# nsl_bnoc.chunked_link

A credit-based framing layer carrying a pair of `nsl_bnoc.framed`
streams, full-duplex, over a byte pipe where one end owns all the
clocking.

## 1. Scope

`chunked_link` is the byte-level protocol shared by serial transports
built on a master-clocked, full-duplex exchange:

- JTAG continuous Shift-DR runs (`nsl_jtag.continuous_transport`),
- SPI transactions (CS-delimited, byte-clocked).

The **master** end drives the link clock and decides when an exchange
starts and stops; the **slave** end is purely reactive and cannot
stall. One uninterrupted exchange is called a **batch** (a Shift-DR
run, a CS assertion window). This layer provides, in both directions:

- packet framing (`last` boundaries preserved),
- reliable in-order payload delivery,
- flow control, so neither receiver's buffer overflows.

It does **not** provide integrity checking; the medium is assumed
error-free, and an application that cannot assume that carries its own
check inside the payload.

The transport below provides:

- a full-duplex byte pipe with a common clock,
- batch delimitation (start and end events on both ends),
- byte alignment of the received stream (a JTAG transport bit-hunts a
  sync pattern; SPI gets alignment from CS for free).

## 2. Wire format

Within a batch, each direction carries **protocol bytes**: a
back-to-back sequence of frames with no gaps. A **frame** is one
header byte followed by the bytes that header implies — none (idle,
pad), a fixed operand (credit, tx-level: 2 bytes), or a data body
(1..64 bytes). The next header immediately follows the previous
frame's last byte. Framing is position-based, not parse-based: a bit
error corrupts payload but not byte alignment.

Header byte; the top bit selects payload vs control. Direction column:
`M>S` = master to slave only, `S>M` = slave to master only.

| Header        | Dir  | Meaning                                | Follows           |
|---------------|------|----------------------------------------|-------------------|
| `0b00nnnnnn`  | both | **Data, not last**, `n+1` bytes        | 1..64 data bytes  |
| `0b01nnnnnn`  | both | **Data, last** (end-of-packet)         | 1..64 data bytes  |
| `0b11110000`  | both | **Idle** (one byte of filler)          | -                 |
| `0b11110001`  | both | **Credit** (absolute balance)          | 2 bytes, LE       |
| `0b11110010`  | S>M  | **TX fill level** (absolute, bytes)    | 2 bytes, LE       |
| `0b11111ppp`  | M>S  | **Set alignment pad** = `ppp`          | - (pad 0..7)      |
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
  cannot express a zero-byte frame, so it would have no source semantic.
- Data body is contiguous: a software receiver `memcpy`s the run
  directly.
- **Credit** means different things by direction but uses one opcode:
  master to slave it grants the slave a TX budget (section 4.2); slave
  to master it advertises the slave's RX buffer credit (section 4.1).
  Absolute, little-endian.
- **TX fill level** gives the master visibility of the slave's pending
  TX backlog, both to size its budget grants (a budget-starved backlog
  would otherwise stay invisible) and to know when it can stop
  clocking. Absolute; a value of 0 means "nothing to send". Safely
  lost. The slave emits it (a) after each end-of-packet chunk, and (b)
  in place of idle whenever the backlog differs from the last value it
  advertised — including once per batch, since a batch start marks the
  advertisement stale in case the previous one fell in a truncated
  batch tail.
- Credit and fill-level fields are 16-bit, little-endian; a single batch
  payload stays well under that, so the width is headroom, not a target.
- **Set alignment pad** belongs to transports that need sub-byte
  alignment of the slave-to-master stream (JTAG; see
  `nsl_jtag/continuous_transport/continuous_transport.md`). Other
  transports never send it and ignore it on reception.

## 3. Idempotency of control

All control frames carry **absolute state** (never deltas), so a
control frame lost in the truncated tail of a batch costs only
freshness, never correctness:

- Credit = "your balance **is** N", not "+N".
- TX fill level = "I currently hold N bytes", a snapshot.

The slave refreshes the master's view **as often as it can**, using
credit frames in place of idle whenever it has no data.

## 4. Flow control

The two directions have different failure modes and use different
credit notions. Credit may be refreshed **at any time** within a batch,
not only at the start.

### 4.1 Master -> slave data: RX buffer credit

The slave grants the master credit equal to **free space in its RX
buffer**, in data bytes; only data bytes consume it (headers, idle and
control operands are not buffered). The master never sends more data
than its current balance.

Credit reaches the master delayed by the link flight time, so the
master derates each received value by a pessimistic bound on the data
it may have emitted during that flight
(`chunked_link_master_framer.flight_margin_c`), then debits every
further data byte it sends. Because only the master fills this buffer
and only the slave's system side drains it, a stale credit can only
under-utilise, never overflow.

The slave, symmetrically, derates its advertised credit by the bytes
already in its receive pipeline but not yet reflected in the free-space
count, so it can never over-grant.

This credit is **running**: it persists across batch boundaries (the
RX buffer is continuous in the system clock domain), so a new batch may
open with the master already holding credit and sending data
immediately.

### 4.2 Slave -> master data: TX budget

The master reads every byte it clocks, so it has no RX-overflow
problem; the budget exists to keep payload out of the part of a batch
that is never delivered — the untransmitted tail of a truncated JTAG
shift, or a frame cut by CS deassertion on SPI. A budget grant of N
(credit frame, master to slave) means: *"I, the master, guarantee at
least N bytes plus margin of further clocking before I end the
batch."* Every byte the slave emits against current budget is
therefore guaranteed to be delivered, and a batch is always
self-contained: the master's parser needs no state across batches.

A batch opens with the slave holding **zero** budget: at batch start
the master has not yet committed to a length, so the slave must send
only control until the first grant arrives. The slave decrements
budget per emitted byte and must not start a data frame it cannot
finish within the remaining budget; the remainder of its chunk is
re-headered under a later grant (or in the next batch).

Margins are deliberately **pessimistic** fixed constants; generosity
costs a fraction of a percent of throughput, so there is no need to
characterise them tightly.

## 5. Components

- `chunked_link_chunker` — stages a framed TX stream into chunks of up
  to 64 bytes so data headers can carry the byte count and last flag.
  Shared by both senders.
- `chunked_link_slave_framer` — slave-side sender: data gated by the
  TX budget, credit/tx-level refreshes as filler.
- `chunked_link_master_framer` — master-side sender: data gated by the
  slave's RX credit, budget grants on demand through a handshake (the
  caller owns the clocking commitment a grant implies).
- `chunked_link_deframer` — receive decoder for either end; every
  known opcode's operands are consumed, each end wires only the
  strobes meaningful for its direction.

Senders present exactly one byte at all times (idle at worst) and
advance on the transport's `byte_ready` strobe, so a transport may
latch bytes at any pace, including not at all while a batch is
suspended.
