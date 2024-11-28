library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_axi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_axi.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal input_s, output_s: bus_t;

  constant in_cfg_c: config_t := config(4, last => false);
  constant out_cfg_c: config_t := config(4, last => true);
begin

  b: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable i : integer;
  begin
    done_s(0) <= '0';

    input_s.m <= transfer_defaults(in_cfg_c);

    wait for 50 ns;

    i := 0;
    while true
    loop
      wait until falling_edge(clock_s);
      input_s.m <= transfer(in_cfg_c, bytes => prbs_byte_string(state_v, prbs31, 4), valid => true);

      wait until rising_edge(clock_s);
      if is_ready(in_cfg_c, input_s.s) then
        state_v := prbs_forward(state_v, prbs31, 32);
        if i /= 42 then
          i := i + 1;
        else
          wait until falling_edge(clock_s);
          input_s.m <= transfer_defaults(in_cfg_c);
          exit;
        end if;
      end if;
    end loop;

    wait for 500 ns;

    i := 0;
    while true
    loop
      wait until falling_edge(clock_s);
      input_s.m <= transfer(in_cfg_c, bytes => prbs_byte_string(state_v, prbs31, 4), valid => true);

      wait until rising_edge(clock_s);
      if is_ready(in_cfg_c, input_s.s) then
        state_v := prbs_forward(state_v, prbs31, 32);
        if i /= 42 then
          i := i + 1;
        else
          wait until falling_edge(clock_s);
          input_s.m <= transfer_defaults(in_cfg_c);
          exit;
        end if;
      end if;
    end loop;

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  dumper: nsl_axi.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => out_cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => output_s
      );
  
  dut: nsl_axi.axi4_stream.axi4_stream_flusher
    generic map(
      max_packet_length_c => 10,
      max_idle_c => 8,
      in_config_c => in_cfg_c,
      out_config_c => out_cfg_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => input_s.m,
      in_o => input_s.s,

      out_o => output_s.m,
      out_i => output_s.s
      );

  output_s.s <= accept(out_cfg_c, true);
  
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
