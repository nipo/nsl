library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_altera;
use nsl_altera.hps.all;

entity top is
  port(
    clock_50_i : in std_ulogic;
    led_o : out std_ulogic_vector(0 to 1);

    hps_usb_clk_i : in std_ulogic;
    hps_usb_stp_o : out std_ulogic;
    hps_usb_dir_i : in std_ulogic;
    hps_usb_data_io : inout std_logic_vector(0 to 7);
    hps_usb_nxt_i : in std_ulogic;
    hps_enet_tx_clk_o : out std_ulogic;
    hps_enet_tx_ctl_o : out std_ulogic;
    hps_enet_rx_clk_i : in std_ulogic;
    hps_enet_rx_ctl_i : in std_ulogic;
    hps_enet_tx_data_o : out std_ulogic_vector(0 to 3);
    hps_enet_rx_data_i : in std_ulogic_vector(0 to 3);
    hps_sd_data_io : inout std_logic_vector(0 to 3);
    hps_sd_clk_o : out std_ulogic;
    hps_clk_25_i : in std_ulogic;
    hps_gsensor_int_io : inout std_logic;
    hps_sd_cmd_io : inout std_logic;
    hps_gsensor_i2c_en_io : inout std_logic;
    hps_i2c_sda_io : inout std_logic;
    hps_i2c_scl_io : inout std_logic;
    hps_uart_tx_o : out std_ulogic;
    hps_uart_rx_i : in std_ulogic;
    hps_key_io : inout std_logic;
    hps_led_io : inout std_logic;
    hps_enet_mdio_io : inout std_logic;
    hps_enet_mdc_o : out std_ulogic
    );
end entity;

architecture beh of top is

  constant lwh2f_config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 12, data_bus_width => 32,
                               id_width => 4, max_length => 256,
                               size => true, burst => true);
  constant apb_config_c : nsl_amba.apb.config_t
    := nsl_amba.apb.config(address_width => 12, data_bus_width => 32,
                           strb => true);

  signal hps_io_unused_s : std_logic_vector(0 to 47);
  signal hps_io_i_s, hps_io_o_s : std_ulogic_vector(0 to 47);
  signal reset_n_s : std_ulogic;
  signal gp_s : std_ulogic_vector(31 downto 0);
  signal lwh2f_s : nsl_amba.axi4_mm.bus_t;
  signal apb_s : nsl_amba.apb.bus_t;
  signal reg_no_s : integer range 0 to 15;
  signal w_value_s, r_value_s : unsigned(31 downto 0);
  signal w_strobe_s : std_ulogic;
  signal scratch_s : unsigned(31 downto 0);

