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

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal bus_s, fifo_bus_s, ram_bus_s: nsl_amba.axi4_mm.bus_t;
  signal au_s, bu_s: nsl_amba.axi4_mm.bus_t;
  signal a2b_s, b2a_s: nsl_amba.axi4_stream.bus_t;

  constant config_c : nsl_amba.axi4_mm.config_t
    := nsl_amba.axi4_mm.config(address_width => 32,
                              data_bus_width => 32,
                              max_length => 16,
                              burst => true);
  constant stream_config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => 5,
                                  id => 3,
                                  last => true);

begin

  au_s.s.ar <= handshake_defaults(config_c);
  au_s.s.r <= read_data_defaults(config_c);
  au_s.s.aw <= handshake_defaults(config_c);
  au_s.s.w <= handshake_defaults(config_c);
  au_s.s.b <= write_response_defaults(config_c);

  bu_s.m.ar <= address_defaults(config_c);
  bu_s.m.r <= handshake_defaults(config_c);
  bu_s.m.aw <= address_defaults(config_c);
  bu_s.m.w <= write_data_defaults(config_c);
  bu_s.m.b <= accept(config_c, true);
  
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
    wait for 90 ns;
    wait until falling_edge(clock_s);

    burst_write(config_c, clock_s, bus_s.s, bus_s.m, x"00000000", prbs_byte_string(state_v, prbs31, 32),
                rsp => rsp);
    
    state_v := prbs_forward(state_v, prbs31, 32*8);

    burst_write(config_c, clock_s, bus_s.s, bus_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 32),
                burst => BURST_WRAP, rsp => rsp);

    burst_write(config_c, clock_s, bus_s.s, bus_s.m, x"00000040", from_hex("00"*32),
                rsp => rsp);
    burst_write(config_c, clock_s, bus_s.s, bus_s.m, x"00000043", from_hex("ff"*4),
                rsp => rsp);
    burst_write(config_c, clock_s, bus_s.s, bus_s.m, x"00000047", from_hex("ee"*7),
                rsp => rsp);

    
    state_v := init_v;

    burst_check(config_c, clock_s, bus_s.s, bus_s.m, x"00000000", prbs_byte_string(state_v, prbs31, 32));

    state_v := prbs_forward(state_v, prbs31, 32*8);

    burst_check(config_c, clock_s, bus_s.s, bus_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 32),
                burst => BURST_WRAP);

    -- Read again, linear
    
    state_v := prbs_forward(init_v, prbs31, 32*8);
    burst_check(config_c, clock_s, bus_s.s, bus_s.m, x"00000028", prbs_byte_string(state_v, prbs31, 24));
    state_v := prbs_forward(state_v, prbs31, 24*8);
    burst_check(config_c, clock_s, bus_s.s, bus_s.m, x"00000020", prbs_byte_string(state_v, prbs31, 8));

    burst_check(config_c, clock_s, bus_s.s, bus_s.m, x"00000041", from_hex("0000" & "ff"*4 & "ee"*7 & "00"));
    
    done_s(0) <= '1';
    wait;
  end process;

  pre_dumper: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "pre"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => bus_s.m,
      slave_i => bus_s.s
      );

  dut_enc: nsl_amba.mm_stream_adapter.axi4_mm_on_stream
    generic map(
      mm_config_c => config_c,
      stream_config_c => stream_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      
      slave_i => bus_s.m,
      slave_o => bus_s.s,

      master_o => au_s.m,
      master_i => au_s.s,

      tx_o => a2b_s.m,
      tx_i => a2b_s.s,

      rx_i => b2a_s.m,
      rx_o => b2a_s.s
      );

  a2b_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => stream_config_c,
      prefix_c => "a2b"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => a2b_s
      );

  b2a_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => stream_config_c,
      prefix_c => "b2a"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => b2a_s
      );

  dut_dec: nsl_amba.mm_stream_adapter.axi4_mm_on_stream
    generic map(
      mm_config_c => config_c,
      stream_config_c => stream_config_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      
      slave_i => bu_s.m,
      slave_o => bu_s.s,

      master_o => fifo_bus_s.m,
      master_i => fifo_bus_s.s,

      tx_o => b2a_s.m,
      tx_i => b2a_s.s,

      rx_i => a2b_s.m,
      rx_o => a2b_s.s
      );

  fifo: nsl_amba.mm_fifo.axi4_mm_fifo
    generic map(
      config_c => config_c,
      aw_depth_c => 4,
      w_depth_c => 2**config_c.len_width,
      b_depth_c => 4,
      ar_depth_c => 4,
      r_depth_c => 2**config_c.len_width,
      clock_count_c => 1
      )
    port map(
      clock_i(0) => clock_s,
      reset_n_i => reset_n_s,
      
      slave_i => fifo_bus_s.m,
      slave_o => fifo_bus_s.s,

      master_o => ram_bus_s.m,
      master_i => ram_bus_s.s
      );
  
  post_dumper: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "post"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => ram_bus_s.m,
      slave_i => ram_bus_s.s
      );
  
  ram: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => ram_bus_s.m,
      axi_o => ram_bus_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 25 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
