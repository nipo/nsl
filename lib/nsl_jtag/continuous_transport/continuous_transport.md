# nsl_jtag.continuous_transport

A high-throughput, full-duplex byte transport between a JTAG master
(ATE) and a custom data register in an FPGA TAP.

## 1. Overview

`continuous_transport` keeps the TAP in a **single, continuous
Shift-DR run** and streams bytes back-to-back in both directions over
the same shift: TDI carries ATE -> TAP, TDO carries TAP -> ATE, sharing
TCK as a common bit clock. One uninterrupted Shift-DR run is called a
**batch** (typically one adapter "shift" command).

Keeping the shift continuous amortises the adapter round-trip over a
whole batch, which is what makes throughput usable over high-latency
links (USB JTAG adapters batch large transfers and cannot make per-bit
decisions). The cost is that the TAP state machine no longer frames
anything for us, so this layer rebuilds byte framing, flow control and
delivery guarantees in-band. The rest of this document is that
protocol.

The system-side interface is `nsl_bnoc.framed`
(`{data[7:0], last, valid}` + `ready`); `last` marks end-of-packet.

## 2. Topology, latency, and who knows what

During Shift-DR the whole scan path is one shift register:

```
ATE.tdo --> [dev .. dev] --> our.TDI ... our.TDO --> [dev .. dev] --> ATE.tdi
            \___ U bits ___/                         \___ D bits ___/
```

Every other device is in BYPASS (1 bit each), so:

- **U** = upstream BYPASS bits = latency, in bits, from the ATE output
  to our TDI.
- **D** = downstream BYPASS bits = latency, in bits, from our TDO to
  the ATE input.

Two facts drive the whole design:

1. **The ATE owns all timing and geometry.** It controls TCK, decides
   when a batch ends, and knows U and D (it must, to drive the chain).
   The TAP knows neither and cannot stall TCK. Therefore **the TAP is
   purely reactive**: every decision that needs geometry or "when does
   the batch end" is made by the ATE and pushed to the TAP as protocol
   state.

2. **The trailing U/D bits of a batch are never clocked through.** When
   the ATE stops, the last U bits it shifted are stranded in upstream
   BYPASS and the next Capture-DR overwrites them; symmetrically the
   last D bits we drove on TDO never reach the ATE. This region carries
   no payload — the credit discipline of section 6 keeps payload out of
   it by construction — so it is a property to design against, not a
   loss to recover from.

## 3. What this layer guarantees

- **Byte framing**: a locked byte boundary for the whole batch.
- **Reliable, in-order payload delivery.** Under the credit and timing
  discipline of section 6, no data byte is ever emitted into a region
  that will not be delivered. Payload is not lost.
- **Flow control**: neither receiver's buffer overflows.

It does **not** provide integrity checking. Bit errors on the JTAG
medium are assumed negligible (the same medium already carries megabit
configuration streams unprotected). An application that cannot assume
that should carry its own check inside the payload.

Control frames (idle, credit, fill-level, pad) may go undelivered in
the trailing region of a batch. All of them carry **absolute state**
(never deltas), so a lost control frame costs only freshness, never
correctness.

## 4. Wire format

A batch, in emission order on each wire:

```
[ alignment pad : 0-7 bits ]   (TDO only, see section 7)
[ preamble      : 0x55 x P  ]   framing reference, P >= 2 (host may send more)
[ SOF           : 0xd5      ]   start-of-frame, marks byte 0
[ protocol bytes ...        ]   frames, back-to-back, until the batch ends
```

After the SOF the rest of the batch is **protocol bytes**: a
back-to-back sequence of frames with no gaps. A **frame** is one header
byte (section 4.1) followed by the bytes that header implies — none
(idle, pad), a fixed operand (credit, fill-level: 2 bytes), or a data
body (1..64 bytes). The next header immediately follows the previous
frame's last byte.

