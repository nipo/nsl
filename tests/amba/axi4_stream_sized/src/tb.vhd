library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is
  constant max_frame_size_c : integer := 128;

  signal clock_s, reset_n_s : std_ulogic;
  
  type config_pair_t is record
    framed : config_t;
    sized  : config_t;
  end record;
  
  type config_pair_vector_t is array (natural range <>) of config_pair_t;

  constant pairs_c : config_pair_vector_t := (
    0 => (framed => config(1, last => true), sized => config(1)),
    1 => (framed => config(1, last => true, keep => true), sized => config(2, keep => true)),
    2 => (framed => config(1, last => true, keep => true), sized => config(4, keep => true)),
    3 => (framed => config(2, last => true, keep => true), sized => config(2, keep => true)),
    4 => (framed => config(4, last => true, keep => true), sized => config(4, keep => true)),
    5 => (framed => config(2, last => true, keep => true), sized => config(1, keep => true)),
    6 => (framed => config(3, last => true, keep => true), sized => config(1, keep => true)),
    7 => (framed => config(4, last => true, keep => true), sized => config(1, keep => true)),
    8 => (framed => config(2, last => true, keep => true), sized => config(2, keep => true)),
    9 => (framed => config(4, last => true, keep => true), sized => config(2, keep => true)),
    10 => (framed => config(12, last => true, keep => true), sized => config(4, keep => true)),
    11 => (framed => config(2, last => true, keep => true), sized => config(4, keep => true)),
    12 => (framed => config(3, last => true, keep => true), sized => config(4, keep => true)),
    13 => (framed => config(6, last => true, keep => true), sized => config(4, keep => true)),
    14 => (framed => config(3, last => true, keep => true), sized => config(2, keep => true))
    );

  constant pairs_1b_c : config_pair_vector_t := (
    0 => (framed => config(1, last => true), sized => config(1)),
    1 => (framed => config(1, last => true, keep => true), sized => config(1, keep => true))
    );

  type frame_queue_root_vector_t is array (natural range <>) of frame_queue_root_t;
  shared variable master_q, slave_q, check_q : frame_queue_root_vector_t(0 to pairs_c'length-1);
  shared variable master_1b_q, slave_1b_q    : frame_queue_root_vector_t(0 to pairs_1b_c'length-1);

  signal done_s : std_ulogic_vector(0 to pairs_c'length + pairs_1b_c'length - 1) := (others => '0');
begin

  gen: for i in pairs_c'range generate
    signal framed_in_s  : bus_t;
    signal framed_out_s : bus_t;
    signal sized_s      : bus_t;

  begin
    trx: process
      variable state_v : prbs_state(30 downto 0) := x"deadbee" & "111";
    begin
      done_s(i) <= '0';
      frame_queue_init(master_q(i));
      frame_queue_init(slave_q(i));
      frame_queue_init(check_q(i));

      if i /= 0 then
        wait until done_s(i-1) = '1';
      end if;

      wait for 40 ns;

      -- Test various frame sizes
      for frame_size in pairs_c(i).framed.data_width to max_frame_size_c / pairs_c(i).framed.data_width
      loop
        frame_queue_check_io(master_q(i), slave_q(i), data => prbs_byte_string(state_v, prbs31, frame_size));
        state_v := prbs_forward(state_v, prbs31, frame_size * 8);
        -- nsl_simulation.logging.log_info("Sent and received frame of size " & integer'image(frame_size) & " for config " & integer'image(i));
      end loop;

      done_s(i) <= '1';
      wait;
    end process;

    master_proc: process is
    begin
      framed_in_s.m <= transfer_defaults(pairs_c(i).framed);
      wait for 40 ns;
      frame_queue_master(pairs_c(i).framed, master_q(i), clock_s, framed_in_s.s, framed_in_s.m);
    end process;

    slave_proc: process is
    begin
      framed_out_s.s <= accept(pairs_c(i).framed, false);
      wait for 40 ns;
      frame_queue_slave(pairs_c(i).framed, slave_q(i), clock_s, framed_out_s.m, framed_out_s.s);
    end process;

    -- Framed -> Sized converter
    from_framed: nsl_amba.stream_sized.axi4_stream_sized_deframing
      generic map(
        in_config_c => pairs_c(i).framed,
        out_config_c => pairs_c(i).sized,
        max_frame_size_c => max_frame_size_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => framed_in_s.m,
        in_o => framed_in_s.s,

        out_o => sized_s.m,
        out_i => sized_s.s
        );

    -- Sized -> Framed converter
    to_framed: nsl_amba.stream_sized.axi4_stream_sized_framing
      generic map(
        in_config_c => pairs_c(i).sized,
        out_config_c => pairs_c(i).framed
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        invalid_o => open,

        in_i => sized_s.m,
        in_o => sized_s.s,

        out_o => framed_out_s.m,
        out_i => framed_out_s.s
        );

    -- dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    --   generic map(
    --     config_c => pairs_c(i).framed,
    --     prefix_c => "FRAMED_IN"
    --     )
    --   port map(
    --     clock_i => clock_s,
    --     reset_n_i => reset_n_s,
    --     bus_i => framed_in_s
    --     );

    -- dumper_sized: nsl_amba.axi4_stream.axi4_stream_dumper
    --   generic map(
    --     config_c => pairs_c(i).sized,
    --     prefix_c => "SIZED"
    --     )
    --   port map(
    --     clock_i => clock_s,
    --     reset_n_i => reset_n_s,
    --     bus_i => sized_s
    --     );

    -- dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    --   generic map(
    --     config_c => pairs_c(i).framed,
    --     prefix_c => "FRAMED_OUT"
    --     )
    --   port map(
    --     clock_i => clock_s,
    --     reset_n_i => reset_n_s,
    --     bus_i => framed_out_s
    --     );

  end generate;

  gen_1b: for i in pairs_1b_c'range generate
    signal framed_in_s  : bus_t;
    signal framed_out_s : bus_t;
    signal sized_s      : bus_t;

  begin
    trx: process
      variable state_v : prbs_state(30 downto 0) := x"c0ffee0" & "111";
    begin
      done_s(pairs_c'length + i) <= '0';
      frame_queue_init(master_1b_q(i));
      frame_queue_init(slave_1b_q(i));

      if i = 0 then
        wait until done_s(pairs_c'length-1) = '1';
      else
        wait until done_s(pairs_c'length + i - 1) = '1';
      end if;

      wait for 40 ns;

      for frame_size in 1 to max_frame_size_c loop
        frame_queue_check_io(master_1b_q(i), slave_1b_q(i), data => prbs_byte_string(state_v, prbs31, frame_size));
        state_v := prbs_forward(state_v, prbs31, frame_size * 8);
      end loop;

      done_s(pairs_c'length + i) <= '1';
      wait;
    end process;

    master_proc: process is
    begin
      framed_in_s.m <= transfer_defaults(pairs_1b_c(i).framed);
      wait for 40 ns;
      frame_queue_master(pairs_1b_c(i).framed, master_1b_q(i), clock_s, framed_in_s.s, framed_in_s.m);
    end process;

    slave_proc: process is
    begin
      framed_out_s.s <= accept(pairs_1b_c(i).framed, false);
      wait for 40 ns;
      frame_queue_slave(pairs_1b_c(i).framed, slave_1b_q(i), clock_s, framed_out_s.m, framed_out_s.s);
    end process;

    from_framed: nsl_amba.stream_sized.axi4_stream_sized_deframing_1b
      generic map(
        in_config_c      => pairs_1b_c(i).framed,
        out_config_c     => pairs_1b_c(i).sized,
        max_frame_size_c => max_frame_size_c
        )
      port map(
        clock_i   => clock_s,
        reset_n_i => reset_n_s,
        in_i      => framed_in_s.m,
        in_o      => framed_in_s.s,
        out_o     => sized_s.m,
        out_i     => sized_s.s
        );

    to_framed: nsl_amba.stream_sized.axi4_stream_sized_framing_1b
      generic map(
        in_config_c  => pairs_1b_c(i).sized,
        out_config_c => pairs_1b_c(i).framed
        )
      port map(
        clock_i   => clock_s,
        reset_n_i => reset_n_s,
        invalid_o => open,
        in_i      => sized_s.m,
        in_o      => sized_s.s,
        out_o     => framed_out_s.m,
        out_i     => framed_out_s.s
        );

  end generate;

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
