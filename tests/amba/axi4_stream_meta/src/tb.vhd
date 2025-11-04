library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal input_s, middle_s, output_s: bus_t;
  shared variable master_q, slave_q, check_q: frame_queue_root_t;

  -- Input configuration with metadata
  constant in_cfg_c: config_t := config(bytes => 4, id => 8, dest => 8, user => 16, last => true);
  -- Middle configuration after packing (no metadata, same data width)
  constant mid_cfg_c: config_t := config(bytes => 4, last => true);
  -- Output configuration matches input
  constant out_cfg_c: config_t := config(bytes => 4, id => 8, dest => 8, user => 16, last => true);

begin

  trx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable frame_byte_count: integer;
    variable id_v : std_ulogic_vector(in_cfg_c.id_width-1 downto 0);
    variable dest_v : std_ulogic_vector(in_cfg_c.dest_width-1 downto 0);
    variable user_v : std_ulogic_vector(in_cfg_c.user_width-1 downto 0);
  begin
    done_s(0) <= '0';
    frame_queue_init(master_q);
    frame_queue_init(slave_q);
    frame_queue_init(check_q);

    wait for 40 ns;

    -- Test various frame sizes and metadata combinations
    for stream_beat_count in 1 to 16
    loop
      frame_byte_count := stream_beat_count * in_cfg_c.data_width;

      -- Generate varying metadata
      id_v := std_ulogic_vector(to_unsigned(stream_beat_count, in_cfg_c.id_width));
      dest_v := std_ulogic_vector(to_unsigned(stream_beat_count * 2, in_cfg_c.dest_width));
      user_v := std_ulogic_vector(to_unsigned(stream_beat_count * 3, in_cfg_c.user_width));

      frame_queue_put2(master_q, check_q,
                       data => prbs_byte_string(state_v, prbs31, frame_byte_count),
                       id => id_v,
                       dest => dest_v,
                       user => user_v);
      state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
    end loop;

    frame_queue_drain(in_cfg_c, master_q, timeout => 1 ms);
    wait for 10 us;

    frame_queue_assert_equal(out_cfg_c, slave_q, check_q);

    done_s(0) <= '1';
    wait;
  end process;

  master_proc: process is
  begin
    input_s.m <= transfer_defaults(in_cfg_c);
    wait for 40 ns;
    frame_queue_master(in_cfg_c, master_q, clock_s, input_s.s, input_s.m);
  end process;

  slave_proc: process is
  begin
    output_s.s <= accept(out_cfg_c, false);
    wait for 40 ns;
    frame_queue_slave(out_cfg_c, slave_q, clock_s, output_s.m, output_s.s);
  end process;

  dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => in_cfg_c,
      prefix_c => "IN"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => input_s
      );

  dumper_mid: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => mid_cfg_c,
      prefix_c => "MID"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => middle_s
      );

  dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => out_cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => output_s
      );

  packer: nsl_amba.stream_meta.axi4_stream_meta_packer
    generic map(
      in_config_c => in_cfg_c,
      out_config_c => mid_cfg_c,
      meta_elements_c => "iou",
      endian_c => ENDIAN_BIG
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => input_s.m,
      in_o => input_s.s,

      out_o => middle_s.m,
      out_i => middle_s.s
      );

  unpacker: nsl_amba.stream_meta.axi4_stream_meta_unpacker
    generic map(
      in_config_c => mid_cfg_c,
      out_config_c => out_cfg_c,
      meta_elements_c => "iou",
      endian_c => ENDIAN_BIG
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => middle_s.m,
      in_o => middle_s.s,

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
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
