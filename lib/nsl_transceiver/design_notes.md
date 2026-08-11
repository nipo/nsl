# nsl_transceiver — intent and state

State snapshot: commit `d0e3faa8`, branch `nipo/transceivers`.

## Purpose

FPGA vendors ship hard transceiver macroblocks that bundle, in one
primitive:

* zero to N PLLs,
* N serializers and N deserializers (today, typically 4 of each),
* a varying amount of offloaded protocol support (8b/10b, 64b/66b,
  scramblers, gearboxes),
* a varying amount of serial stream handling (CDR, comma alignment,
  elastic buffering, channel bonding).

Every vendor exposes this with a different port map, a different
naming scheme and a different split between what the macroblock does
and what the fabric must do. `nsl_transceiver` provides one portable
contract on top of them, so that link- and transport-layer
infrastructure can be written once and built for several targets.
Target families in scope: Gowin GW5A, Altera Agilex 5, Xilinx
7-series.

## Scope and non-goals

**In scope**: a portable component whose shape maps onto one vendor
macroblock, a portable per-lane signal contract, and protocol
adapters written against that contract.

**Not in scope**: supporting every configuration every vendor
permits. The goal is sharing most of an implementation across
targets, not universal coverage. A protocol that a given target
cannot do natively is simply not available on that target.

**Not on the critical path**: dynamic reconfiguration. It is needed
to bring a link up but is not on the datapath, so it is not
optimized. It is uniformly a set of read/write registers behind a
vendor-specific bus; the abstraction is a wrapper onto a standard bus
(APB), and higher-level sequencing is expected to live in software or
in a per-adapter init ROM.

## Design decisions and their rationale

### Group, not "quad"

The portable unit is a *group* (`nsl_transceiver.group`), matching one
vendor macroblock. "Quad" is the count that happens to be common in
current silicon; it has been 2 in the past and is likely to be 6 or 8
in the future, so it does not belong in a type name.

### Structure mirrors what the vendor wizards produce

Gowin's IP generator handles a multi-protocol split quad by emitting:
one protocol-dependent IP per lane group, one clock/PLL configuration
for the whole quad, and RTL glue between the two. The result is one
macroblock per quad whose port map is the union of all user-side
connections. `nsl_transceiver` uses the same decomposition:

* one entity that maps to one macroblock (`transceiver_group`),
* a group-wide config (`group.config_t`) holding PLLs, reference
  clock routing and lane count,
* an array of per-lane configs (`lane.config_t`),
* an array of per-lane IO records carrying only what the group entity
  and the protocol adapters need to agree on.

This matters because one quad routinely serves several protocols at
once — 10G Ethernet on one lane and USB3 on another, or four lanes
carrying 2×10G to two different peers — each with its own reference
clock and PLL assignment.

### Worst-case dimensioning with don't-cares

`lane` records carry the maximum width of every field; a lane's
`config_t` declares which subset is meaningful, and unused bits are
driven to `'-'`. This is the construct already used by
`nsl_amba.axi4_stream` and `nsl_amba.axi4_mm`, and synthesis prunes
it well.

The chosen worst case targets 40 Gb/s per lane against a 150 MHz
fabric clock — a serial/parallel ratio near 256 — with room for two
ancillary bits per data byte:

* `max_data_byte_count_c = 32` (32×8 data bits),
* one `aux_t` byte per data byte,
* handshake, lane status and opaque control/status carriers.

### Split TX and RX, shared PMA reset

TX and RX are two independent unidirectional bundles rather than a
single master/slave pair, because a lane's TX and RX are not
necessarily owned by the same adapter. A daisy-chain ring — four
devices where each TX feeds the next device's RX — needs them wired
separately. PMA reset stays shared, because one primitive serves both
directions; an application splitting TX and RX ownership combines the
two reset requests itself.

### The lane config states the required interface, not the implementation

`lane.config_t` describes what the adapter needs at the transceiver
boundary: parallel width, encoding, alignment patterns, line rate,
PLL and refclk routing, analog tuning. Whether the vendor primitive
provides a feature natively or the group architecture supplies it in
fabric logic is an implementation detail of the backend, not
something the user configures.

This is deliberate: vendor communication IPs are themselves a mix of
macroblock functionality and fabric glue. There is no performance
argument for the vendor's version over a portable one — hand-placed
timing-critical IP is not what modern vendor IP actually is.

### Records rather than AXI4-Stream at the lane boundary

Using AXI4-Stream for the transceiver/protocol boundary was
considered — `tuser` can carry K and error bits predictably, and it
would bring width adapters, FIFOs and CDCs for free. Dedicated
records were chosen instead, because the lane boundary carries a
large amount of non-stream sideband (PMA/PCS resets, lock and
alignment status, alignment triggers, channel-bonding control) that
does not fit a stream interface. An AXI4-Stream profile remains a
reasonable *adapter* to write on top of the lane records.

