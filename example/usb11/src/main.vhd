library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_hwdep, nsl_bnoc, nsl_spi;

entity main is
  port (
    usb_dp_io, usb_dm_io, usb_dp_pu_io : inout std_logic;
    external_io: out std_ulogic_vector(0 to 7);
    led_r_o, led_g_o, led_b_o: inout std_logic;
    button_i: in std_ulogic;
    clk16_i: in std_ulogic;

    spi_cs_n_o, spi_mosi_o, spi_sck_o : out std_ulogic;
    spi_miso_i : in std_ulogic
  );
end main;

architecture arch of main is

  constant external_clock_freq : integer := 16000000;
  constant internal_clock_freq : integer := 48000000;

  signal usb_o : nsl_usb.io.usb_io_c;
  signal usb_i : nsl_usb.io.usb_io_s;
  signal tx_valid, tx_ready, rx_valid, rx_ready : std_ulogic;
  signal tx_data, rx_data : std_ulogic_vector(7 downto 0);

  signal utmi_data_to_phy : nsl_usb.utmi.utmi_data8_sie2phy;
  signal utmi_data_from_phy : nsl_usb.utmi.utmi_data8_phy2sie;
  signal utmi_system_to_phy : nsl_usb.utmi.utmi_system_sie2phy;
  signal utmi_system_from_phy : nsl_usb.utmi.utmi_system_phy2sie;

  signal app_reset_n, reset_merged_n, reset_n : std_ulogic;

  signal online, online_n : std_ulogic;

  signal internal_clock, external_clock : std_ulogic;
  signal blinker_r : std_ulogic;
  signal blinker_r_ctr : natural range 0 to internal_clock_freq / 2 - 1;
  signal blinker_b : std_ulogic;
  signal blinker_b_ctr : natural range 0 to external_clock_freq / 2 - 1;

  function nibble_to_char(nibble : unsigned(3 downto 0))
    return character
  is
  begin
    if nibble < 10 then
      return character'val(character'pos('0') + to_integer(nibble));
    else
      return character'val(character'pos('a') + to_integer(nibble) - 10);
    end if;
  end function;

  type framed_io is
  record
    cmd, rsp : nsl_bnoc.framed.framed_bus;
  end record;

  type comm_io is
  record
    pre_fifo, post_fifo : framed_io;
  end record;

  signal comm_spi: comm_io;

