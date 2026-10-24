library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_omnivision, nsl_i2c, nsl_bnoc, nsl_data, nsl_simulation;
use nsl_omnivision.ov5640.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- Drives the OV5640 driver through a real I2C transactor against a
-- model of the sensor register map.  The model only answers while
-- out of power down and reset, and holds the identification.  Output
-- format and size must be set once the driver says it is ready, and
-- the test pattern must follow its input afterwards.
entity tb is
end entity;

architecture sim of tb is

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
      width_c => 320,
      height_c => 240
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

    expect_reg(16#3008#, x"02");
    expect_reg(16#3808#, x"01");
    expect_reg(16#3809#, x"40");
    expect_reg(16#380a#, x"00");
    expect_reg(16#380b#, x"f0");
    expect_reg(16#4300#, x"61");
    expect_reg(16#501f#, x"01");
    expect_reg(16#4740#, x"20");
    expect_reg(16#503d#, x"00");

    test_pattern_s <= '1';
    wait until ready_s = '0' for 1 ms;
    wait until ready_s = '1' for 10 ms;
    assert ready_s = '1'
      report "Driver not ready after test pattern change" severity failure;
    expect_reg(16#503d#, x"80");

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
