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
use nsl_axi.mm_fifo.all;

entity tb is
end tb;

architecture arch of tb is

  signal stim_clock_s, ram_clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal ram_bus_s, bus_s: bus_t;

  constant config_c : config_t := config(address_width => 32,
                                         data_bus_width => 32,
                                         max_length => 16,
                                         burst => true);

begin

  writer: process is
    constant init_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable state_v : prbs_state(30 downto 0) := init_v;
    variable i: integer;
    variable rsp: resp_enum_t;

    variable pushback_v : prbs_state(30 downto 0) := x"5555555"&"101";
    variable do_accept: boolean;
    variable rdata, expected: byte_string(0 to 2**config_c.data_bus_width_l2-1);
  begin
    done_s(0) <= '0';
    
    bus_s.m.ar <= address_defaults(config_c);
    bus_s.m.r <= handshake_defaults(config_c);
    bus_s.m.aw <= address_defaults(config_c);
    bus_s.m.w <= write_data_defaults(config_c);
    bus_s.m.b <= accept(config_c, true);
    wait for 30 ns;
    wait until falling_edge(stim_clock_s);

    burst_write(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000000", prbs_byte_string(state_v, prbs31, 32),
                rsp => rsp);
    
    state_v := prbs_forward(state_v, prbs31, 32*8);

    burst_write(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 32),
                burst => BURST_WRAP, rsp => rsp);

    burst_write(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000040", from_hex("00"*32),
                rsp => rsp);
    burst_write(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000043", from_hex("ff"*4),
                rsp => rsp);
    burst_write(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000047", from_hex("ee"*7),
                rsp => rsp);

    
    state_v := init_v;

    burst_check(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000000", prbs_byte_string(state_v, prbs31, 32));

    state_v := prbs_forward(state_v, prbs31, 32*8);

    burst_check(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 32),
                burst => BURST_WRAP);

    -- Read again, linear
    
    state_v := prbs_forward(init_v, prbs31, 32*8);
    burst_check(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 24));
    state_v := prbs_forward(state_v, prbs31, 24*8);
    burst_check(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000020", prbs_byte_string(state_v, prbs31, 8));

    burst_check(config_c, stim_clock_s, bus_s.s, bus_s.m, x"00000041", from_hex("0000" & "ff"*4 & "ee"*7 & "00"));
    
    done_s(0) <= '1';
    wait;
  end process;

  cdc: nsl_axi.mm_fifo.axi4_mm_cdc
    generic map(
      config_c => config_c
      )
    port map(
      clock_i(0) => stim_clock_s,
      clock_i(1) => ram_clock_s,
      reset_n_i => reset_n_s,

      slave_i => bus_s.m,
      slave_o => bus_s.s,

      master_o => ram_bus_s.m,
      master_i => ram_bus_s.s
      );
      
  
  dut: nsl_axi.ram.axi4_mm_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => ram_clock_s,
      reset_n_i => reset_n_s,

      axi_i => ram_bus_s.m,
      axi_o => ram_bus_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 7 ns,
      reset_duration => (others => 28 ns),
      clock_o(0) => stim_clock_s,
      clock_o(1) => ram_clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
