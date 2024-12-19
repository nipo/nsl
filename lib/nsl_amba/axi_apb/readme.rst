
AXI4-MM to APB bridge
=====================

These components allow conversion of an AXI4-MM bus to an APB bus.
Two variants exist, one doing conversion to a single APB master port
(`axi4_apb_bridge`), the other also doing transaction routing
depending on address (`axi4_apb_bridge_dispatch`).  The latter is
functionally equivalent to passing `axi4_apb_bridge` to
`apb_dispatch`, but will have better timing closure results.

Address lookup is handled the same way as the rest of the amba
library, see `address <../address/>`_ for more info.