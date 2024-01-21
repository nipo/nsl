library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_usb, nsl_io, nsl_hwdep,
  nsl_color, nsl_math, neorv32,
  nsl_bnoc, nsl_jtag, nsl_clocking,
  nsl_spi, nsl_data, work, nsl_uart,
  nsl_i2c;
use nsl_color.rgb.all;
use nsl_data.text.all;
use nsl_jtag.jtag.all;

entity tester_root is
  generic(
    clock_i_hz_c : integer
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    serial_i : in string(1 to 8);

    ulpi_o: out nsl_usb.ulpi.ulpi8_link2phy;
    ulpi_i: in nsl_usb.ulpi.ulpi8_phy2link;

    flash_cs_n_o : out nsl_io.io.opendrain;
    flash_d_o : out nsl_io.io.directed_vector(0 to 1);
    flash_d_i : in std_ulogic_vector(0 to 1);
    flash_sel_o : out std_ulogic;
    flash_sck_o : out std_ulogic;

    sda_io, scl_io : inout std_logic;

    button_i: in std_ulogic_vector(1 to 4);
    led_o: out std_ulogic;
    done_led_o: out std_ulogic
    );
end entity;

architecture beh of tester_root is

  constant app_clock_hz_c : integer := 100000000;
  signal s_app_clock, s_app_reset_n, s_online : std_ulogic;

  constant transactor_count_c: integer := 2;

  signal s_cs_config, s_cs_status: nsl_bnoc.control_status.control_status_reg_array(0 to 1);

  constant REG_UNUSED : integer := 0;

  signal s_jtag_ate_cmd: nsl_jtag.jtag.jtag_ate_o;
  signal s_jtag_ate_rsp: nsl_jtag.jtag.jtag_ate_i;
  signal s_jtag_tap_cmd: nsl_jtag.jtag.jtag_tap_i;
  signal s_jtag_tap_rsp: nsl_jtag.jtag.jtag_tap_o;
    
  signal s_cmd_req, s_rsp_req: nsl_bnoc.framed.framed_req_array(0 to transactor_count_c-1);
  signal s_cmd_ack, s_rsp_ack: nsl_bnoc.framed.framed_ack_array(0 to transactor_count_c-1);

  signal s_jtag_system_reset_n: nsl_io.io.opendrain;

  signal uart_from_usb_s, uart_to_usb_s: nsl_bnoc.pipe.pipe_bus_t;

  signal core_gpio_o_s, core_gpio_i_s: std_ulogic_vector(63 downto 0);
  signal core_txd_s, core_rxd_s, core_rts_s, core_cts_s: std_ulogic;
  signal core_spi_sck_s, core_spi_sdo_s, core_spi_sdi_s: std_ulogic;
  signal core_spi_csn_s: std_ulogic_vector(7 downto 0);

  signal core_i2c_s: nsl_i2c.i2c.i2c_io;
  
  constant uart_div_c: unsigned := nsl_math.arith.to_unsigned_auto(app_clock_hz_c / 19200);

