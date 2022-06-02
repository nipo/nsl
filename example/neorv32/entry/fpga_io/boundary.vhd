library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_clocking, nsl_hwdep, nsl_spi, nsl_ws,
  nsl_indication, nsl_color, nsl_bnoc,
  nsl_io, entry;
use nsl_color.rgb.all;

library unisim;

entity boundary is
  port (
      clock_60_i: in std_ulogic;

      phy_clk_o: out std_ulogic;
      phy_data_io: inout std_logic_vector(7 downto 0);
      phy_dir_i: in std_ulogic;
      phy_nxt_i: in std_ulogic;
      phy_stp_o: out std_ulogic;
      phy_reset_n_o: out std_ulogic;

      flash_d_io : inout std_ulogic_vector(0 to 1);
      flash_cs_n_o : out std_logic;

      flash_sel_d_o, flash_sel_c_o : out std_ulogic;
      flash_sel_o : out std_ulogic;
      i2c_sda_io, i2c_scl_io : inout std_logic;

      button_n_i: in std_ulogic_vector(1 to 4);
      led_ctrl_o: out std_logic
  );
end boundary;

architecture arch of boundary is

  signal button_down, button_pressed_n, button_pressed: std_ulogic_vector(1 to 4);

  signal reset_merged_n, reset_n : std_ulogic;
  signal clock_60 : std_ulogic;

  signal done_led, done_led_n: std_ulogic;

  signal s_device_uid : unsigned(31 downto 0);
  signal s_device_serial : string(1 to (s_device_uid'length + 3) / 4);

  signal s_ulpi: nsl_usb.ulpi.ulpi8;

  signal s_flash_cs_n : nsl_io.io.opendrain;
  signal s_flash_d_o : nsl_io.io.directed_vector(0 to 1);
  signal s_flash_d_i : std_ulogic_vector(0 to 1);
  signal s_flash_sel : std_ulogic;
  signal s_flash_sck : std_ulogic;

  function uid_to_serial(uid : unsigned) return string
  is
    variable ret : string(1 to (uid'length + 3) / 4);
    variable uid_a : unsigned(ret'length*4 - 1 downto 0);
    variable nibble : unsigned(3 downto 0);
    variable c : character;
  begin
    uid_a := (others => '0');
    uid_a(uid'length-1 downto 0) := uid;

    for i in ret'range
    loop
      nibble := uid_a(uid_a'left - 4 * (i-1) downto uid_a'left - 4 * (i - 1) - 3);
      if nibble < x"a" then
        c := character'val(character'pos('0') + to_integer(nibble));
      else
        c:= character'val(character'pos('a') + to_integer(nibble) - 10);
      end if;
      ret(i) := c;
    end loop;
    return ret;
  end function;

begin

  clock_buf: nsl_hwdep.clock.clock_buffer
    port map(
      clock_i => clock_60_i,
      clock_o => clock_60
      );

  startup: unisim.vcomponents.startupe2
    port map (
      cfgmclk => open,
      eos => open,
      clk => '0',
      gsr => '0',
      gts => '0',
      keyclearb => '1',
      pack => '0',
      usrcclko => s_flash_sck,
      usrcclkts => '0', -- oe_n
      usrdoneo => '0',
      usrdonets => done_led_n -- oe_n
      );

  reset_sync: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_60,
      reset_n_o => reset_n
      );

  done_led_n <= not done_led;

  main: entry.neorv32_tester.tester_root
    generic map(
      clock_i_hz_c => 60000000
      )
    port map(
      clock_i => clock_60,
      reset_n_i => reset_n,

      serial_i => s_device_serial,

      ulpi_o => s_ulpi.link2phy,
      ulpi_i => s_ulpi.phy2link,

      flash_sck_o => s_flash_sck,
      flash_cs_n_o => s_flash_cs_n,
      flash_d_o => s_flash_d_o,
      flash_d_i => s_flash_d_i,
      flash_sel_o => s_flash_sel,

      sda_io => i2c_sda_io,
      scl_io => i2c_scl_io,

      button_i => button_pressed,
      led_o => led_ctrl_o,
      done_led_o => done_led
      );
  
  ulpi_driver: nsl_usb.ulpi.ulpi8_line_driver_clock_master
    generic map(
      reset_active_c => '0'
      )
    port map(
      clock_i => clock_60,

      clock_o => phy_clk_o,
      reset_o => phy_reset_n_o,
      data_io => phy_data_io,
      dir_i => phy_dir_i,
      nxt_i => phy_nxt_i,
      stp_o => phy_stp_o,

      bus_o => s_ulpi.phy2link,
      bus_i => s_ulpi.link2phy
      );

  s_device_serial <= uid_to_serial(s_device_uid);

  cs_drain: process(clock_60)
  begin
    if rising_edge(clock_60) then
      flash_cs_n_o <= s_flash_cs_n.drain_n;
    end if;
  end process;
  flash_sel_o <= s_flash_sel;
  flash_d_io(0) <= s_flash_d_o(0).v;
  s_flash_d_i(0) <= '-';
  s_flash_d_i(1) <= flash_d_io(1);
  
  uid: nsl_hwdep.uid.uid32_reader
    port map(
      clock_i => clock_60,
      reset_n_i => reset_n,
      uid_o => s_device_uid
      );
  
  button_sampler: for i in button_n_i'range
  generate
    input_gate: nsl_clocking.async.async_input
      generic map(
        debounce_count_c => 100
        )
      port map(
        clock_i => clock_60,
        reset_n_i => reset_n,
        data_i => button_n_i(i),
        falling_o => open,
        data_o => button_pressed_n(i)
        );
  end generate;
  button_pressed <= not button_pressed_n;
  
end arch;