### Portability by build-system file selection

There is one `nsl_transceiver.group` package with a portable
`transceiver_group` component declaration, and one vendor entity +
architecture per target in its own `transceiver_group_<vendor>.vhd`.
The subset Makefile gates each vendor file on `hwdep` and
`target_part`, so exactly one lands in the working library. There is
no `group_gw5a` package to name in user code.

When a backend eventually needs to express primitive constraints
(supported rates per PLL, VCO ranges, lane-to-PLL routing rules), the
pattern to follow is the one used by
`lib/nsl_clocking/pll/pll_config_series67.pkg.vhd` (declaration) and
`pll_config_series7.vhd` (backend body), with raw constants under
`lib/nsl_hwdep/`. See `group/index.rst` for the full description.
That layering is not in place yet, on purpose — there is no
vendor-specific content in the package today.

### Reference clock binding by opaque identifier

Reference clock topology is hardware-dependent, so the group takes an
array of refclk inputs plus a generic array of identifiers saying
what each entry is:

```vhdl
inst: nsl_transceiver.group.transceiver_group
  generic map(
    ref_clock_c => (0 => clock_id("ref0"), 1 => clock_id("fabric"))
    )
  port map(
    ref_clock_i(0) => ref_clock_0_i,
    ref_clock_i(1) => fabric_clock_i
    );
```

`nsl_transceiver.target.clock_id(name)` is declared target-agnostically
and has one target-specific package body, selected the same way the
group backend is. Names are portable strings; the returned integers
are implementation-defined. This avoids adding one entity port per
possible clock source, and avoids ambiguity about which port a
configuration actually uses.

### Reset polarity

`reset_n_i` everywhere. Mixed reset polarity within one block is not
acceptable.

## Package layout and current state

| Package | State |
|---|---|
| `lane` | Complete signal contract and config types. No entities. |
| `target` | `clock_id()` declaration + GW5A body. |
| `group` | Portable component + config types + `is_valid()`. GW5A backend implemented. |
| `dynamic_reconfig` | **Declaration only** — `apb_arbiter` component is declared with no entity behind it. |
| `cuff_adapter` | Implemented, untested, uninstantiated. |

### `lane`

`config_t` covers enable, `data_byte_count`, encoding
(`RAW`/`8B10B`/`64B66B`/`128B130B`), line rate, PLL index, refclk
index, user clock group index, per-direction polarity invert,
loopback mode, `sync_t` and `analog_t`.

`sync_t` carries comma value/mask/length, a `comma_negated` flag,
clock-correction pattern and idle pattern. `comma_negated` exists
because transceivers without runtime RX polarity invert need to be
given a negated comma pattern at elaboration when the upstream device
sends with reversed differential polarity.

`tx_master_t` carries `control` and `control_h` — two opaque sideband
vectors, because some primitives expose two independent runtime
control inputs per lane — plus `c2i_clock`, an adapter-driven per-lane
fabric clock needed by encodings where the protocol IP owns the
lane's interface clock.

### `group`

`config_t` holds lane count, PLL count, user clock group count, a
`pll_config_vector` and a `lane.config_vector`. `is_valid()` performs
target-agnostic checks only (each enabled lane refers to an enabled,
in-range PLL and an in-range user clock group); refclk index bounds
are checked in the vendor architecture, since the refclk count is
carried by the `ref_clock_c` generic rather than by `config_t`.

The component exposes per-lane differential pads, per-lane TX/RX
fabric clocks, the four lane record vectors, per-lane PMA reset, and
an APB slave port for configuration. `apb_clock_o` is an *output*:
the configuration bus clock comes from inside the primitive, so the
user-side APB master must clock on it.

## GW5A backend

`transceiver_group_gw5a.vhd` wraps `GTR12_QUADB`. Elaboration asserts
exactly 4 lanes, at most 2 PLLs (CMU0/CMU1), at most 4 refclk entries,
config validity, per-lane encoding in {RAW, 8B10B, 64B66B}, and
`data_byte_count` in {1, 8}.

Wired: per-lane TX data packing (8 data bytes at `TXDATA_I[63:0]`,
per-byte aux bit 0 at `[71:64]`), symmetric RX unpacking with
`rx_data[87:72]` surfaced through `rx_master.status`, TX valid /
`RX_IF_FIFO_RDEN` handshake against the primitive's FIFO
almost-full/almost-empty flags, PMA and PCS resets, align trigger,
channel-bond start, opaque `CTRL_I` / `CTRL_I_H` / `C2I_CLK`, per-lane
BUFGs on the recovered and derived fabric clocks, `CLK_VIQ_I` fabric
refclk slots, and CMU lock status onto `tx_slave.pll_lock`.

