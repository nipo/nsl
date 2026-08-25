library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_io, nsl_amba, nsl_math;
use nsl_math.int_ext.all;

-- Configuration types and component declaration for a transceiver
-- cluster: a set of lanes sharing PLLs, reference clock routing
-- and a configuration interface, as exposed by a vendor primitive.
-- The transceiver_cluster component is the portable contract; each
-- vendor provides one entity+architecture matching it (one of which
-- is selected at build time by the project's hwdep / target_part
-- variables).
package cluster is

  constant max_lane_count_c : natural := 8;
  constant max_pll_count_c : natural := 4;
  constant max_user_clock_group_count_c : natural := max_lane_count_c;

  type pll_config_t is
  record
    enabled : boolean;
    ref_clock_index : natural;
    ref_clock_mhz : natural;
    target_vco_mhz : natural;
  end record;

  type pll_config_vector is array (natural range <>) of pll_config_t;

  constant disabled_pll_c : pll_config_t := (
    enabled => false,
    ref_clock_index => 0,
    ref_clock_mhz => 0,
    target_vco_mhz => 0
    );

  type config_t is
  record
    lane_count : natural range 0 to max_lane_count_c;
    pll_count : natural range 0 to max_pll_count_c;
    user_clock_group_count : natural range 0 to max_user_clock_group_count_c;
    plls : pll_config_vector(0 to max_pll_count_c-1);
    lanes : nsl_transceiver.lane.config_vector(0 to max_lane_count_c-1);
  end record;

  function config(
    plls : pll_config_vector;
    lanes : nsl_transceiver.lane.config_vector;
    user_clock_group_count : natural
    ) return config_t;

  -- Target-agnostic intra-config consistency check. A vendor
  -- architecture additionally asserts legality against its primitive
  -- (which PLL can drive which lane at which line rate, etc.) in
  -- its architecture body.
  function is_valid(cfg : config_t) return boolean;

  -- Portable transceiver cluster component. One vendor entity matching
  -- this declaration is compiled into the working library based on
  -- the project's hwdep / target_part variables. The vendor entity
  -- asserts at elaboration that the supplied config matches the
  -- vendor primitive's shape (lane count, PLL count, etc.).
  component transceiver_cluster is
    generic(
      config_c : config_t;
      -- Reference clock source binding. One entry per fabric-side
      -- refclk port; each carries a target-defined identifier from
      -- nsl_transceiver.target.clock_id(name). The vendor entity
      -- routes ref_clock_i(i) to the primitive input matching
      -- ref_clock_c(i). Lane configurations refer to entries in
      -- this array via lane.config_t.ref_clock_index.
      ref_clock_c : integer_vector
      );
    port(
      reset_n_i : in std_ulogic;

      ref_clock_i : in std_ulogic_vector(0 to ref_clock_c'length-1);

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

end package cluster;

package body cluster is

  function config(
    plls : pll_config_vector;
    lanes : nsl_transceiver.lane.config_vector;
    user_clock_group_count : natural
    ) return config_t
  is
    variable ret : config_t;
  begin
    ret.lane_count := lanes'length;
    ret.pll_count := plls'length;
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

  -- Refclk-index bound checks live in the vendor architecture body
  -- since the refclk count is carried by the transceiver_cluster
  -- ref_clock_c generic, not by config_t.
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
      if cfg.lanes(i).user_clock_group_index >= cfg.user_clock_group_count then
        return false;
      end if;
    end loop;
    return true;
  end function;

end package body cluster;
