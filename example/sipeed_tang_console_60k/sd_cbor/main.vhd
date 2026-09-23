library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_clocking, nsl_hwdep, nsl_indication,
  nsl_io, nsl_sdio, nsl_usb;
use nsl_sdio.sdio.all;

-- The SD card socket of the board on a USB port: what arrives is a
-- command stream for the host, and what leaves is the answers to it.
--
-- Nothing here knows what a card is.  The identification sequence,
-- the command set of whatever answers, and what to do about an error
-- all live on the far end of the wire; this is the bus and a way to
-- reach it.
--
-- Framing comes from the bus below: one frame is one transfer, which
-- ends where a short packet does, and the pipe that carries it does
-- its own flow control and its own checking.  So a batch of commands
-- is a frame, the answers to it are a frame, and nothing here has to
-- find the edges of either.
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

    tf_clk_o: out std_ulogic;
    tf_cmd_io: inout std_logic;
    tf_dat_io: inout std_logic_vector(3 downto 0);
    tf_det_i: in std_ulogic;

    done_led_o: inout std_logic;
    ready_led_o: inout std_logic;

    mspi_sck_o : out std_ulogic;
    mspi_cs_n_o, mspi_mosi_io: inout std_logic;
    mspi_miso_i : in std_ulogic
    );
end main;

architecture arch of main is

  constant clock_ext_hz_c : integer := 50e6;
  -- What the bus below wants
  constant clock_usb_hz_c : integer := 60e6;
  -- What the card side runs at.  A bus period is a whole number of
  -- these, so this is what the speeds a card can be clocked at are
  -- reachable from: a quarter of it is default speed, and half of it
  -- is high speed.
  constant clock_app_hz_c : integer := 100e6;

  use nsl_clocking.pll.all;

  constant pll_config_c: pll_config_t := pll_config(
    input_hz => clock_ext_hz_c,
    o0 => pll_output(clock_usb_hz_c),
    o1 => pll_output(clock_app_hz_c));

  constant stream_config_c: nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => 1, last => true);

  signal utmi_s : nsl_usb.utmi.utmi8_bus;

  signal clock_ext_s, clock_usb_s, clock_app_s : std_ulogic;
  signal pll_clock_s : std_ulogic_vector(0 to pll_config_c.output_count - 1);
  signal startup_reset_n_s, board_reset_n_s : std_ulogic;
  signal reset_n_s, app_reset_n_s, app_reset_n_app_s : std_ulogic;
  signal online_s : std_ulogic;

  -- Frames as the bus below hands them over, and the same frames in
  -- the domain the card side runs in
  signal usb_cmd_s, usb_rsp_s: nsl_bnoc.framed.framed_req_t;
  signal usb_cmd_ack_s, usb_rsp_ack_s: nsl_bnoc.framed.framed_ack_t;
  signal cmd_framed_s, rsp_framed_s: nsl_bnoc.framed.framed_req_t;
  signal cmd_framed_ack_s, rsp_framed_ack_s: nsl_bnoc.framed.framed_ack_t;

  signal cmd_s, rsp_s: nsl_amba.axi4_stream.master_t;
  signal cmd_ack_s, rsp_ack_s: nsl_amba.axi4_stream.slave_t;

  signal bus_o_s: sdio_master_o;
  signal bus_i_s: sdio_master_i;
  signal card_present_s: std_ulogic;

