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
use nsl_amba.axi4_mm.all;
use nsl_amba.apb.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal axi_s: nsl_amba.axi4_mm.bus_t;
  signal apb_s: nsl_amba.apb.bus_t;

  constant axi_cfg_c : nsl_amba.axi4_mm.config_t := config(address_width => 32,
                                                          data_bus_width => 32,
                                                          max_length => 16,
                                                          burst => true);
  constant apb_cfg_c : nsl_amba.apb.config_t := config(address_width => 32,
                                                       data_bus_width => 32,
                                                       strb => true);

begin

  writer: process is
    constant init_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable state_v : prbs_state(30 downto 0) := init_v;
    variable i: integer;
    variable rsp: resp_enum_t;

    variable pushback_v : prbs_state(30 downto 0) := x"5555555"&"101";
    variable do_accept: boolean;
    variable rdata, expected: byte_string(0 to 2**axi_cfg_c.data_bus_width_l2-1);
  begin
    done_s(0) <= '0';
    
    axi_s.m.ar <= address_defaults(axi_cfg_c);
    axi_s.m.r <= handshake_defaults(axi_cfg_c);
    axi_s.m.aw <= address_defaults(axi_cfg_c);
    axi_s.m.w <= write_data_defaults(axi_cfg_c);
    axi_s.m.b <= accept(axi_cfg_c, true);
    wait for 30 ns;
    wait until falling_edge(clock_s);

    burst_write(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000000", prbs_byte_string(state_v, prbs31, 32),
                rsp => rsp);
    
    state_v := prbs_forward(state_v, prbs31, 32*8);

    burst_write(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 32),
                burst => BURST_WRAP, rsp => rsp);

    burst_write(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000040", from_hex("00"*32),
                rsp => rsp);
    burst_write(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000043", from_hex("ff"*4),
                rsp => rsp);
    burst_write(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000047", from_hex("ee"*7),
                rsp => rsp);

    
    state_v := init_v;

    burst_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000000", prbs_byte_string(state_v, prbs31, 32));

    state_v := prbs_forward(state_v, prbs31, 32*8);

    burst_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 32),
                burst => BURST_WRAP);

    -- Read again, linear
    
    state_v := prbs_forward(init_v, prbs31, 32*8);
    burst_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 24));
    state_v := prbs_forward(state_v, prbs31, 24*8);
    burst_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000020", prbs_byte_string(state_v, prbs31, 8));

    burst_check(axi_cfg_c, clock_s, axi_s.s, axi_s.m, x"00000041", from_hex("0000" & "ff"*4 & "ee"*7 & "00"));
    
    done_s(0) <= '1';
    wait;
  end process;

  bridge: nsl_amba.axi_apb.axi4_apb_bridge
    generic map(
      axi_config_c => axi_cfg_c,
      apb_config_c => apb_cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      apb_o => apb_s.m,
      apb_i => apb_s.s
      );
  
  axi_dumper: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => axi_cfg_c,
      prefix_c => "AXI"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => axi_s.m,
      slave_i => axi_s.s
      );
  
  apb_dumper: nsl_amba.apb.apb_dumper
    generic map(
      config_c => apb_cfg_c,
      prefix_c => "APB"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => apb_s
      );
  
  dut: nsl_amba.ram.apb_ram
    generic map(
      config_c => apb_cfg_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      apb_i => apb_s.m,
      apb_o => apb_s.s
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