The receiver bit-searches for `preamble..SOF` (before lock only BYPASS
zeros precede it, so the pattern is unambiguous), then **counts** bytes
from the SOF for the rest of the batch. Framing within a batch is
position-based, not parse-based: a bit error corrupts payload but not
byte alignment.

There is **no clock recovery** here: TCK is forwarded, so both ends
sample directly on TCK edges and every bit is reliable from the first.
The preamble exists only to (a) give the SOF's alternation-break a
preceding alternating reference so it is detectable, (b) give the host
a known pattern to find the TDO bit-phase, and (c) harmlessly absorb
the Capture-DR -> Shift-DR entry (the first TDO bit is the captured
value). All three need only a couple of bits, hence P = 2 is ample.

JTAG shifts LSB-first. `0x55` on the wire is a steady alternating
`1,0,1,0,...`. `0xd5` (LSB-first `1,0,1,0,1,0,1,1`) repeats the same
alternation but ends in two equal bits, breaking the pattern — that
break is how the receiver locks the SOF. (Same idea as the Ethernet
preamble / `0xD5` SFD.)

### 4.1 Frame encoding

Header byte; the top bit selects payload vs control. Direction column:
`TDI` = ATE -> TAP only, `TDO` = TAP -> ATE only, `both` = either.

| Header        | Dir  | Meaning                                | Follows           |
|---------------|------|----------------------------------------|-------------------|
| `0b00nnnnnn`  | both | **Data, not last**, `n+1` bytes        | 1..64 data bytes  |
| `0b01nnnnnn`  | both | **Data, last** (end-of-packet)         | 1..64 data bytes  |
| `0b11110000`  | both | **Idle** (one byte of filler)          | -                 |
| `0b11110001`  | both | **Credit** (absolute balance)          | 2 bytes, LE       |
| `0b11110010`  | TDO  | **TX fill level** (absolute, bytes)    | 2 bytes, LE       |
| `0b11111ppp`  | TDI  | **Set TDO alignment pad** = `ppp`      | - (pad 0..7)      |
| else          | both | **Reserved** (receiver: treat as Idle) | -                 |

The data/control split is bit 7 (`0` = data, `1` = control). Defined
control opcodes are clustered under the `0b1111xxxx` prefix on purpose,
so the large blocks `0b10xxxxxx` (64), `0b110xxxxx` (32) and
`0b1110xxxx` (16) stay fully reserved and aligned — a future opcode can
then carry an inline value in its low bits (as the pad already does)
without fragmenting them.

Notes:

- `last` is folded into the data header, so a packet boundary is atomic
  with its data. There is no zero-length-packet marker: `nsl_bnoc.framed`
  and AXI4-Stream cannot express a zero-byte frame, so it would have no
  source semantic.
- Data body is contiguous: the host `memcpy`s the run directly.
- **Credit** means different things by direction but uses one opcode:
  on TDI it grants the TAP a TX budget (section 6.2); on TDO it grants
  the ATE RX buffer credit (section 6.1). Absolute, little-endian.
- **TX fill level** gives the ATE visibility of the TAP's pending TX
  backlog so it knows whether to keep clocking. Absolute; a value of 0
  means "nothing to send" (so no separate empty marker is needed).
  Safely lost. The TAP emits it (a) after each end-of-packet chunk, as an
  early "here is what remains" hint the ATE can use to size the next
  batch, and (b) in place of idle when the backlog is empty, so the
  "you can stop" signal is re-advertised reliably even if the
  end-of-packet one fell in a truncated batch tail.
- Credit and fill-level fields are 16-bit, little-endian; a single batch
  payload stays well under that (4-8 KiB is ample), so the width is
  headroom, not a target.
- **Set TDO alignment pad** encodes the 3-bit pad directly in the
  opcode (no payload byte). It updates a shadow register; the value
  transfers to the active pad on the next **Update-DR** (batch close)
  and applies from the following batch's preamble (section 7).

## 5. Idempotency of control

All control frames carry absolute state, so losing one costs at most
freshness:

- Credit = "your balance **is** N", not "+N".
- TX fill level = "I currently hold N bytes", a snapshot.

