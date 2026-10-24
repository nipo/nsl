library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_pkg is

  -- Register address and expected value
  subtype reg_check_t is std_ulogic_vector(23 downto 0);
  type reg_check_vector is array(natural range <>) of reg_check_t;

end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_omnivision, nsl_i2c, nsl_bnoc, nsl_data, work;
use nsl_omnivision.ov5640.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use work.tb_pkg.all;

-- Drives the OV5640 driver through a real I2C transactor against a
-- model of the sensor register map.  The model only answers while
-- out of power down and reset, and holds the identification.
-- Registers in checks_c must hold their value once the driver says it
-- is ready, and the test pattern must follow its input afterwards.
entity harness is
  generic(
    mode_c : mode_t;
    width_c : positive;
    height_c : positive;
    checks_c : reg_check_vector
    );
  port(
    done_o : out boolean
    );
end entity;

architecture sim of harness is

  constant clock_hz_c : natural := 16_000_000;
  constant clock_period_c : time := 1 sec / clock_hz_c;
  constant i2c_divisor_c : unsigned(4 downto 0)
    := nsl_i2c.transactor.scl_divisor(clock_hz_c, 400_000);
  -- Shortens power-up delays to a few hundred cycles
  constant driver_clock_hz_c : natural := 40_000;

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;
  signal done_s : boolean := false;

  signal cmd_s, rsp_s : nsl_bnoc.framed.framed_bus;
  signal i2c_s : nsl_i2c.i2c.i2c_i;
  signal i2c_o_s : nsl_i2c.i2c.i2c_o_vector(0 to 1);

  signal mem_addr_s : unsigned(15 downto 0);
  signal mem_r_data_s, mem_w_data_s : std_ulogic_vector(7 downto 0);
  signal mem_w_valid_s : std_ulogic;

  type reg_file_t is array(0 to 65535) of byte;
  signal regs_s : reg_file_t := (others => x"00");

  signal test_pattern_s : std_ulogic := '0';
  signal sensor_reset_n_s, sensor_power_down_s, sensor_on_n_s : std_ulogic;
  signal ready_s : std_ulogic;

begin

  done_o <= done_s;

  clock_s <= not clock_s after clock_period_c / 2 when not done_s else '0';

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 10 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  dut: nsl_omnivision.ov5640.ov5640_driver
    generic map(
      clock_i_hz_c => driver_clock_hz_c,
      mode_c => mode_c,
      width_c => width_c,
      height_c => height_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      i2c_divisor_i => i2c_divisor_c,
      cmd_o => cmd_s.req,
      cmd_i => cmd_s.ack,
      rsp_i => rsp_s.req,
      rsp_o => rsp_s.ack,

      test_pattern_i => test_pattern_s,

      sensor_reset_n_o => sensor_reset_n_s,
      sensor_power_down_o => sensor_power_down_s,

      ready_o => ready_s
      );

  transactor: nsl_i2c.transactor.transactor_framed_controller
    generic map(
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      i2c_o => i2c_o_s(0),
      i2c_i => i2c_s,

      cmd_i => cmd_s.req,
      cmd_o => cmd_s.ack,
      rsp_o => rsp_s.req,
      rsp_i => rsp_s.ack
      );

  resolver: nsl_i2c.i2c.i2c_resolver
    generic map(
      port_count => 2
      )
    port map(
      bus_i => i2c_o_s,
      bus_o => i2c_s
      );

  sensor_on_n_s <= sensor_reset_n_s and not sensor_power_down_s;

  chip_i2c: nsl_i2c.clocked.clocked_memory_controller
    generic map(
      addr_bytes => 2,
      data_bytes => 1
      )
    port map(
      reset_n_i => sensor_on_n_s,
      clock_i => clock_s,
      slave_address_i => i2c_saddr_default_c,
      i2c_o => i2c_o_s(1),
      i2c_i => i2c_s,
      addr_o => mem_addr_s,
      r_data_i => mem_r_data_s,
      w_valid_o => mem_w_valid_s,
      w_data_o => mem_w_data_s
      );

  chip_read: process(mem_addr_s, regs_s) is
  begin
    case to_integer(mem_addr_s) is
      when 16#300a# => mem_r_data_s <= x"56";
      when 16#300b# => mem_r_data_s <= x"40";
      when others => mem_r_data_s <= regs_s(to_integer(mem_addr_s));
    end case;
  end process;

  chip_write: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if sensor_on_n_s = '0' then
        regs_s <= (others => x"00");
      elsif mem_w_valid_s = '1' then
        regs_s(to_integer(mem_addr_s)) <= mem_w_data_s;
      end if;
    end if;
  end process;

  check: process is
    procedure expect_reg(addr: natural; value: byte) is
    begin
      assert regs_s(addr) = value
        report "Register " & to_hex_string(std_ulogic_vector(to_unsigned(addr, 16)))
        & " is " & to_hex_string(regs_s(addr)) & ", expected " & to_hex_string(value)
        severity failure;
    end procedure;
  begin
    wait until reset_n_s = '1';

    wait until ready_s = '1' for 1 sec;
    assert ready_s = '1'
      report "Driver never ready" severity failure;

    for i in checks_c'range loop
      expect_reg(to_integer(unsigned(checks_c(i)(23 downto 8))),
                 checks_c(i)(7 downto 0));
    end loop;

    test_pattern_s <= '1';
    wait until ready_s = '0' for 1 ms;
    wait until ready_s = '1' for 10 ms;
    assert ready_s = '1'
      report "Driver not ready after test pattern change" severity failure;
    expect_reg(16#503d#, x"80");

    done_s <= true;
    wait;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_omnivision, nsl_simulation, work;
use nsl_omnivision.ov5640.all;
use work.tb_pkg.all;

-- Runs the driver in each of its modes.  Output format, size and
-- clock setup are checked.
entity tb is
end entity;

architecture sim of tb is

  signal vga_done_s, hd15_done_s, hd30_done_s : boolean;

begin

  vga: entity work.harness
    generic map(
      mode_c => MODE_VGA,
      width_c => 320,
      height_c => 240,
      checks_c => (
        x"300802", x"303521", x"30366a", x"303714", x"382402",
        x"380801", x"380940", x"380a00", x"380bf0", x"5001a3",
        x"430061", x"501f01", x"474020", x"503d00")
      )
    port map(
      done_o => vga_done_s
      );

  hd15: entity work.harness
    generic map(
      mode_c => MODE_720P15,
      width_c => 1280,
      height_c => 720,
      checks_c => (
        x"300802", x"303541", x"303669", x"303713", x"310801",
        x"460c22", x"382401", x"3803fa", x"3807a9", x"380d64",
        x"380e02", x"380fe4", x"381110", x"381304", x"380805",
        x"380900", x"380a02", x"380bd0", x"500183", x"430061",
        x"501f01", x"474020", x"503d00")
      )
    port map(
      done_o => hd15_done_s
      );

  hd30: entity work.harness
    generic map(
      mode_c => MODE_720P30,
      width_c => 640,
      height_c => 360,
      checks_c => (
        x"303521", x"303669", x"303713", x"382401", x"380802",
        x"380980", x"380a01", x"380b68", x"5001a3")
      )
    port map(
      done_o => hd30_done_s
      );

  terminator: process is
  begin
    wait until vga_done_s and hd15_done_s and hd30_done_s;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
