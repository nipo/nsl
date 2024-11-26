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
  signal done_s : std_ulogic_vector(0 to 1);

  signal input_s, output_s: bus_t;

  constant in_cfg_c: config_t := config(12, last => true);
  constant out_cfg_c: config_t := config(4, last => true, keep => true);
begin

  tx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable d : byte_string(0 to in_cfg_c.data_width-1) := (others => dontcare_byte_c);
    variable k, s : std_ulogic_vector(0 to in_cfg_c.data_width-1) := (others => '0');
    variable frame_byte_count, output_beat_count, beat_byte_count: integer;
  begin
    done_s(0) <= '0';

    input_s.m <= transfer_defaults(in_cfg_c);

    wait for 50 ns;

    for stream_beat_count in 1 to 16
    loop
      frame_byte_count := stream_beat_count * out_cfg_c.data_width;
      output_beat_count := (frame_byte_count + in_cfg_c.data_width - 1) / in_cfg_c.data_width;
      for beat_index in 0 to output_beat_count-1
      loop
        beat_byte_count := frame_byte_count - beat_index * in_cfg_c.data_width;
        if beat_byte_count > in_cfg_c.data_width then
          beat_byte_count := in_cfg_c.data_width;
        end if;

        d := (others => dontcare_byte_c);
        k := (others => '0');
        s := (others => '0');

        d(0 to beat_byte_count-1) := prbs_byte_string(state_v, prbs31, beat_byte_count);
        k(0 to beat_byte_count-1) := (others => '1');
        s(0 to beat_byte_count-1) := (others => '1');
        state_v := prbs_forward(state_v, prbs31, beat_byte_count * 8);

        send(in_cfg_c, clock_s, input_s.s, input_s.m,
             bytes => d,
             keep => k,
             strobe => s,
             valid => true,
             last => beat_index = output_beat_count-1);
      end loop;
    end loop;

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  rx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable beat_v: master_t;
    variable k : std_ulogic_vector(0 to out_cfg_c.data_width-1);
    variable beat_count: natural;
    constant ratio : integer := in_cfg_c.data_width / out_cfg_c.data_width;
  begin
    done_s(1) <= '0';

    output_s.s <= accept(out_cfg_c, false);

    wait for 50 ns;

    for s in 1 to 16
    loop
      beat_count := s;
      if not in_cfg_c.has_keep then
        beat_count := ((s + ratio - 1) / ratio) * ratio;
      end if;

      for i in 0 to beat_count-1
      loop
        receive(out_cfg_c, clock_s, output_s.m, output_s.s, beat_v);
        k := keep(out_cfg_c, beat_v);
        if i < s then
          assert_equal("data", bytes(out_cfg_c, beat_v), prbs_byte_string(state_v, prbs31, out_cfg_c.data_width), failure);
          state_v := prbs_forward(state_v, prbs31, out_cfg_c.data_width * 8);
        end if;
        assert_equal("last", is_last(out_cfg_c, beat_v), i = beat_count-1, failure);
      end loop;
    end loop;

    wait for 500 ns;

    done_s(1) <= '1';
    wait;
  end process;

  dumper_in: nsl_axi.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => in_cfg_c,
      prefix_c => "IN"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => input_s
      );

  dumper_out: nsl_axi.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => out_cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => output_s
      );
  
  dut: nsl_axi.axi4_stream.axi4_stream_width_adapter
    generic map(
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
