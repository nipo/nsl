library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_altera, nsl_clocking;
use nsl_amba.axi4_mm.all;
use nsl_altera.hps.all;

entity hps_wrapper is
  generic(
    h2f_used_c : boolean := false;
    h2f_config_c : nsl_amba.axi4_mm.config_t := h2f_native_config_c;
    lwh2f_used_c : boolean := false;
    lwh2f_config_c : nsl_amba.axi4_mm.config_t := lwh2f_native_config_c;
    f2h_used_c : boolean := false;
    f2h_config_c : nsl_amba.axi4_mm.config_t := f2h_native_config_c;
    f2h_ace_c : hps_f2h_ace_t := hps_f2h_non_coherent_c;
    f2sdram_used_c : boolean := false;
    f2sdram_config_c : nsl_amba.axi4_mm.config_t := f2sdram_native_config_c;
    emif_used_c : boolean := false;

    warm_reset_handshake_c : boolean := false
    );
  port(
    hps_io_i : in std_ulogic_vector(0 to 47) := (others => '0');
    hps_io_o : out std_ulogic_vector(0 to 47);
    hps_io_io : inout std_logic_vector(0 to 47);

    reset_n_o : out std_ulogic;
    user_clock_o : out std_ulogic_vector(0 to 1);
    warm_reset_request_o : out std_ulogic;
    warm_reset_ack_i : in std_ulogic := '0';

    h2f_clock_i : in std_ulogic := '0';
    h2f_reset_n_o : out std_ulogic;
    h2f_o : out nsl_amba.axi4_mm.master_t;
    h2f_i : in nsl_amba.axi4_mm.slave_t := h2f_slave_idle_c;

    lwh2f_clock_i : in std_ulogic := '0';
    lwh2f_reset_n_o : out std_ulogic;
    lwh2f_o : out nsl_amba.axi4_mm.master_t;
    lwh2f_i : in nsl_amba.axi4_mm.slave_t := lwh2f_slave_idle_c;

    f2h_clock_i : in std_ulogic := '0';
    f2h_reset_n_o : out std_ulogic;
    f2h_i : in nsl_amba.axi4_mm.master_t := f2h_master_idle_c;
    f2h_o : out nsl_amba.axi4_mm.slave_t;

    f2sdram_clock_i : in std_ulogic := '0';
    f2sdram_reset_n_o : out std_ulogic;
    f2sdram_i : in nsl_amba.axi4_mm.master_t := f2sdram_master_idle_c;
    f2sdram_o : out nsl_amba.axi4_mm.slave_t;

    emif_o : out hps_emif_o_t;
    emif_i : in hps_emif_i_t := hps_emif_i_idle_c;

    irq_i : in std_ulogic_vector(0 to 63) := (others => '0');
    gp_i : in std_ulogic_vector(31 downto 0) := (others => '0');
    gp_o : out std_ulogic_vector(31 downto 0)
    );
end entity;