begin

  reset_merged_n <= not button_i;

  gb16: nsl_hwdep.clock.clock_buffer
    port map(
      clock_i => clk16_i,
      clock_o => external_clock
      );

  pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => external_clock_freq,
      output_hz_c => internal_clock_freq,
      hw_variant_c => "ice40(out=global,in=core)"
      )
    port map(
      clock_i => external_clock,
      reset_n_i => reset_merged_n,

      clock_o => internal_clock,
      locked_o => reset_n
      );

  io_driver: nsl_usb.io.io_fs_driver
    port map(
      bus_o => usb_i,
      bus_i => usb_o,
      bus_io.dp => usb_dp_io,
      bus_io.dm => usb_dm_io,
      dp_pullup_control_io => usb_dp_pu_io
      );

  external_io(0) <= usb_i.dp;
  external_io(1) <= usb_i.dm;
  
  fs_phy: nsl_usb.fs_phy.fs_utmi8_phy
    generic map(
      ref_clock_mhz_c => internal_clock_freq / 1000000
      )
    port map(
      ref_clock_i => internal_clock,
      reset_n_i => reset_n,

      bus_o => usb_o,
      bus_i => usb_i,

      utmi_data_i => utmi_data_to_phy,
      utmi_data_o => utmi_data_from_phy,
      utmi_system_i => utmi_system_to_phy,
      utmi_system_o => utmi_system_from_phy
      );

  func: nsl_usb.func.vendor_bulk_pair
    generic map(
      vendor_id_c => x"dead",
      product_id_c => x"beef",
      device_version_c => x"0100",
      manufacturer_c => "Nipo",
      product_c => "NSL Example SPI programmer",
      serial_c => "",
      hs_supported_c => false,
      bulk_mps_count_l2_c => 2,
      phy_clock_rate_c => internal_clock_freq,
      self_powered_c => false
      )
    port map(
      phy_system_o => utmi_system_to_phy,
      phy_system_i => utmi_system_from_phy,
      phy_data_o => utmi_data_to_phy,
      phy_data_i => utmi_data_from_phy,

      reset_n_i => reset_n,

      app_reset_n_o => app_reset_n,

      online_o => online,

      rx_valid_o => comm_spi.pre_fifo.cmd.req.valid,
      rx_data_o => comm_spi.pre_fifo.cmd.req.data,
      rx_ready_i => comm_spi.pre_fifo.cmd.ack.ready,

      tx_valid_i => comm_spi.pre_fifo.rsp.req.valid,
      tx_data_i => comm_spi.pre_fifo.rsp.req.data,
      tx_ready_o => comm_spi.pre_fifo.rsp.ack.ready
      );

  spi_cmd_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 256,
      clk_count => 1
      )
    port map(
      p_resetn => app_reset_n,
      p_clk(0) => internal_clock,

      p_in_val => comm_spi.pre_fifo.cmd.req,
      p_in_ack => comm_spi.pre_fifo.cmd.ack,

      p_out_val => comm_spi.post_fifo.cmd.req,
      p_out_ack => comm_spi.post_fifo.cmd.ack
      );

  spi_rsp_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 256,
      clk_count => 1
      )
    port map(
      p_resetn => app_reset_n,
      p_clk(0) => internal_clock,

      p_in_val => comm_spi.post_fifo.rsp.req,
      p_in_ack => comm_spi.post_fifo.rsp.ack,

      p_out_val => comm_spi.pre_fifo.rsp.req,
      p_out_ack => comm_spi.pre_fifo.rsp.ack
      );

  spi_inst: nsl_spi.transactor.spi_framed_transactor
    generic map(
      slave_count_c => 1
      )
    port map(
      clock_i  => internal_clock,
      reset_n_i => app_reset_n,

      sck_o => spi_sck_o,
      mosi_o => spi_mosi_o,
      cs_n_o(0).drain_n => spi_cs_n_o,
      miso_i => spi_miso_i,

      cmd_i => comm_spi.post_fifo.cmd.req,
      cmd_o => comm_spi.post_fifo.cmd.ack,
      rsp_o => comm_spi.post_fifo.rsp.req,
      rsp_i => comm_spi.post_fifo.rsp.ack
      );

  sb: if false
  generate
    g_driver: nsl_hwdep.ice40.ice40_opendrain_io_driver
      port map(
        v_i.drain_n => online_n,
        io_io => led_g_o
        );

    r_driver: nsl_hwdep.ice40.ice40_opendrain_io_driver
      port map(
        v_i.drain_n => blinker_r,
        io_io => led_r_o
        );

    b_driver: nsl_hwdep.ice40.ice40_opendrain_io_driver
      port map(
        v_i.drain_n => blinker_b,
        io_io => led_b_o
        );
  end generate;

  no_sb: if true
  generate
    led_r_o <= blinker_r;
    led_g_o <= online_n;
    led_b_o <= blinker_b;
  end generate;

  online_n <= not online;

  blinker_r_p : process(reset_n, internal_clock)
  begin
    if rising_edge(internal_clock) then
      if blinker_r_ctr /= 0 then
        blinker_r_ctr <= blinker_r_ctr - 1;
      else
        blinker_r_ctr <= internal_clock_freq / 2 - 1;
        blinker_r <= not blinker_r;
      end if;
    end if;

    if reset_n = '0' then
      blinker_r_ctr <= internal_clock_freq / 2 - 1;
      blinker_r <= '0';
    end if;
  end process;

  blinker_b_p : process(reset_merged_n, external_clock)
  begin
    if rising_edge(external_clock) then
      if blinker_b_ctr /= 0 then
        blinker_b_ctr <= blinker_b_ctr - 1;
        blinker_b <= blinker_b;
      else
        blinker_b_ctr <= external_clock_freq / 2 - 1;
        blinker_b <= not blinker_b;
      end if;
    end if;

    if reset_merged_n = '0' then
      blinker_b_ctr <= external_clock_freq / 2 - 1;
      blinker_b <= '0';
    end if;
  end process;

  
  
end arch;