`apb_upar_bridge_gw5a.vhd` instantiates `GTR12_UPARA` and maps
`nsl_amba.apb.apb_slave` onto the 24-bit-address / 32-bit-data UPAR
bus. It also surfaces `AHB_RSTN_O` and `QUAD_CFG_TEST_DEC_EN`, which
feed back into the companion `GTR12_QUADB`. The APB clock is the
buffered `FABRIC_CM_LIFE_CLK_O` loopback.

### How the primitive was decoded

Gowin's documentation for `GTR12_QUADB` is thin and its port naming is
inconsistent (`LN[0-3]` and `LANE[0-3]` both appear; some two-element
arrays are spelled as an unsuffixed port plus a `1`-suffixed port,
e.g. `FABRIC_REFCLK_INPUT_SEL_I` / `FABRIC_REFCLK1_INPUT_SEL_I`).

Semantics were therefore recovered empirically: 21 IP-generator
configurations were swept across protocol (USB3, 1000BASE-X,
10GBASE-R, JESD204B, custom 8b/10b), refclk source and rate, PLL
choice, lane index, polarity swap, multi-protocol split quads and
4-lane channel bonding; the generated `serdes.v` files were
paired-diffed. `build/support/gw5a_decode/decode.py` produces the
tables in `group/gw5a_decoded/`; `audit_vhd.py` cross-checks the
backend's port map against them.

The load-bearing conclusions:

* **Configuration is CSR-driven, not fabric-driven.** Only 40 of 275
  primitive ports vary across the sweep, and they are almost all
  datapath. Per-lane `CTRL_I`, `RATE_I`, `PD_I` and their `_H`
  variants are tied to zero in every configuration; so are the refclk
  input selectors, the CMU reset/power signals, the per-lane CPLL
  trio, and `FABRIC_POR_N_I` despite its name. Rate, encoding,
  polarity invert, equalization and power state all come from CSR
  writes at bitstream load time.
* **The one observed exception**: 1000BASE-X drives
  `FABRIC_LN1_CTRL_I` and `FABRIC_LN1_CTRL_I_H` from named wires when
  placed on lane 1 — probably auto-negotiation or speed control.
  Needs follow-up if a 1000BASE-X adapter is ever written.
* **`GTR12_UPARA` is optional.** It is instantiated only for protocols
  needing runtime CSR access (all USB3 configs). 10GBASE-R, JESD204B
  and custom 8b/10b work from init-only CSR writes.

CSR contents are generated from a TOML file, and TOML→CSR tooling
already exists in the build system; sweeping TOML input to decode CSR
semantics is possible but was not pursued.

## Adapters

`cuff_adapter` bridges `nsl_cuff.protocol.cuff_code_vector` (10-bit
8b/10b words) onto the lane records, using
`nsl_line_coding.ibm_8b10b` to decode on the way in and encode on the
way out, at `data_byte_count = 1`. It exists because CUFF currently
runs on Spartan-6/7 `ISERDES2`/`OSERDES2` — a basic 10:1 IO serdes
that caps the achievable rate — and a real transceiver should take it
higher. The stated first milestone is a working design at 1.25 Gb/s
before anything faster.

## Gaps and next steps

Functional gaps, roughly in dependency order:

1. **No CSR init path.** The backend wires UPAR but nothing writes it.
   Each adapter needs a CSR init ROM holding the address/value subset
   for its protocol, refclk, PLL and rate. The next analysis pass is
   correlating the varying CSR addresses against the configuration
   axes (refclk source, PLL, rate, protocol, polarity, lane).
2. **`dynamic_reconfig.apb_arbiter` has no implementation.** Only the
   component declaration exists. It is needed as soon as more than one
   adapter in a group wants CSR access.
3. **Nothing instantiates the library.** No testbench under `tests/`,
   no synthesis project under `example/`. Neither the GW5A backend nor
   `cuff_adapter` has been elaborated in anger.
4. **`cuff_adapter` ignores flow control.** It drives `tx.valid` to a
   constant `'1'`, never inspects `tx_s_i.ready`, and never inspects
   `rx_m_i.valid`. This matches CUFF's word-per-cycle contract only if
   the transceiver's elastic FIFOs never assert back-pressure; it
   needs either a justification comment or real handshaking.
5. **`lane.config_t` fields are declared but unenforced** by the GW5A
   backend: `polarity_invert_*`, `loopback`, `sync` and `analog` reach
   no primitive input, consistent with the finding that these are
   CSR-driven — but the backend currently accepts a config requesting
   them and silently does nothing.
6. **Only one backend exists.** Agilex 5 and 7-series are unstarted;
   the portable contract has therefore been validated against exactly
   one primitive.

7. **`tx_pack` / `rx_unpack` unconditionally cover bytes 0..7**
   regardless of `data_byte_count`. For a one-byte lane this pushes
   the adapter's `'-'` fill into the primitive: harmless for
   synthesis, noisy in simulation.