begin

  hps: nsl_altera.hps.hps_wrapper
    generic map(
      lwh2f_used_c => true,
      lwh2f_config_c => lwh2f_config_c
      )
    port map(
      hps_io_io(0) => hps_io_unused_s(0),
      hps_io_io(1) => hps_io_unused_s(1),
      hps_io_io(2) => hps_io_unused_s(2),
      hps_io_io(3) => hps_usb_data_io(0),
      hps_io_io(4) => hps_usb_data_io(1),
      hps_io_io(5) => hps_io_unused_s(5),
      hps_io_io(6) => hps_usb_data_io(2),
      hps_io_io(7) => hps_usb_data_io(3),
      hps_io_io(8) => hps_usb_data_io(4),
      hps_io_io(9) => hps_usb_data_io(5),
      hps_io_io(10) => hps_usb_data_io(6),
      hps_io_io(11) => hps_usb_data_io(7),
      hps_io_io(12) => hps_io_unused_s(12),
      hps_io_io(13) => hps_io_unused_s(13),
      hps_io_io(14) => hps_io_unused_s(14),
      hps_io_io(15) => hps_io_unused_s(15),
      hps_io_io(16) => hps_io_unused_s(16),
      hps_io_io(17) => hps_io_unused_s(17),
      hps_io_io(18) => hps_io_unused_s(18),
      hps_io_io(19) => hps_io_unused_s(19),
      hps_io_io(20) => hps_io_unused_s(20),
      hps_io_io(21) => hps_io_unused_s(21),
      hps_io_io(22) => hps_io_unused_s(22),
      hps_io_io(23) => hps_io_unused_s(23),
      hps_io_io(24) => hps_sd_data_io(0),
      hps_io_io(25) => hps_sd_data_io(1),
      hps_io_io(26) => hps_io_unused_s(26),
      hps_io_io(27) => hps_io_unused_s(27),
      hps_io_io(28) => hps_gsensor_int_io,
      hps_io_io(29) => hps_sd_data_io(2),
      hps_io_io(30) => hps_sd_data_io(3),
      hps_io_io(31) => hps_sd_cmd_io,
      hps_io_io(32) => hps_io_unused_s(32),
      hps_io_io(33) => hps_io_unused_s(33),
      hps_io_io(34) => hps_gsensor_i2c_en_io,
      hps_io_io(35) => hps_io_unused_s(35),
      hps_io_io(36) => hps_i2c_sda_io,
      hps_io_io(37) => hps_i2c_scl_io,
      hps_io_io(38) => hps_io_unused_s(38),
      hps_io_io(39) => hps_io_unused_s(39),
      hps_io_io(40) => hps_key_io,
      hps_io_io(41) => hps_led_io,
      hps_io_io(42) => hps_io_unused_s(42),
      hps_io_io(43) => hps_io_unused_s(43),
      hps_io_io(44) => hps_io_unused_s(44),
      hps_io_io(45) => hps_io_unused_s(45),
      hps_io_io(46) => hps_enet_mdio_io,
      hps_io_io(47) => hps_io_unused_s(47),
      hps_io_i => hps_io_i_s,
      hps_io_o => hps_io_o_s,
      lwh2f_clock_i => clock_50_i,
      lwh2f_reset_n_o => reset_n_s,
      lwh2f_o => lwh2f_s.m,
      lwh2f_i => lwh2f_s.s,
      gp_o => gp_s
      );

  bridge: nsl_amba.axi_apb.axi4_apb_bridge
    generic map(
      axi_config_c => lwh2f_config_c,
      apb_config_c => apb_config_c
      )
    port map(
      clock_i => clock_50_i,
      reset_n_i => reset_n_s,
      irq_n_o => open,
      axi_i => lwh2f_s.m,
      axi_o => lwh2f_s.s,
      apb_o => apb_s.m,
      apb_i => apb_s.s
      );

  regmap: nsl_amba.apb.apb_regmap
    generic map(
      config_c => apb_config_c,
      reg_count_l2_c => 4
      )
    port map(
      clock_i => clock_50_i,
      reset_n_i => reset_n_s,
      apb_i => apb_s.m,
      apb_o => apb_s.s,
      reg_no_o => reg_no_s,
      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,
      r_value_i => r_value_s,
      r_strobe_o => open
      );

  hps_io_i_s <= (
    0 => hps_usb_clk_i,
    2 => hps_usb_dir_i,
    5 => hps_usb_nxt_i,
    14 => hps_enet_rx_clk_i,
    15 => hps_enet_rx_ctl_i,
    18 => hps_enet_rx_data_i(0),
    19 => hps_enet_rx_data_i(1),
    22 => hps_enet_rx_data_i(2),
    23 => hps_enet_rx_data_i(3),
    27 => hps_clk_25_i,
    39 => hps_uart_rx_i,
    others => '0');

  hps_usb_stp_o <= hps_io_o_s(1);
  hps_enet_tx_clk_o <= hps_io_o_s(12);
  hps_enet_tx_ctl_o <= hps_io_o_s(13);
  hps_enet_tx_data_o(0) <= hps_io_o_s(16);
  hps_enet_tx_data_o(1) <= hps_io_o_s(17);
  hps_enet_tx_data_o(2) <= hps_io_o_s(20);
  hps_enet_tx_data_o(3) <= hps_io_o_s(21);
  hps_sd_clk_o <= hps_io_o_s(26);
  hps_uart_tx_o <= hps_io_o_s(38);
  hps_enet_mdc_o <= hps_io_o_s(47);

  regs: process(clock_50_i, reset_n_s)
  begin
    if reset_n_s = '0' then
      scratch_s <= (others => '0');
    elsif rising_edge(clock_50_i) then
      if w_strobe_s = '1' and reg_no_s = 1 then
        scratch_s <= w_value_s;
      end if;
    end if;
  end process;

  with reg_no_s select r_value_s <=
    x"4e534c48" when 0,
    scratch_s when 1,
    unsigned(gp_s) when 2,
    x"00000000" when others;

  led_o(0) <= not reset_n_s;
  led_o(1) <= scratch_s(0);

end architecture;
