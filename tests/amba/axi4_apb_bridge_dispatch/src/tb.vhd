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
use nsl_amba.axi4_mm.all;
use nsl_amba.apb.all;
use nsl_amba.address.all;
use work.ctx.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal axi_s: nsl_amba.axi4_mm.bus_t;
  signal slave0_s, slave1_s: nsl_amba.apb.bus_t;

  constant axi_cfg_c : nsl_amba.axi4_mm.config_t := config(address_width => 32,
                                                          data_bus_width => 32);
  constant apb_cfg_c : nsl_amba.apb.config_t := config(address_width => 32,
                                                       data_bus_width => 32,
                                                       strb => true);

begin

  writer: process is
    variable rsp: resp_enum_t;
  begin
    done_s(0) <= '0';
    
    axi_s.m.aw <= address_defaults(axi_cfg_c);
    axi_s.m.w <= write_data_defaults(axi_cfg_c);
    axi_s.m.r <= handshake_defaults(axi_cfg_c);
    axi_s.m.b <= handshake_defaults(axi_cfg_c);
    axi_s.m.ar <= address_defaults(axi_cfg_c);

    wait for 30 ns;
    wait until falling_edge(clock_s);

    lite_write(axi_cfg_c, clock_s, axi_s.s, axi_s.m, addr => x"00000000", val => x"00000000", rsp => rsp);
    lite_write(axi_cfg_c, clock_s, axi_s.s, axi_s.m, addr => x"00001000", val => x"11111111", rsp => rsp);
    lite_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, addr => x"00000000", val => x"00000000", rsp => rsp);
    lite_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, addr => x"00001000", val => x"11111111", rsp => rsp);
    lite_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, addr => x"00000008", val => x"00000000", rsp => rsp);
    lite_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, addr => x"00001008", val => x"00000001", rsp => rsp);
    
    done_s(0) <= '1';
    wait;
  end process;

  dumper: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => axi_cfg_c,
      prefix_c => "Master"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => axi_s.m,
      slave_i => axi_s.s
      );

  router: nsl_amba.axi_apb.axi4_apb_bridge_dispatch
    generic map(
      axi_config_c => axi_cfg_c,
      apb_config_c => apb_cfg_c,
      routing_table_c => routing_table(apb_cfg_c.address_width, "x----0000/20", "x----1000/20")
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      apb_o(0) => slave0_s.m,
      apb_o(1) => slave1_s.m,
      apb_i(0) => slave0_s.s,
      apb_i(1) => slave1_s.s
      );

  s0_dumper: nsl_amba.apb.apb_dumper
    generic map(
      config_c => apb_cfg_c,
      prefix_c => "S0"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => slave0_s
      );

  s1_dumper: nsl_amba.apb.apb_dumper
    generic map(
      config_c => apb_cfg_c,
      prefix_c => "S1"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => slave1_s
      );

  slave0: work.ctx.mockup_slave
    generic map(
      config_c => apb_cfg_c,
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
      config_c => apb_cfg_c,
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
