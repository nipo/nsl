===========================================
GTR12_QUADB semantics decoded from IPgen
===========================================

This document records what we learned by paired-diffing Gowin IP
generator outputs across a parameter sweep. The raw evidence is in
``gtr_ports.csv`` / ``gtr_ports.rst`` (primitive port connections
per configuration) and ``csr_writes.csv`` / ``csr_writes.rst``
(bitstream-time CSR register writes per configuration).

The sweep covers:

- protocol: USB3, 1000BASE-X, 10GBASE-R, JESD204B, custom 8b10b
- reference clock: refclk0 pad, refclk1 pad, fabric-input (refin),
  MIPI clock (mclk)
- reference clock rate: 50 MHz, 100 MHz, 125 MHz, 156.25 MHz
- PLL: QPLL0, QPLL1, CPLL
- lane: 0, 1, 2, 3
- polarity: TX-swap, RX-swap, both, none
- multi-protocol per quad: USB3 + USB3, USB3 + 1000BASE-X (with
  shared and split reference clocks)
- channel bonding: JESD204B 4-lane

Headline findings
=================

Configuration is overwhelmingly CSR-driven, not fabric-driven
------------------------------------------------------------

Of the 275 ``GTR12_QUADB`` ports, **only 40 vary across the 21
sampled configurations**. The remaining 235 are wizard-baked tie-offs
to constants (mostly ground). The 40 varying ports are almost
entirely per-lane datapath wires (TX data, TX valid, fabric clocks,
PCS resets, FIFO read-enable, PMA reset) plus the AHB/UPAR bring-up.

Per-lane runtime control inputs the primitive *appears* to expose —
``FABRIC_LNn_CTRL_I[42:0]``, ``FABRIC_LNn_RATE_I[1:0]``,
``FABRIC_LNn_PD_I[2:0]``, the ``_I_H`` variants of all three — are
tied to zero in **every** configuration. Lane rate, encoding,
polarity invert, line equalisation, power state: none of this comes
from the fabric. It is all written to CSR addresses at bitstream
load time.

Practical consequence: the VHDL backend should *not* expose generics
or fabric inputs for these knobs. Instead, the protocol adapter
(through the APB master plumbed into ``GTR12_UPARA``) writes the
relevant CSR addresses during init.

The one exception we observed: 1000BASE-X drives
``FABRIC_LN1_CTRL_I`` and ``FABRIC_LN1_CTRL_I_H`` from named wires
(``q0_fabric_ln1_ctrl_i``, ``q0_fabric_ln1_ctrl_i_h``) when 1000BASE-X
is placed on lane 1. This is the only configuration in the sample
where a CTRL_I lane port is non-zero. Likely runtime auto-negotiation
or speed control; needs follow-up if we ever add a 1000BASE-X
adapter.

Reference clock selectors are unused at the fabric level
--------------------------------------------------------

``FABRIC_REFCLK_INPUT_SEL_I[2:0]`` and
``FABRIC_REFCLK1_INPUT_SEL_I[2:0]`` are tied to ``"000"`` in every
configuration, including the ones explicitly using refclk1, the
"refin" fabric clock, and the "mclk" MIPI clock. The fabric-side mux
selectors that the port names imply are not used. Refclk source
selection is entirely CSR-driven.

PLL reset / power signals are unused at the fabric level
--------------------------------------------------------

``FABRIC_CMU0_RESETN_I``, ``FABRIC_CMU1_RESETN_I``,
``FABRIC_CMU0_PD_I``, ``FABRIC_CMU1_PD_I``,
``FABRIC_CMU0_IDDQ_I``, ``FABRIC_CMU1_IDDQ_I`` are all tied to ground
in every configuration. Same for the per-lane CPLL trio
(``FABRIC_LNn_CPLL_RESETN_I``, ``_PD_I``, ``_IDDQ_I``). The PLL
bring-up and ready handshake are managed via CSR registers, not via
the apparently-named fabric reset signals.

The relevant backend correction: the first cut of
``transceiver_group_gw5a.vhd`` had ``FABRIC_CMU0_RESETN_I`` connected
to ``reset_n_i`` and ``FABRIC_LNn_CPLL_PD_I`` tied to ``gw_vcc``
(powering down). The wizard never asserts either: both go to ``gw_gnd``.
This commit corrects those tie-offs.

``FABRIC_POR_N_I`` is similarly tied to ground in every configuration,
despite its name suggesting it is a power-on reset input. The backend
was driving it from ``reset_n_i``; corrected to ``gw_gnd``.

AHB/UPAR bring-up is per-protocol-IP, not per-group
---------------------------------------------------

``AHB_RSTN``, ``CK_AHB_I`` and ``TEST_DEC_EN`` are tied to ground in
6 of the 21 sampled configurations and driven by named wires
(``ahb_rstn_o``, ``q0_fabric_cm_life_clk_o``, ``quad_cfg_test_dec_en``)
in the other 15. The ground-tied ones are exactly the configurations
where the wizard does *not* instantiate ``GTR12_UPARA``: 10GBASE-R,
custom 8b10b (all four polarity variants), and JESD204B. All USB3
configurations instantiate ``GTR12_UPARA`` and bring up its clock /
reset / test-decoder-enable signals.

Interpretation: ``GTR12_UPARA`` is only required when a protocol
needs runtime CSR access. Bitstream init writes are not enough for
USB3 (which goes through the wizard's per-protocol IP for power-state
and equalizer training), but 10GBASE-R, JESD204B and custom 8b10b
configurations function with init-only CSR writes. Our backend has
to make UPARA optional: emit it when the APB master port is
non-trivially used, omit it otherwise.

