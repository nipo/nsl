library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_clocking, nsl_i2c, nsl_io, nsl_usb;

-- The SCCB bus of a Sipeed PMOD-DVP camera on a USB port, with what
-- a sensor needs before it answers: a clock to run from, out of
-- power down and out of reset.
--
-- The camera spans two Pmods.  Its control connector, carrying SCCB,
-- the reset and power down lines, the sensor clock, the sync lines
-- and D7, sits on J7; the data connector, on J6, is all sensor
-- outputs and is left alone.
--
-- Which row of J7 the odd pins of the camera connector land on
-- depends on which way up the module went in.  S1 swaps the two rows
-- and puts the sensor through reset again; the done LED is lit when
-- the rows are swapped.
entity main is
  port (
    clk_i: in std_ulogic;

    usb_dxp_io : inout std_logic;
    usb_dxn_io : inout std_logic;
    usb_rxdp_i : in std_logic;
    usb_rxdn_i : in std_logic;
    usb_pullup_en_o : out std_logic;
    usb_term_dp_io : inout std_logic;
    usb_term_dn_io : inout std_logic;

    s_n_i: in std_ulogic_vector(1 to 2);

    j7_io: inout std_logic_vector(1 to 8);

    done_led_o: inout std_logic;
    ready_led_o: inout std_logic
    );
end main;

architecture arch of main is

  constant clock_ext_hz_c : integer := 50e6;
  constant clock_usb_hz_c : integer := 60e6;
  constant clock_cam_hz_c : integer := 24e6;

  use nsl_clocking.pll.all;

  constant pll_config_c: pll_config_t := pll_config(
    input_hz => clock_ext_hz_c,
    o0 => pll_output(clock_usb_hz_c),
    o1 => pll_output(clock_cam_hz_c));

  constant stream_config_c: nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => 1, last => true);

  -- Button sampling period, longer than it bounces for
  constant sample_period_c : integer := clock_ext_hz_c / 1000;
  -- How long the sensor is held in reset, with its clock running
  constant reset_period_c : integer := clock_ext_hz_c / 100;

  type regs_t is
  record
    sample_left: integer range 0 to sample_period_c - 1;
    button: std_ulogic;
    swapped: std_ulogic;
    reset_left: integer range 0 to reset_period_c - 1;
  end record;

  signal r, rin: regs_t;

  signal utmi_s : nsl_usb.utmi.utmi8_bus;

  signal clock_ext_s, clock_usb_s, clock_cam_s : std_ulogic;
  signal pll_clock_s : std_ulogic_vector(0 to pll_config_c.output_count - 1);
  signal startup_reset_n_s, board_reset_n_s : std_ulogic;
  signal reset_n_s, app_reset_n_s : std_ulogic;
  signal online_s : std_ulogic;

  signal cmd_framed_s, rsp_framed_s: nsl_bnoc.framed.framed_req_t;
  signal cmd_framed_ack_s, rsp_framed_ack_s: nsl_bnoc.framed.framed_ack_t;

  signal cmd_s, rsp_s: nsl_amba.axi4_stream.master_t;
  signal cmd_ack_s, rsp_ack_s: nsl_amba.axi4_stream.slave_t;

  signal i2c_o_s: nsl_i2c.i2c.i2c_o;
  signal i2c_i_s: nsl_i2c.i2c.i2c_i;
  signal button_s: std_ulogic;
  signal swapped_s, cam_reset_n_s: std_ulogic;
  signal j7_s: nsl_io.io.tristated_vector(1 to 8);
  signal j7_in_s: std_ulogic_vector(1 to 8);

