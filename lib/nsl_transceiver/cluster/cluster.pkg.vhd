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
  constant max_refclk_count_c : natural := 8;
  constant max_user_clock_group_count_c : natural := max_lane_count_c;

  -- One PLL of the cluster. ``ref_clock_index`` picks the fabric
  -- refclk port feeding it, as a position in the cluster's
  -- ref_clock_c binding, and ``ref_clock_mhz`` is the rate of that
  -- clock: the frequency the multiplier and divider search starts
  -- from. ``target_vco_mhz`` is the VCO frequency the search aims
  -- for, which the vendor architecture rounds to what its primitive
  -- can reach.
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

  -- Rate of one of the cluster's fabric refclk ports, named by its
  -- position in the ref_clock_c binding. Entries describe the board,
  -- so a clock a PLL multiplies has its rate stated here as well as
  -- in the PLL configuration, and the two have to agree; is_valid
  -- rejects a configuration where they do not. Clocks no PLL
  -- multiplies, such as the housekeeping clock a backend needs to
  -- time its reset sequence, are described here only.
  type refclk_config_t is
  record
    ref_clock_index : natural;
    ref_clock_mhz : natural;
  end record;

  type refclk_config_vector is array (natural range <>) of refclk_config_t;

  constant disabled_refclk_c : refclk_config_t := (
    ref_clock_index => 0,
    ref_clock_mhz => 0
    );

  type config_t is
  record
    lane_count : natural range 0 to max_lane_count_c;
    pll_count : natural range 0 to max_pll_count_c;
    refclk_count : natural range 0 to max_refclk_count_c;
    user_clock_group_count : natural range 0 to max_user_clock_group_count_c;
    plls : pll_config_vector(0 to max_pll_count_c-1);
    refclks : refclk_config_vector(0 to max_refclk_count_c-1);
    lanes : nsl_transceiver.lane.config_vector(0 to max_lane_count_c-1);
  end record;

  function config(
    plls : pll_config_vector;
    refclks: refclk_config_vector;
    lanes : nsl_transceiver.lane.config_vector;
    user_clock_group_count : natural
    ) return config_t;

  -- Rate of the clock on a given fabric refclk port, from the
  -- refclks entry describing it. Zero when the configuration does
  -- not describe that port.
  function ref_clock_mhz(cfg : config_t; port_index : natural) return natural;

  -- Position in a cluster's ref_clock_c binding of the port carrying
  -- a given target clock identifier. For a vendor architecture that
  -- needs a specific clock of its target, such as the housekeeping
  -- clock its reset sequencer counts on, rather than whichever clock
  -- a lane happens to be configured with.
  function refclk_port(ref_clock_c : integer_vector;
                       id : natural) return natural;

  -- Target-agnostic intra-config consistency check. A vendor
  -- architecture additionally asserts legality against its primitive
  -- (which PLL can drive which lane at which line rate, etc.) in
  -- its architecture body.
  function is_valid(cfg : config_t) return boolean;

  -- Shape of the configuration bus every vendor cluster exposes on
  -- apb_m_i / apb_s_o. Declared here rather than per backend so a
  -- configuration master can be written once: a cluster whose
  -- primitive has no runtime configuration path still answers, with
  -- an error response, instead of leaving the master waiting.
  constant csr_config_c : nsl_amba.apb.config_t
    := nsl_amba.apb.apb4_config(address_width => 24,
                                data_bus_width => 32,
                                strb => true,
                                ready => true,
                                err => true);

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
      -- must clock on this output. It runs even on a target whose
      -- primitive has no configuration path, so the master's own
      -- reset and error handling stay clocked.
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
    refclks: refclk_config_vector;    
    lanes : nsl_transceiver.lane.config_vector;
    user_clock_group_count : natural
    ) return config_t
  is
    variable ret : config_t;
  begin
    ret.lane_count := lanes'length;
    ret.pll_count := plls'length;
    ret.refclk_count := refclks'length;
    ret.user_clock_group_count := user_clock_group_count;
    ret.plls := (others => disabled_pll_c);
    ret.refclks := (others => disabled_refclk_c);
    ret.lanes := (others => nsl_transceiver.lane.disabled_lane_c);
    for i in 0 to plls'length-1 loop
      ret.plls(i) := plls(plls'low + i);
    end loop;
    for i in 0 to refclks'length-1 loop
      ret.refclks(i) := refclks(refclks'low + i);
    end loop;    
    for i in 0 to lanes'length-1 loop
      ret.lanes(i) := lanes(lanes'low + i);
    end loop;
    return ret;
  end function;

  function ref_clock_mhz(cfg : config_t; port_index : natural) return natural
  is
  begin
    for i in 0 to cfg.refclk_count-1 loop
      if cfg.refclks(i).ref_clock_index = port_index then
        return cfg.refclks(i).ref_clock_mhz;
      end if;
    end loop;
    return 0;
  end function;

  function refclk_port(ref_clock_c : integer_vector;
                       id : natural) return natural
  is
  begin
    for i in ref_clock_c'range loop
      if ref_clock_c(i) = id then
        return i - ref_clock_c'low;
      end if;
    end loop;
    assert false
      report "transceiver_cluster: the target clock this backend needs"
      & " is not bound to any refclk port"
      severity failure;
    return 0;
  end function;

  -- Whether a refclk port exists at all is up to the vendor
  -- architecture: the port count is carried by the
  -- transceiver_cluster ref_clock_c generic, not by config_t.
  function is_valid(cfg : config_t) return boolean
  is
  begin
    for i in 0 to cfg.pll_count-1 loop
      if not cfg.plls(i).enabled then
        next;
      end if;
      -- A PLL multiplying a clock whose rate the board description
      -- does not give, or gives differently, would be programmed for
      -- a line rate it cannot reach.
      if ref_clock_mhz(cfg, cfg.plls(i).ref_clock_index)
        /= cfg.plls(i).ref_clock_mhz then
        return false;
      end if;
      if cfg.plls(i).ref_clock_mhz = 0 then
        return false;
      end if;
    end loop;
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