begin

  clock_ext_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  -- The buttons of this board sit in the bank the socket is in, and
  -- they are wired for a supply a card cannot take, so the reset this
  -- starts with is its own.
  startup: nsl_hwdep.reset.reset_at_startup
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
  clock_app_s <= pll_clock_s(1);

  -- The reset the bus below asks for reaches the card side as well,
  -- where it is a reset from another domain like any other.
  app_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_app_s,
      data_i => app_reset_n_s,
      data_o => app_reset_n_app_s
      );

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
      product_id_c => x"5d10",
      device_version_c => x"0100",
      manufacturer_c => "Nipo",
      product_c => "NSL SDIO transactor",
      serial_c => "sd",
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

      out_o => usb_cmd_s,
      out_i => usb_cmd_ack_s,

      in_i => usb_rsp_s,
      in_o => usb_rsp_ack_s
      );

  -- Frames crossing into the domain the card side runs in, and back.
  -- A whole batch never has to fit: what these hold is what keeps
  -- both sides moving while the other is busy.
  cmd_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 2048,
      clk_count => 2,
      -- What comes out of a fifo of this size comes out of a memory
      -- read from an address, and the address is worked out from the
      -- handshake.  A slice on either side keeps that off the path
      -- between the two clocks this runs on.
      input_slice_c => true,
      output_slice_c => true
      )
    port map(
      p_resetn => app_reset_n_s,
      p_clk(0) => clock_usb_s,
      p_clk(1) => clock_app_s,

      p_in_val => usb_cmd_s,
      p_in_ack => usb_cmd_ack_s,

      p_out_val => cmd_framed_s,
      p_out_ack => cmd_framed_ack_s
      );

  rsp_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 2048,
      clk_count => 2,
      input_slice_c => true,
      output_slice_c => true
      )
    port map(
      p_resetn => app_reset_n_app_s,
      p_clk(0) => clock_app_s,
      p_clk(1) => clock_usb_s,

      p_in_val => rsp_framed_s,
      p_in_ack => rsp_framed_ack_s,

      p_out_val => usb_rsp_s,
      p_out_ack => usb_rsp_ack_s
      );

  cmd_adapter: nsl_bnoc.axi_adapter.framed_to_axi4_stream
    port map(
      clock_i => clock_app_s,
      reset_n_i => app_reset_n_app_s,

      framed_i => cmd_framed_s,
      framed_o => cmd_framed_ack_s,

      axi_o => cmd_s,
      axi_i => cmd_ack_s
      );

  transactor: nsl_sdio.cbor_transactor.axi4stream_cbor_sdio_transactor
    generic map(
      clock_i_hz_c => clock_app_hz_c,
      stream_config_c => stream_config_c
      )
    port map(
      clock_i => clock_app_s,
      reset_n_i => app_reset_n_app_s,

      sdio_o => bus_o_s,
      sdio_i => bus_i_s,

      card_present_i => card_present_s,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,

      rsp_o => rsp_s,
      rsp_i => rsp_ack_s
      );

  rsp_adapter: nsl_bnoc.axi_adapter.axi4_stream_to_framed
    port map(
      clock_i => clock_app_s,
      reset_n_i => app_reset_n_app_s,

      axi_i => rsp_s,
      axi_o => rsp_ack_s,

      framed_o => rsp_framed_s,
      framed_i => rsp_framed_ack_s
      );

  -- Socket of the board, wired straight to the fabric.  What comes
  -- back off the bus is taken from the pins rather than from the
  -- drivers, so that the pins stay ones the fabric can let go of.
  tf_clk_o <= bus_o_s.clk;

  cmd_pad: nsl_io.io.tristated_io_driver
    port map(
      v_i => bus_o_s.cmd,
      v_o => open,
      io_io => tf_cmd_io
      );

  bus_i_s.cmd <= to_x01(tf_cmd_io);

  dat_pad: for i in 0 to 3
  generate
    pad: nsl_io.io.tristated_io_driver
      port map(
        v_i => bus_o_s.d(i),
        v_o => open,
        io_io => tf_dat_io(i)
        );

    bus_i_s.d(i) <= to_x01(tf_dat_io(i));
  end generate;

  -- A socket has four data lines, and what a host drives above them
  -- goes nowhere.
  bus_i_s.d(bus_i_s.d'left downto 4) <= (others => '1');

  -- The contact grounds its pin while a card is in.  Nothing waits on
  -- it: a card answers or it does not.
  card_present_s <= not to_x01(tf_det_i);

  ready_led_o <= online_s;

  monitor: nsl_indication.activity.activity_blinker
    generic map(
      clock_hz_c => real(clock_ext_hz_c)
      )
    port map(
      reset_n_i => board_reset_n_s,
      clock_i => clock_ext_s,
      activity_i => cmd_framed_s.valid,
      led_o => done_led_o
      );

  mspi_sck_o <= '0';
  mspi_cs_n_o <= 'Z';
  mspi_mosi_io <= 'Z';

end arch;