begin

  usb: work.neorv32_tester.usb_function
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      transactor_count_c => transactor_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      app_clock_i => s_app_clock,
      app_reset_n_o => s_app_reset_n,

      serial_i => serial_i,
      
      ulpi_o => ulpi_o,
      ulpi_i => ulpi_i,

      cmd_o => s_cmd_req,
      cmd_i => s_cmd_ack,
      rsp_i => s_rsp_req,
      rsp_o => s_rsp_ack,

      rx_o => uart_from_usb_s.req,
      rx_i => uart_from_usb_s.ack,
      tx_i => uart_to_usb_s.req,
      tx_o => uart_to_usb_s.ack,
      
      online_o => s_online
      );

  done_led_o <= '1';

  cs: nsl_bnoc.control_status.framed_control_status
    generic map(
      config_count_c => s_cs_config'length,
      status_count_c => s_cs_status'length
      )
    port map(
      clock_i  => s_app_clock,
      reset_n_i => s_app_reset_n,

      cmd_i => s_cmd_req(0),
      cmd_o => s_cmd_ack(0),
      rsp_o => s_rsp_req(0),
      rsp_i => s_rsp_ack(0),

      config_o => s_cs_config,
      status_i => s_cs_status
      );

  jtag: nsl_jtag.transactor.framed_ate
    port map(
      clock_i  => s_app_clock,
      reset_n_i => s_app_reset_n,

      cmd_i => s_cmd_req(1),
      cmd_o => s_cmd_ack(1),
      rsp_o => s_rsp_req(1),
      rsp_i => s_rsp_ack(1),

      jtag_o => s_jtag_ate_cmd,
      jtag_i => s_jtag_ate_rsp,

      system_reset_n_o => s_jtag_system_reset_n
      );

  app_clock_gen: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => clock_i_hz_c,
      output_hz_c => app_clock_hz_c,
      hw_variant_c => "series67(type=pll)"
      )
    port map(
      clock_i => clock_i,
      clock_o => s_app_clock,

      reset_n_i => reset_n_i,
      locked_o => open
      );

  neorv32_inst: neorv32.neorv32_package.neorv32_top
    generic map (
      CLOCK_FREQUENCY              => app_clock_hz_c,
      INT_BOOTLOADER_EN            => true,
      MEM_INT_IMEM_EN              => true,
      MEM_INT_DMEM_EN              => true,

      ON_CHIP_DEBUGGER_EN          => true,

      IO_GPIO_NUM                  => core_gpio_o_s'length,
      IO_UART0_EN                  => true,
      IO_SPI_EN                    => true,
      IO_TWI_EN                    => true,
      IO_NEOLED_EN                 => true
      )
    port map (
      clk_i       => s_app_clock,
      rstn_i      => s_jtag_system_reset_n.drain_n,

      jtag_trst_i => '1',
      jtag_tck_i  => s_jtag_tap_cmd.tck,
      jtag_tdi_i  => s_jtag_tap_cmd.tdi,
      jtag_tdo_o  => s_jtag_tap_rsp.tdo.v,
      jtag_tms_i  => s_jtag_tap_cmd.tms,

      gpio_o      => core_gpio_o_s,
      gpio_i      => core_gpio_i_s,

      uart0_txd_o => core_txd_s,
      uart0_rxd_i => core_rxd_s,
      uart0_rts_o => core_rts_s,
      uart0_cts_i => core_cts_s,

      spi_clk_o   => core_spi_sck_s,
      spi_dat_o   => core_spi_sdo_s,
      spi_dat_i   => core_spi_sdi_s,
      spi_csn_o   => core_spi_csn_s,

      twi_sda_i   => core_i2c_s.i.sda,
      twi_sda_o   => core_i2c_s.o.sda.drain_n,
      twi_scl_i   => core_i2c_s.i.scl,
      twi_scl_o   => core_i2c_s.o.scl.drain_n,

      neoled_o    => led_o
      );

  s_jtag_tap_cmd <= to_tap(s_jtag_ate_cmd);
  s_jtag_ate_rsp <= to_ate(s_jtag_tap_rsp);
  s_jtag_tap_rsp.tdo.en <= '1';
  flash_cs_n_o.drain_n <= core_spi_csn_s(0) and core_spi_csn_s(1);
  flash_d_o(0).output <= '1';
  flash_d_o(0).v <= core_spi_sdo_s;
  flash_d_o(1).output <= '0';
  flash_d_o(1).v <= '-';
  core_spi_sdi_s <= flash_d_i(1);
  flash_sck_o <= core_spi_sck_s;
  flash_sel_o <= not core_spi_csn_s(1);

  core_gpio_i_s <= s_cs_config(1) & s_cs_config(0);
  s_cs_status(1) <= core_gpio_o_s(63 downto 32);
  s_cs_status(0) <= core_gpio_o_s(31 downto 0);

  i2c_driver: nsl_i2c.i2c.i2c_line_driver
    port map(
      bus_io.scl => scl_io,
      bus_io.sda => sda_io,
      bus_o => core_i2c_s.i,
      bus_i => core_i2c_s.o
      );
  
  uart: nsl_uart.transactor.uart8
    port map(
      reset_n_i => s_app_reset_n,
      clock_i => s_app_clock,

      divisor_i => uart_div_c,

      tx_o => core_rxd_s,
      cts_i => core_rts_s,
      rx_i => core_txd_s,
      rts_o => core_cts_s,

      tx_data_i => uart_from_usb_s.req,
      tx_data_o => uart_from_usb_s.ack,
      rx_data_i => uart_to_usb_s.ack,
      rx_data_o => uart_to_usb_s.req
      );

end architecture;
