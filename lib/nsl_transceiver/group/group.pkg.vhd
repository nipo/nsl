library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_io, nsl_amba;

-- Configuration types and component declaration for a transceiver
-- group: a cluster of lanes sharing PLLs, reference clock routing
-- and a configuration interface, as exposed by a vendor primitive.
-- The transceiver_group component is the portable contract; each
-- vendor provides one entity+architecture matching it (one of which
-- is selected at build time by the project's hwdep / target_part
-- variables).
package group is

  constant max_lane_count_c : natural := 8;
  constant max_pll_count_c : natural := 4;
  constant max_ref_clock_count_c : natural := 4;
  constant max_user_clock_group_count_c : natural := max_lane_count_c;

  type pll_config_t is
  record
    enabled : boolean;
    ref_clock_index : natural;
    target_vco_mhz : natural;
  end record;

  type pll_config_vector is array (natural range <>) of pll_config_t;

  constant disabled_pll_c : pll_config_t := (
    enabled => false,
    ref_clock_index => 0,
    target_vco_mhz => 0
    );

  type config_t is
  record
    lane_count : natural range 0 to max_lane_count_c;
    pll_count : natural range 0 to max_pll_count_c;
    ref_clock_count : natural range 0 to max_ref_clock_count_c;
    user_clock_group_count : natural range 0 to max_user_clock_group_count_c;
    plls : pll_config_vector(0 to max_pll_count_c-1);
    lanes : nsl_transceiver.lane.config_vector(0 to max_lane_count_c-1);
  end record;

  function config(
    plls : pll_config_vector;
    lanes : nsl_transceiver.lane.config_vector;
    ref_clock_count : natural;
    user_clock_group_count : natural
    ) return config_t;

  -- Target-agnostic intra-config consistency check. A vendor
  -- architecture additionally asserts legality against its primitive
  -- (which PLL can drive which lane at which line rate, etc.) in
  -- its architecture body.
  function is_valid(cfg : config_t) return boolean;

  -- Portable transceiver group component. One vendor entity matching
  -- this declaration is compiled into the working library based on
  -- the project's hwdep / target_part variables. The vendor entity
  -- asserts at elaboration that the supplied config matches the
  -- vendor primitive's shape (lane count, PLL count, etc.).
  component transceiver_group is
    generic(
      config_c : config_t
      );
    port(
      reset_n_i : in std_ulogic;

      ref_clock_i : in nsl_io.diff.diff_pair_vector(0 to config_c.ref_clock_count-1);

      lane_tx_o : out nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);
      lane_rx_i : in nsl_io.diff.diff_pair_vector(0 to config_c.lane_count-1);

      lane_tx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);
      lane_rx_clock_o : out std_ulogic_vector(0 to config_c.lane_count-1);

      tx_m_i : in nsl_transceiver.lane.tx_master_vector(0 to config_c.lane_count-1);
      tx_s_o : out nsl_transceiver.lane.tx_slave_vector(0 to config_c.lane_count-1);
      rx_m_o : out nsl_transceiver.lane.rx_master_vector(0 to config_c.lane_count-1);
      rx_s_i : in nsl_transceiver.lane.rx_slave_vector(0 to config_c.lane_count-1);

      pma_reset_n_i : in std_ulogic_vector(0 to config_c.lane_count-1);

      -- APB clock for the user-facing master, sourced internally
      -- from the vendor primitive's housekeeping clock. The APB
      -- master and any companion logic on the configuration bus
      -- must clock on this output.
      apb_clock_o : out std_ulogic;
      apb_reset_n_i : in std_ulogic;
      apb_m_i : in nsl_amba.apb.master_t;
      apb_s_o : out nsl_amba.apb.slave_t
      );
  end component;

end package group;

package body group is

  function config(
    plls : pll_config_vector;
    lanes : nsl_transceiver.lane.config_vector;
    ref_clock_count : natural;
    user_clock_group_count : natural
    ) return config_t
  is
    variable ret : config_t;
  begin
    ret.lane_count := lanes'length;
    ret.pll_count := plls'length;
    ret.ref_clock_count := ref_clock_count;
    ret.user_clock_group_count := user_clock_group_count;
    ret.plls := (others => disabled_pll_c);
    ret.lanes := (others => nsl_transceiver.lane.disabled_lane_c);
    for i in 0 to plls'length-1 loop
      ret.plls(i) := plls(plls'low + i);
    end loop;
    for i in 0 to lanes'length-1 loop
      ret.lanes(i) := lanes(lanes'low + i);
    end loop;
    return ret;
  end function;

  function is_valid(cfg : config_t) return boolean
  is
  begin
    for i in 0 to cfg.lane_count-1 loop
      if not cfg.lanes(i).enabled then
        next;
      end if;
      if cfg.lanes(i).pll_index >= cfg.pll_count then
        return false;
      end if;
      if not cfg.plls(cfg.lanes(i).pll_index).enabled then
        return false;
      end if;
      if cfg.lanes(i).ref_clock_index >= cfg.ref_clock_count then
        return false;
      end if;
      if cfg.lanes(i).user_clock_group_index >= cfg.user_clock_group_count then
        return false;
      end if;
    end loop;
    for i in 0 to cfg.pll_count-1 loop
      if not cfg.plls(i).enabled then
        next;
      end if;
      if cfg.plls(i).ref_clock_index >= cfg.ref_clock_count then
        return false;
      end if;
    end loop;
    return true;
  end function;

end package body group;