CSR address space carries most of the per-configuration delta
-------------------------------------------------------------

Of the 515 distinct CSR addresses written by the wizard's init
sequence, **76 vary across configurations**. The other 439 are
common init writes (PMA biasing, internal clock dividers, default
register values for unused features, etc.). The 76 varying writes
are where refclk routing, line rate, encoding mode, polarity invert
and analog tuning actually live.

Decoding the 76-address subset by which configuration axis they
correlate with (refclk source, PLL choice, line rate, protocol,
polarity, lane) is the next analysis pass. See
``csr_writes.rst`` for the raw per-address per-config table.

What this means for the backend
================================

The VHDL backend's job is narrower than the primitive port count
suggests:

1. **Wire the data path and clock plumbing**: per-lane ``TXDATA_I``,
   ``TX_VLD_IN``, ``FABRIC_TX_CLK``, ``FABRIC_RX_CLK``,
   ``PCS_TX_RST``, ``PCS_RX_RST``, ``RX_IF_FIFO_RDEN``, ``RSTN_I``
   (PMA reset). These are the only inputs the wizard actually uses.

2. **Tie off everything else to the wizard's defaults**, primarily
   ``gw_gnd``. This avoids fighting the CSR-driven configuration.
   The current commit aligns the tie-offs with the decoded wizard
   behaviour.

3. **Plumb the APB master through to ``GTR12_UPARA``** so the
   protocol adapter (or a CSR ROM if init-only suffices) can write
   the relevant subset of the 515-address space. Optionally make
   ``GTR12_UPARA`` instantiation conditional on whether the adapter
   actually uses it.

4. **For each adapter we write, ship a CSR init ROM** with the
   correct subset of address-value pairs for that protocol /
   refclk / PLL / rate. The script ``build/support/gw5a_decode/``
   produces the raw table; an adapter-specific filter selects the
   subset.

Backend audit (status against the reference)
============================================

``build/support/gw5a_decode/audit_vhd.py`` cross-checks our
``transceiver_group_gw5a.vhd`` instantiation against the reference
table. The audit suppresses a few categories of intentional
architectural difference:

- Differential pad ports (``LN[0-3]_TX[MP]_O``, ``LN[0-3]_RX[MP]_I``,
  ``REFCLK[PM][01]_I``) are entity ports on our side; the wizard
  routes them through synthesis-tool magic and so ties them to
  ground at the wrapper level. No actual mismatch.
- ``LANE[0-3]_ALIGN_TRIGGER`` and ``LANE[1-3]_CHBOND_START`` are
  exposed by our backend through the lane record for adapters that
  need manual word alignment or non-default channel bonding
  mastership. The wizard never drives them in our sample but
  exposure is harmless when the adapter ties to '0'.

After these filters, one mismatch remains — a primitive input the
wizard sometimes drives but our current backend ties to a constant:

``CLK_VIQ_I``
   Two-bit selector for an *alternative reference clock source* (a
   fabric-side clock pad or a MIPI clock pad), used by the ``refin``
   and ``mclk`` configurations. The wizard wires this as
   ``{mclk_i,gw_gnd}`` or ``{gw_gnd,gpio_refclk_i}`` rather than the
   usual ``{gw_gnd,gw_gnd}``. Supporting non-pad refclks in our
   backend requires adding optional ``mipi_clock_i`` /
   ``fabric_refclk_i`` ports on the entity (or surfacing
   ``CLK_VIQ_I`` directly) and selecting the source from
   ``group.config_t``.

``FABRIC_LN1_CTRL_I_H`` and ``LANE0_FABRIC_C2I_CLK`` are no longer
in the mismatch list: ``lane.tx_master_t`` gained ``control_h`` and
``c2i_clock`` fields that the GW5A backend wires through to the
matching primitive inputs. Adapters that don't need them leave the
fields at '0' (1000BASE-X drives ``control_h`` on the lane it's
placed on; custom 8b10b drives ``c2i_clock``).

``TEST_DEC_EN`` is no longer in the mismatch list: the GW5A
backend now instantiates ``GTR12_UPARA`` through
``apb_upar_bridge_gw5a``, which surfaces the primitive's
``QUAD_CFG_TEST_DEC_EN`` output and the ``AHB_RSTN_O`` reset that
feed back into the companion ``GTR12_QUADB``. The APB clock is
the buffered ``FABRIC_CM_LIFE_CLK_O`` loopback the wizard uses
(exposed on the entity as ``apb_clock_o``).

97 primitive outputs we have at ``open`` are wired to internal
named signals by the wizard. The wires feed either the protocol
IPs (for status monitoring, 64b/66b helpers) or ``GTR12_UPARA``
(for AHB/UPAR clocking and reset). Leaving them ``open`` is
correct as long as we do not need to consume the signal in our
adapter; auditing them is a per-adapter concern as we build out
each protocol.

Reproduction
============

To regenerate this analysis from new IPgen outputs::

   python3.13 build/support/gw5a_decode/decode.py \\
       --src /path/to/ipgen/projects \\
       --out lib/nsl_transceiver/group/gw5a_decoded

To audit a backend file against the reference table::

   python3.13 build/support/gw5a_decode/audit_vhd.py \\
       --vhd lib/nsl_transceiver/group/transceiver_group_gw5a.vhd \\
       --reference lib/nsl_transceiver/group/gw5a_decoded/gtr_ports.csv

The decode script ignores subdirectories without ``serdes.v``
(wizard stubs from invalid options).
