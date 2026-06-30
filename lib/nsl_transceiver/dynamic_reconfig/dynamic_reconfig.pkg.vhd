library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

-- Configuration-bus plumbing for transceiver group entities. The
-- vendor-native register access bus is wrapped to APB by a
-- vendor-specific bridge entity (declared elsewhere, alongside the
-- group entity). Per-lane / per-protocol-adapter masters arbitrate
-- access to the single group slave via a static address-space
-- demux.
package dynamic_reconfig is

  -- N APB masters arbitrated into a single APB slave port. Each
  -- master claims an address window in the group's register space,
  -- defined by a (base, mask) pair. A master's transaction is
  -- forwarded with its address unchanged; the demux only selects
  -- which transaction reaches the slave each cycle.
  component apb_arbiter is
    generic(
      master_config_c : nsl_amba.apb.config_t;
      slave_config_c : nsl_amba.apb.config_t;
      master_count_c : natural;
      base_addresses_c : nsl_amba.address.address_vector;
      address_masks_c : nsl_amba.address.address_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      master_i : in nsl_amba.apb.master_vector(0 to master_count_c-1);
      master_o : out nsl_amba.apb.slave_vector(0 to master_count_c-1);

      slave_o : out nsl_amba.apb.master_t;
      slave_i : in nsl_amba.apb.slave_t
      );
  end component;

end package dynamic_reconfig;
