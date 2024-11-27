library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_axi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_axi.axi4_mm.all;

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
    variable rsp: resp_enum_t;
  begin
    done_s(0) <= '0';
    
    bus_s.m.aw <= address_defaults(config_c);
    bus_s.m.w <= write_data_defaults(config_c);
    bus_s.m.r <= handshake_defaults(config_c);
    bus_s.m.b <= handshake_defaults(config_c);
    bus_s.m.ar <= address_defaults(config_c);
    wait for 30 ns;
    wait until falling_edge(clock_s);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000000", val => x"00010203", rsp => rsp);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000004", val => x"04050607", rsp => rsp);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000008", val => x"08090a0b", rsp => rsp);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000000c", val => x"0c0d0e0f", rsp => rsp);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000010", val => x"10111213", rsp => rsp);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000014", val => x"14151617", rsp => rsp);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000018", val => x"18191a1b", rsp => rsp);
    lite_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000001c", val => x"1c1d1e1f", rsp => rsp);

    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000001c", val => value, rsp => rsp);
    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000004", val => value, rsp => rsp);
    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000008", val => value, rsp => rsp);
    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"0000000c", val => value, rsp => rsp);
    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000010", val => value, rsp => rsp);
    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000018", val => value, rsp => rsp);
    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000014", val => value, rsp => rsp);
    lite_read(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000000", val => value, rsp => rsp);

    
    done_s(0) <= '1';
    wait;
  end process;

  dumper: nsl_axi.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "RAM"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => bus_s.m,
      slave_i => bus_s.s
      );
  
  dut: nsl_axi.axi4_mm.axi4_mm_lite_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => bus_s.m,
      axi_o => bus_s.s
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