architecture beh of hps_wrapper is

  function data_width(cfg : config_t) return natural
  is
  begin
    return 8 * 2 ** cfg.data_bus_width_l2;
  end function;

  -- Checks an NSL config of a bridge where the HPS is master can be
  -- derived from native one.
  function m_config_check(name : string; cfg, native : config_t;
                          min_data_width : natural) return boolean
  is
  begin
    assert data_width(cfg) >= min_data_width
      and cfg.data_bus_width_l2 <= native.data_bus_width_l2
      report name & ": data width must be from " & integer'image(min_data_width)
      & " to " & integer'image(data_width(native))
      severity failure;
    assert cfg.address_width <= native.address_width
      report name & ": address width must be " & integer'image(native.address_width) & " or less"
      severity failure;
    assert cfg.id_width >= native.id_width
      report name & ": ID width must be " & integer'image(native.id_width) & " or more"
      severity failure;
    assert cfg.len_width >= native.len_width
      report name & ": max_length must be " & integer'image(2 ** native.len_width) & " or more"
      severity failure;
    assert cfg.has_size and cfg.has_burst
      report name & ": size and burst are mandatory"
      severity failure;
    return true;
  end function;

  -- Checks an NSL config of a bridge where the HPS is slave is a subset
  -- of native one.
  function s_config_check(name : string; cfg, native : config_t;
                          min_data_width : natural) return boolean
  is
  begin
    assert data_width(cfg) >= min_data_width
      and cfg.data_bus_width_l2 <= native.data_bus_width_l2
      report name & ": data width must be from " & integer'image(min_data_width)
      & " to " & integer'image(data_width(native))
      severity failure;
    assert cfg.address_width <= native.address_width
      report name & ": address width must be " & integer'image(native.address_width) & " or less"
      severity failure;
    assert cfg.id_width <= native.id_width
      report name & ": ID width must be " & integer'image(native.id_width) & " or less"
      severity failure;
    assert cfg.len_width <= native.len_width
      report name & ": max_length must be " & integer'image(2 ** native.len_width) & " or less"
      severity failure;
    assert cfg.user_width <= native.user_width
      report name & ": user width must be " & integer'image(native.user_width) & " or less"
      severity failure;
    return true;
  end function;

  constant h2f_ok_c : boolean := m_config_check("h2f", h2f_config_c, h2f_native_config_c, 32);
  constant lwh2f_ok_c : boolean := m_config_check("lwh2f", lwh2f_config_c, lwh2f_native_config_c, 32);
  constant f2h_ok_c : boolean := s_config_check("f2h", f2h_config_c, f2h_native_config_c, 256);
  constant f2sdram_ok_c : boolean := s_config_check("f2sdram", f2sdram_config_c, f2sdram_native_config_c, 64);

  function slave_fwd_idle return hps_slave_fwd_t
  is
    variable ret : hps_slave_fwd_t;
  begin
    ret.awid := (others => '0');
    ret.awaddr := (others => '0');
    ret.awlen := (others => '0');
    ret.awsize := (others => '0');
    ret.awburst := (others => '0');
    ret.awlock := '0';
    ret.awcache := (others => '0');
    ret.awprot := (others => '0');
    ret.awqos := (others => '0');
    ret.awregion := (others => '0');
    ret.awuser := (others => '0');
    ret.awvalid := '0';
    ret.wdata := (others => '0');
    ret.wstrb := (others => '0');
    ret.wlast := '0';
    ret.wuser := (others => '0');
    ret.wvalid := '0';
    ret.bready := '0';
    ret.arid := (others => '0');
    ret.araddr := (others => '0');
    ret.arlen := (others => '0');
    ret.arsize := (others => '0');
    ret.arburst := (others => '0');
    ret.arlock := '0';
    ret.arcache := (others => '0');
    ret.arprot := (others => '0');
    ret.arqos := (others => '0');
    ret.arregion := (others => '0');
    ret.aruser := (others => '0');
    ret.arvalid := '0';
    ret.rready := '0';
    return ret;
  end function;

  function master_bwd_idle return hps_master_bwd_t
  is
    variable ret : hps_master_bwd_t;
  begin
    ret.awready := '0';
    ret.wready := '0';
    ret.bid := (others => '0');
    ret.bresp := (others => '0');
    ret.bvalid := '0';
    ret.arready := '0';
    ret.rid := (others => '0');
    ret.rdata := (others => '0');
    ret.rresp := (others => '0');
    ret.rlast := '0';
    ret.rvalid := '0';
    return ret;
  end function;

  function master_idle(cfg : config_t) return master_t
  is
  begin
    return (
      aw => address_defaults(cfg),
      w => write_data_defaults(cfg),
      b => handshake_defaults(cfg),
      ar => address_defaults(cfg),
      r => handshake_defaults(cfg)
      );
  end function;

  function slave_idle(cfg : config_t) return slave_t
  is
  begin
    return (
      aw => handshake_defaults(cfg),
      w => handshake_defaults(cfg),
      b => write_response_defaults(cfg),
      ar => handshake_defaults(cfg),
      r => read_data_defaults(cfg)
      );
  end function;

  signal h2f_reset_s : std_ulogic;
  signal warm_reset_request_n_s, warm_reset_ack_n_s : std_ulogic;
  signal irq_s : std_ulogic_vector(63 downto 0);
  signal h2f_fwd_s, lwh2f_fwd_s : hps_master_fwd_t;
  signal h2f_bwd_s, lwh2f_bwd_s : hps_master_bwd_t;
  signal f2h_fwd_s, f2sdram_fwd_s : hps_slave_fwd_t;
  signal f2h_bwd_s, f2sdram_bwd_s : hps_slave_bwd_t;
  signal reset_n_s : std_ulogic;
  signal h2f_reset_n_s, lwh2f_reset_n_s, f2h_reset_n_s, f2sdram_reset_n_s : std_ulogic;
