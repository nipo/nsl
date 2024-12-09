library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.apb.all;
use nsl_amba.address.all;
use work.ctx.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal bus_s, slave0_s, slave1_s: bus_t;

  constant config_c : config_t := config(address_width => 32,
                                         data_bus_width => 32);

begin

  writer: process is
    variable err : boolean;
  begin
    done_s(0) <= '0';
    
    bus_s.m <= transfer_idle(config_c);

    wait for 30 ns;
    wait until falling_edge(clock_s);

    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000000", val => x"00000000", err => err);
    apb_write(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00001000", val => x"11111111", err => err);
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000000", val => x"00000000", err => err);
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00001000", val => x"11111111", err => err);
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00000008", val => x"00000000", err => err);
    apb_check(config_c, clock_s, bus_s.s, bus_s.m, addr => x"00001008", val => x"00000001", err => err);
    
    done_s(0) <= '1';
    wait;
  end process;

  dumper: nsl_amba.apb.apb_dumper
    generic map(
      config_c => config_c,
      prefix_c => "Master"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => bus_s
      );

  router: nsl_amba.apb_routing.apb_dispatch
    generic map(
      config_c => config_c,
      routing_table_c => routing_table(config_c.address_width, "x----0000/20", "x----1000/20")
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => bus_s.m,
      in_o => bus_s.s,

      out_o(0) => slave0_s.m,
      out_o(1) => slave1_s.m,
      out_i(0) => slave0_s.s,
      out_i(1) => slave1_s.s
      );

  slave0: work.ctx.mockup_slave
    generic map(
      config_c => config_c,
      index_c => 0
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      apb_i => slave0_s.m,
      apb_o => slave0_s.s
      );

  slave1: work.ctx.mockup_slave
    generic map(
      config_c => config_c,
      index_c => 1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      apb_i => slave1_s.m,
      apb_o => slave1_s.s
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
