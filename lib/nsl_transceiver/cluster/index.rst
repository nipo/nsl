====================
Transceiver clusters
====================

This subset declares the portable ``transceiver_cluster`` component
and its configuration types. One vendor architecture is compiled
into the working library at a time, selected by the project's
``hwdep`` and ``target_part`` Makefile variables.

Vendor-specific architectures
=============================

Each backend lives in its own ``transceiver_cluster_<vendor>.vhd``
file alongside ``cluster.pkg.vhd``, providing ``entity
transceiver_cluster is ...`` plus an ``architecture <vendor>`` body.
The Makefile gates each vendor file with the relevant
``hwdep`` / ``target_part`` filter so exactly one ends up in the
working library.

A vendor architecture is expected to:

* Assert at elaboration that ``config_c`` matches its primitive's
  fixed shape (lane count, PLL count, reference clock count).
* Assert that any per-lane settings the primitive cannot satisfy
  (encoding, line rate, sync pattern, analog tuning) are rejected
  rather than silently miswired.
* Map the worst-case lane signal records onto the primitive's
  per-lane data / clock / status ports.
* Provide whatever glue the primitive does not handle natively
  (e.g. encoder, scrambler, gearbox) so the lane signal contract
  is fulfilled regardless of which side of the boundary the
  encoding actually lives on.

Per-backend constants (planned)
===============================

When a vendor architecture needs to encode primitive-specific
numeric data — supported line rates per PLL choice, allowed VCO
ranges, lane-to-PLL routing rules, hardware comma-alignment
capability flags, etc. — we apply the same pattern used by the
PLL configuration packages (see
``lib/nsl_clocking/pll/pll_config_series67.pkg.vhd`` for the
declaration and ``pll_config_series7.vhd`` for the
backend-specific body).

The layering for the transceiver cluster would be:

* ``nsl_transceiver.cluster`` package declaration in
  ``cluster.pkg.vhd`` declares both the portable types and any
  function whose answer depends on the backend, e.g.::

    function vendor_supports_encoding(enc : nsl_transceiver.lane.encoding_t)
      return boolean;
    function vendor_max_line_rate_mbps(pll_idx, refclk_hz : natural)
      return natural;

* The ``nsl_transceiver.cluster`` package body lives in the vendor
  file (``transceiver_cluster_<vendor>.vhd`` or a sibling
  ``cluster_<vendor>_body.vhd``). It implements the vendor
  functions, typically by calling into a target-family constants
  package under ``nsl_hwdep``. VHDL allows exactly one package
  body per package; the Makefile guarantees only one vendor body
  file is compiled.

* Raw primitive constants live under
  ``lib/nsl_hwdep/<vendor>_xcvr_config/`` (one file per chip
  family if needed, mirroring how
  ``lib/nsl_hwdep/xc7_config/`` is organised). The vendor
  ``cluster`` body imports them.

* The portable ``is_valid`` function in the package body uses the
  vendor functions to validate intra-config consistency *and*
  primitive-specific legality before elaboration, so a user can
  test their configuration without instantiating the entity.

This layering is deliberately *not* in place yet: there is no
vendor-specific content in the package today, so splitting decl
from body would add ceremony without benefit. Adopt the pattern
the first time a vendor architecture needs to express a real
primitive constraint.