The TAP refreshes the ATE's RX credit (section 6.1) **as often as it
can**, using credit frames in place of idle whenever it has no data —
this keeps the ATE's view maximally fresh and the link maximally
utilised.

## 6. Flow control

The two directions have different failure modes and use different
credit notions. Credit may be refreshed **at any time** within a batch,
not only at the start.

### 6.1 ATE -> TAP (data on TDI): RX buffer credit

The TAP grants the ATE credit equal to **free space in its RX FIFO**,
in data bytes; only data bytes consume it (headers/idle/control are not
buffered). The ATE never sends more data than its current balance.

Credit travels on TDO and reaches the host delayed by D, so each credit
frame is **anchored to the bitstream byte position at which the TAP
emitted it** — a position the host knows from its TCK count and D. The
host treats the value as free space *as of that position* and debits
every data byte it has shifted past it. Because only the ATE fills this
FIFO and only the system side drains it, a stale credit can only
under-utilise, never overflow.

The TAP **derates** its advertised credit by a fixed implementation
constant (`tap_rx_latency_c`) covering bytes already in its input
pipeline but not yet reflected in the free-space count, so it can never
over-grant.

This credit is **running**: it persists across batch boundaries (the RX
FIFO is continuous in the system clock domain), so a new batch may open
with the ATE already holding credit and sending data immediately.

### 6.2 TAP -> ATE (data on TDO): TX budget

The ATE has no RX-overflow problem (it reads everything it clocks); the
budget exists only to keep payload out of the untransmitted tail
(section 2, fact 2). A budget grant of N (credit frame on TDI) means:
*"I, the ATE, guarantee at least `N*8 + margin` further TCK cycles
before I leave Shift-DR,"* where `margin >= U + D + tap_tx_latency_c`
covers the grant's flight to the TAP, the TAP's internal latency, and
the return flight of the emitted bytes. Every byte the TAP emits
against current budget is therefore guaranteed to reach the host.

A batch opens with the TAP holding **zero** budget: at batch start the
ATE has not yet committed to a length, so the TAP must send only control
(preamble, SOF, credit refreshes, idle) until the first grant arrives.
The TAP decrements budget per emitted byte and must not start a data
frame it cannot finish within the remaining budget.

`tap_tx_latency_c` and `tap_rx_latency_c` are deliberately
**pessimistic** fixed constants; there is no need to characterise them
tightly. They only make the ATE stop sending data a little earlier and
clock a few extra bits before closing a batch — at a 4 KiB batch, even
16 cycles in each direction is ~0.1% overhead, so generosity is free.

## 7. Byte alignment

Byte framing only yields host `memcpy` if protocol byte boundaries land
on host-buffer byte boundaries.

- **TX (host -> device): free.** The host lays out header+data
  byte-aligned in its buffer; the device re-derives boundaries from the
  SOF. U merely delays arrival.
- **RX (device -> host): needs a pad.** The device stream arrives offset
  by D bits, landing at `D mod 8` inside the host's buffer bytes. The
  device inserts a sticky 0-7 bit **alignment pad** (the `Set TDO
  alignment pad` control) so that `(D + pad) mod 8 == 0`; the host drops
  `(D+pad)/8` whole leading bytes and the rest is aligned. The pad is
  committed on Update-DR (section 4.1).

Bootstrapping: the host may compute the pad a priori from the known
chain geometry (D), or converge empirically — lock the SOF, measure the
actual bit offset, software-realign that one batch (a constant funnel
shift over 32/64-bit words, cheap even for large batches), then write
the sticky pad so subsequent batches arrive aligned.

## 8. Reset and TLR

Test-Logic-Reset is a hard reset of the whole block. On TLR the slave
drops framing, flushes both FIFOs, and zeroes the TAP's TX budget; any
bytes in flight at that instant are discarded. The component asserts an
active-low `reset_n_o`, resynchronised to the system clock, so user
logic can be reset alongside the transport.
