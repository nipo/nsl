library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

  signal in_s, with_header_s, out_s: bus_t;
  signal in_header_s, out_header_s : byte_string(0 to 10);
  signal in_header_strobe_s, out_header_strobe_s : std_ulogic;

  constant cfg_c: config_t := config(4, last => true, strobe => true);
  
begin

  tx: process
    variable header_state_v : prbs_state(30 downto 0) := x"decafba"&"111";
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable done: boolean := false;
    variable data_length: natural;
  begin
    done_s(0) <= '0';

    in_s.m <= transfer_defaults(cfg_c);
    in_header_s <= (others => dontcare_byte_c);

    wait for 50 ns;

    for i in 1 to 6
    loop
      data_length := i * cfg_c.data_width;

      in_header_s <= prbs_byte_string(header_state_v, prbs31, in_header_s'length);
      header_state_v := prbs_forward(header_state_v, prbs31, in_header_s'length * 8);
      
      packet_send(cfg_c, clock_s, in_s.s, in_s.m, prbs_byte_string(state_v, prbs31, data_length));
      state_v := prbs_forward(state_v, prbs31, data_length * 8);
    end loop;

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  rx_header: process
    variable header_state_v : prbs_state(30 downto 0) := x"decafba"&"111";
    variable header_v : byte_string(in_header_s'range);
  begin
    done_s(1) <= '0';

    wait for 50 ns;

    for i in 1 to 6
    loop
      header_v := prbs_byte_string(header_state_v, prbs31, header_v'length);
      header_state_v := prbs_forward(header_state_v, prbs31, header_v'length * 8);

      one: while true
      loop
        wait until rising_edge(clock_s);
        if out_header_strobe_s = '1' then
          assert_equal("out header", out_header_s, header_v, failure);
          exit one;
        end if;
      end loop;
    end loop;

    wait for 50 ns;

    done_s(1) <= '1';
    wait;
  end process;

  rx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable rx_data : byte_stream;
    variable id, user, dest : std_ulogic_vector(1 to 0);
    variable data_length: natural;
  begin
    done_s(2) <= '0';

    out_s.s <= accept(cfg_c, false);

    wait for 50 ns;

    for i in 1 to 6
    loop
      data_length := i * cfg_c.data_width;

      packet_receive(cfg_c, clock_s, out_s.m, out_s.s,
                     packet => rx_data,
                     id => id,
                     user => user,
                     dest => dest);

      assert_equal("data", rx_data.all, prbs_byte_string(state_v, prbs31, data_length), failure);
      state_v := prbs_forward(state_v, prbs31, data_length * 8);
    end loop;

    wait for 500 ns;

    done_s(2) <= '1';
    wait;
  end process;

  inserter: nsl_amba.axi4_stream.axi4_stream_header_inserter
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => in_s.m,
      in_o => in_s.s,
      header_i => in_header_s,
      header_strobe_o => in_header_strobe_s,
      
      out_o => with_header_s.m,
      out_i => with_header_s.s
      ); 

  extractor: nsl_amba.axi4_stream.axi4_stream_header_extractor
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => with_header_s.m,
      in_o => with_header_s.s,

      header_o => out_header_s,
      header_strobe_o => out_header_strobe_s,
      out_o => out_s.m,
      out_i => out_s.s
      );
  
  dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "IN "
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => in_s
      );
  
  dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "HDR"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => with_header_s
      );
 
  dumper_hdr: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => out_s
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