begin

  assert not f2sdram_used_c or emif_used_c
    report "nsl_altera.hps: f2sdram needs the HPS EMIF"
    severity failure;

  atoms: nsl_altera.hps.hps_atoms
    generic map(
      h2f_used_c => h2f_used_c,
      h2f_data_width_c => data_width(h2f_config_c),
      lwh2f_used_c => lwh2f_used_c,
      lwh2f_data_width_c => data_width(lwh2f_config_c),
      f2h_used_c => f2h_used_c,
      f2h_data_width_c => data_width(f2h_config_c),
      f2h_ace_c => f2h_ace_c,
      f2sdram_used_c => f2sdram_used_c,
      f2sdram_data_width_c => data_width(f2sdram_config_c),
      emif_used_c => emif_used_c
      )
    port map(
      hps_io_i => hps_io_i,
      hps_io_o => hps_io_o,
      hps_io_io => hps_io_io,
      h2f_reset_o => h2f_reset_s,
      user_clock_o => user_clock_o,
      warm_reset_request_n_o => warm_reset_request_n_s,
      warm_reset_ack_n_i => warm_reset_ack_n_s,
      irq_i => irq_s,
      gp_i => gp_i,
      gp_o => gp_o,
      h2f_clock_i => h2f_clock_i,
      h2f_o => h2f_fwd_s,
      h2f_i => h2f_bwd_s,
      lwh2f_clock_i => lwh2f_clock_i,
      lwh2f_o => lwh2f_fwd_s,
      lwh2f_i => lwh2f_bwd_s,
      f2h_clock_i => f2h_clock_i,
      f2h_i => f2h_fwd_s,
      f2h_o => f2h_bwd_s,
      f2sdram_clock_i => f2sdram_clock_i,
      f2sdram_i => f2sdram_fwd_s,
      f2sdram_o => f2sdram_bwd_s,
      emif_o => emif_o,
      emif_i => emif_i
      );

  reset_n_s <= not h2f_reset_s;
  reset_n_o <= reset_n_s;

  warm_reset_request_o <= not warm_reset_request_n_s;
  warm_reset_ack_n_s <= not warm_reset_ack_i when warm_reset_handshake_c
                        else warm_reset_request_n_s;

  irq: for i in 0 to 63
  generate
    irq_s(i) <= irq_i(i);
  end generate;

  h2f_gen: if h2f_used_c
  generate
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => h2f_clock_i,
        data_i => reset_n_s,
        data_o => h2f_reset_n_s
        );

    bridge: nsl_altera.hps.hps_master_bridge
      generic map(
        config_c => h2f_config_c
        )
      port map(
        clock_i => h2f_clock_i,
        reset_n_i => h2f_reset_n_s,
        ps_i => h2f_fwd_s,
        ps_o => h2f_bwd_s,
        axi_o => h2f_o,
        axi_i => h2f_i
        );
  end generate;

  h2f_none: if not h2f_used_c
  generate
    h2f_reset_n_s <= '0';
    h2f_bwd_s <= master_bwd_idle;
    h2f_o <= master_idle(h2f_config_c);
  end generate;

  h2f_reset_n_o <= h2f_reset_n_s;

  lwh2f_gen: if lwh2f_used_c
  generate
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => lwh2f_clock_i,
        data_i => reset_n_s,
        data_o => lwh2f_reset_n_s
        );

    bridge: nsl_altera.hps.hps_master_bridge
      generic map(
        config_c => lwh2f_config_c
        )
      port map(
        clock_i => lwh2f_clock_i,
        reset_n_i => lwh2f_reset_n_s,
        ps_i => lwh2f_fwd_s,
        ps_o => lwh2f_bwd_s,
        axi_o => lwh2f_o,
        axi_i => lwh2f_i
        );
  end generate;

  lwh2f_none: if not lwh2f_used_c
  generate
    lwh2f_reset_n_s <= '0';
    lwh2f_bwd_s <= master_bwd_idle;
    lwh2f_o <= master_idle(lwh2f_config_c);
  end generate;

  lwh2f_reset_n_o <= lwh2f_reset_n_s;

  f2h_gen: if f2h_used_c
  generate
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => f2h_clock_i,
        data_i => reset_n_s,
        data_o => f2h_reset_n_s
        );

    bridge: nsl_altera.hps.hps_slave_bridge
      generic map(
        config_c => f2h_config_c
        )
      port map(
        clock_i => f2h_clock_i,
        reset_n_i => f2h_reset_n_s,
        axi_i => f2h_i,
        axi_o => f2h_o,
        ps_o => f2h_fwd_s,
        ps_i => f2h_bwd_s
        );
  end generate;

  f2h_none: if not f2h_used_c
  generate
    f2h_reset_n_s <= '0';
    f2h_fwd_s <= slave_fwd_idle;
    f2h_o <= slave_idle(f2h_config_c);
  end generate;

  f2h_reset_n_o <= f2h_reset_n_s;

  f2sdram_gen: if f2sdram_used_c
  generate
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => f2sdram_clock_i,
        data_i => reset_n_s,
        data_o => f2sdram_reset_n_s
        );

    bridge: nsl_altera.hps.hps_slave_bridge
      generic map(
        config_c => f2sdram_config_c
        )
      port map(
        clock_i => f2sdram_clock_i,
        reset_n_i => f2sdram_reset_n_s,
        axi_i => f2sdram_i,
        axi_o => f2sdram_o,
        ps_o => f2sdram_fwd_s,
        ps_i => f2sdram_bwd_s
        );
  end generate;

  f2sdram_none: if not f2sdram_used_c
  generate
    f2sdram_reset_n_s <= '0';
    f2sdram_fwd_s <= slave_fwd_idle;
    f2sdram_o <= slave_idle(f2sdram_config_c);
  end generate;

  f2sdram_reset_n_o <= f2sdram_reset_n_s;

end architecture;
