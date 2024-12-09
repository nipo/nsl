library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.apb.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal bus_s: bus_t;

  constant config_c : config_t := config(address_width => 32,
                                         data_bus_width => 32);

begin

  writer: process is
    variable value: unsigned(31 downto 0);
    variable err: boolean;
  begin
    done_s(0) <= '0';
    
    bus_s.m <= transfer_idle(config_c);

    wait for 30 ns;
    wait until falling_edge(clock_s);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000000", val => x"00010203", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000004", val => x"04050607", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000008", val => x"08090a0b", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000000c", val => x"0c0d0e0f", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000010", val => x"10111213", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000014", val => x"14151617", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000018", val => x"18191a1b", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000001c", val => x"1c1d1e1f", err => err);

    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000014", val => x"14151617");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000000c", val => x"0c0d0e0f");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000001c", val => x"1c1d1e1f");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000004", val => x"04050607");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000008", val => x"08090a0b");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000010", val => x"10111213");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000000", val => x"00010203");
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000018", val => x"18191a1b");
    
    done_s(0) <= '1';
    wait;
  end process;

  dumper: nsl_amba.apb.apb_dumper
    generic map(
      config_c => config_c,
      prefix_c => "RAM"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => bus_s
      );
  
  dut: nsl_amba.ram.apb_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      apb_i => bus_s.m,
      apb_o => bus_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
