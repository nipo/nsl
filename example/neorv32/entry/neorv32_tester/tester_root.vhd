library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_usb, nsl_io, nsl_hwdep,
  nsl_color, nsl_math, neorv32,
  nsl_bnoc, nsl_jtag, nsl_clocking,
  nsl_spi, nsl_data, work, nsl_uart;
use nsl_color.rgb.all;
use nsl_data.text.all;

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

  signal s_jtag_cmd: nsl_jtag.jtag.jtag_ate_o;
  signal s_jtag_rsp: nsl_jtag.jtag.jtag_ate_i;
    
  signal s_cmd_req, s_rsp_req: nsl_bnoc.framed.framed_req_array(0 to transactor_count_c-1);
  signal s_cmd_ack, s_rsp_ack: nsl_bnoc.framed.framed_ack_array(0 to transactor_count_c-1);

  signal s_jtag_system_reset_n: nsl_io.io.opendrain;

  signal uart_from_usb_s, uart_to_usb_s: nsl_bnoc.pipe.pipe_bus_t;

  signal core_gpio_o_s, core_gpio_i_s: std_ulogic_vector(63 downto 0);
  signal core_txd_s, core_rxd_s, core_rts_s, core_cts_s: std_ulogic;
  signal core_spi_sck_s, core_spi_sdo_s, core_spi_sdi_s: std_ulogic;
  signal core_spi_csn_s: std_ulogic_vector(7 downto 0);

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

      jtag_o => s_jtag_cmd,
      jtag_i => s_jtag_rsp,

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
      -- General --
      CLOCK_FREQUENCY              => app_clock_hz_c,   -- clock frequency of clk_i in Hz
      INT_BOOTLOADER_EN            => true,             -- boot configuration: true = boot explicit bootloader; false = boot from int/ext (I)MEM
      MEM_INT_IMEM_EN              => true,             -- implement processor-internal instruction memory
      MEM_INT_DMEM_EN              => true,             -- implement processor-internal data memory
      HW_THREAD_ID                 => 0,                -- hardware thread id (32-bit)

      -- On-Chip Debugger (OCD) --
      ON_CHIP_DEBUGGER_EN          => true,             -- implement on-chip debugger?
      CPU_EXTENSION_RISCV_Zifencei => true,             -- implement instruction stream sync.?

      -- Processor peripherals --
      IO_GPIO_EN                   => true,     -- implement general purpose input/output port unit (GPIO)?
      IO_MTIME_EN                  => false,    -- implement machine system timer (MTIME)?
      IO_UART0_EN                  => true,     -- implement primary universal asynchronous receiver/transmitter (UART0)?
      IO_UART1_EN                  => false,    -- implement secondary universal asynchronous receiver/transmitter (UART1)?
      IO_SPI_EN                    => true,     -- implement serial peripheral interface (SPI)?
      IO_TWI_EN                    => true,     -- implement two-wire interface (TWI)?
      IO_PWM_NUM_CH                => 0,        -- number of PWM channels to implement (0..60); 0 = disabled
      IO_WDT_EN                    => false,    -- implement watch dog timer (WDT)?
      IO_TRNG_EN                   => false,    -- implement true random number generator (TRNG)?
      IO_NEOLED_EN                 => true      -- implement NeoPixel-compatible smart LED interface (NEOLED)?
      )
    port map (
      -- Global control --
      clk_i       => s_app_clock,                -- global clock, rising edge
      rstn_i      => s_jtag_system_reset_n.drain_n, -- global reset, low-active, async

      -- JTAG on-chip debugger interface (available if ON_CHIP_DEBUGGER_EN = true) --
      jtag_trst_i => '1',                        -- low-active TAP reset (optional)
      jtag_tck_i  => s_jtag_cmd.tck,             -- serial clock
      jtag_tdi_i  => s_jtag_cmd.tdi,             -- serial data input
      jtag_tdo_o  => s_jtag_rsp.tdo,             -- serial data output
      jtag_tms_i  => s_jtag_cmd.tms,             -- mode select

      -- Wishbone bus interface (available if MEM_EXT_EN = true) --
      wb_dat_i    => (others => '0'),              -- read data
      wb_ack_i    => '0',                          -- transfer acknowledge
      wb_err_i    => '0',                          -- transfer error

      -- GPIO (available if IO_GPIO_EN = true) --
      gpio_o      => core_gpio_o_s,                   -- parallel output
      gpio_i      => core_gpio_i_s,                   -- parallel input

      -- primary UART0 (available if IO_UART0_EN = true) --
      uart0_txd_o => core_txd_s,                   -- UART0 send data
      uart0_rxd_i => core_rxd_s,                   -- UART0 receive data
      uart0_rts_o => core_rts_s,                   -- hw flow control: UART0.RX ready to receive ("RTR"), low-active, optional
      uart0_cts_i => core_cts_s,                   -- hw flow control: UART0.TX allowed to transmit, low-active, optional

      -- SPI (available if IO_SPI_EN = true) --
      spi_sck_o   => core_spi_sck_s,                  -- SPI serial clock
      spi_sdo_o   => core_spi_sdo_s,                  -- controller data out, peripheral data in
      spi_sdi_i   => core_spi_sdi_s,                  -- controller data in, peripheral data out
      spi_csn_o   => core_spi_csn_s,                  -- SPI CS

      -- TWI (available if IO_TWI_EN = true) --
      twi_sda_io  => sda_io,                   -- twi serial data line
      twi_scl_io  => scl_io,                   -- twi serial clock line

      -- NeoPixel-compatible smart LED interface (available if IO_NEOLED_EN = true) --
      neoled_o    => led_o                         -- async serial data line
      );

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