begin

  clock_ext_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  startup: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_ext_s,
      reset_n_o => startup_reset_n_s
      );

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_ext_s,
      data_i => startup_reset_n_s,
      data_o => board_reset_n_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => board_reset_n_s,

      clock_o => pll_clock_s,
      locked_o => reset_n_s
      );

  clock_usb_s <= pll_clock_s(0);
  clock_cam_s <= pll_clock_s(1);

  hs_phy: work.softphy.gw_usb2_phy
    port map(
      clock_i => clock_usb_s,
      reset_n_i => reset_n_s,

      usb_dxp_io => usb_dxp_io,
      usb_dxn_io => usb_dxn_io,
      usb_rxdp_i => usb_rxdp_i,
      usb_rxdn_i => usb_rxdn_i,
      usb_pullup_en_o => usb_pullup_en_o,
      usb_term_dp_io => usb_term_dp_io,
      usb_term_dn_io => usb_term_dn_io,

      utmi_i => utmi_s.sie2phy,
      utmi_o => utmi_s.phy2sie
      );

  func: nsl_usb.func.vendor_framed_pair
    generic map(
      vendor_id_c => x"dead",
      product_id_c => x"12c0",
      device_version_c => x"0100",
      manufacturer_c => "Nipo",
      product_c => "NSL camera SCCB probe",
      serial_c => "cam",
      hs_supported_c => true,
      phy_clock_rate_c => clock_usb_hz_c,
      self_powered_c => false
      )
    port map(
      phy_system_o => utmi_s.sie2phy.system,
      phy_system_i => utmi_s.phy2sie.system,
      phy_data_o => utmi_s.sie2phy.data,
      phy_data_i => utmi_s.phy2sie.data,

      reset_n_i => reset_n_s,

      app_reset_n_o => app_reset_n_s,
      online_o => online_s,

      out_o => cmd_framed_s,
      out_i => cmd_framed_ack_s,

      in_i => rsp_framed_s,
      in_o => rsp_framed_ack_s
      );

  cmd_adapter: nsl_bnoc.axi_adapter.framed_to_axi4_stream
    port map(
      clock_i => clock_usb_s,
      reset_n_i => app_reset_n_s,

      framed_i => cmd_framed_s,
      framed_o => cmd_framed_ack_s,

      axi_o => cmd_s,
      axi_i => cmd_ack_s
      );

  transactor: nsl_i2c.cbor_transactor.axi4stream_cbor_i2c_controller
    generic map(
      clock_i_hz_c => clock_usb_hz_c,
      target_scl_hz_c => 100000,
      -- SCCB devices stretch, if at all, for a few cycles of their own
      -- clock; this only bounds how long a dead bus takes to report
      stuck_timeout_half_cycles_c => 64,
      stream_config_c => stream_config_c
      )
    port map(
      clock_i => clock_usb_s,
      reset_n_i => app_reset_n_s,

      i2c_o => i2c_o_s,
      i2c_i => i2c_i_s,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,

      rsp_o => rsp_s,
      rsp_i => rsp_ack_s
      );

  rsp_adapter: nsl_bnoc.axi_adapter.axi4_stream_to_framed
    port map(
      clock_i => clock_usb_s,
      reset_n_i => app_reset_n_s,

      axi_i => rsp_s,
      axi_o => rsp_ack_s,

      framed_o => rsp_framed_s,
      framed_i => rsp_framed_ack_s
      );

  button_sync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => 1
      )
    port map(
      clock_i => clock_ext_s,
      data_i(0) => s_n_i(1),
      data_o(0) => button_s
      );

  regs: process(clock_ext_s, board_reset_n_s) is
  begin
    if rising_edge(clock_ext_s) then
      r <= rin;
    end if;

    if board_reset_n_s = '0' then
      r.sample_left <= 0;
      r.button <= '1';
      r.swapped <= '0';
      r.reset_left <= reset_period_c - 1;
    end if;
  end process;

  transition: process(r, button_s) is
  begin
    rin <= r;

    if r.reset_left /= 0 then
      rin.reset_left <= r.reset_left - 1;
    end if;

    if r.sample_left /= 0 then
      rin.sample_left <= r.sample_left - 1;
    else
      rin.sample_left <= sample_period_c - 1;
      rin.button <= button_s;
      if r.button = '1' and button_s = '0' then
        rin.swapped <= not r.swapped;
        rin.reset_left <= reset_period_c - 1;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    swapped_s <= r.swapped;
    if r.reset_left /= 0 then
      cam_reset_n_s <= '0';
    else
      cam_reset_n_s <= '1';
    end if;
  end process;

  -- Camera control connector, by the column of J7 it lands in:
  --
  --   J7 pins     1/5        2/6          3/7         4/8
  --   camera     SDA/SCL   RSTN/VSYNC   PWDN/HREF   D7/XCLK
  --
  -- with the camera's odd pins on 1-4 unless swapped.  Reset and power
  -- down have pull-ups on the module, to its own supply: reset is only
  -- ever pulled down or let go, and power down is held low.
  j7_map: process(swapped_s, cam_reset_n_s, clock_cam_s, i2c_o_s, j7_in_s) is
    variable cam_odd, cam_even: integer;
  begin
    if swapped_s = '1' then
      cam_odd := 4;
      cam_even := 0;
    else
      cam_odd := 0;
      cam_even := 4;
    end if;

    j7_s <= (others => nsl_io.io.to_tristated('0', '0'));

    j7_s(cam_odd + 1) <= nsl_io.io.to_tristated(i2c_o_s.sda);
    j7_s(cam_even + 1) <= nsl_io.io.to_tristated(i2c_o_s.scl);
    j7_s(cam_odd + 2) <= nsl_io.io.to_tristated('0', not cam_reset_n_s);
    j7_s(cam_odd + 3) <= nsl_io.io.to_tristated('0', '1');
    j7_s(cam_even + 4) <= nsl_io.io.to_tristated(clock_cam_s, '1');

    i2c_i_s.sda <= j7_in_s(cam_odd + 1);
    i2c_i_s.scl <= j7_in_s(cam_even + 1);
  end process;

  j7_pad: for i in 1 to 8
  generate
    pad: nsl_io.io.tristated_io_driver
      port map(
        v_i => j7_s(i),
        v_o => j7_in_s(i),
        io_io => j7_io(i)
        );
  end generate;

  ready_led_o <= online_s;
  done_led_o <= swapped_s;

end arch;
