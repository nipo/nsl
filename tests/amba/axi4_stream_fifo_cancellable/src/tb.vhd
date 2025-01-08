library ieee, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb is
end tb;

library nsl_memory, nsl_simulation, nsl_amba, nsl_data;
use nsl_data.bytestream.all;
use nsl_simulation.assertions.all;
use nsl_amba.axi4_stream.all;
use nsl_data.prbs.all;



architecture arch of tb is

  constant cfg_c: config_t := config(16, last => true);

  signal in_clock_s, in_reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal input_s, output_s: bus_t;
  
  type side_t is
  record
    clock : std_ulogic;
    commit, rollback : std_ulogic;
  end record;

  signal t, r : side_t;

  procedure data_commit(signal clock : in std_ulogic;
                        signal commit : out std_ulogic) is
  begin
    commit <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    commit <= '0';
  end procedure;

  procedure data_rollback(signal clock : in std_ulogic;
                          signal rollback : out std_ulogic) is
  begin
    rollback <= '1';
    wait until rising_edge(clock);
    wait until falling_edge(clock);
    rollback <= '0';
  end procedure;
  
begin

  tx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable frame_byte_count: integer;
  begin
    done_s(0) <= '0';

    input_s.m <= transfer_defaults(cfg_c);

    wait for 105 ns;
    for stream_beat_count in 1 to 16
      loop
        frame_byte_count := stream_beat_count * cfg_c.data_width;

        packet_send(cfg_c, in_clock_s, input_s.s, input_s.m,
                    packet => prbs_byte_string(state_v, prbs31, frame_byte_count));
        if stream_beat_count mod 2 /= 0 then 
          data_commit(in_clock_s, t.commit);
        else 
          data_rollback(in_clock_s, t.rollback);
        end if;
        state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
      end loop;

    wait for 500 ns;

    done_s(0) <= '1';
    
    wait;
  end process;

  rx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable rx_data : byte_stream;
    variable frame_byte_count: integer;
    variable id, user, dest : std_ulogic_vector(1 to 0);
  begin
    done_s(1) <= '0';

    output_s.s <= accept(cfg_c, false);

    wait for 100 ns;

    for stream_beat_count in 1 to 16
      loop
        frame_byte_count := stream_beat_count * cfg_c.data_width;

        if stream_beat_count mod 2 /= 0 then
          packet_receive(cfg_c, in_clock_s, output_s.m, output_s.s,
                        packet => rx_data,
                        id => id,
                        user => user,
                        dest => dest);
          assert_equal("data", rx_data.all(0 to frame_byte_count-1), prbs_byte_string(state_v, prbs31, frame_byte_count), failure); 
        end if;
        state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
      end loop;    
    wait for 500 ns;

    done_s(1) <= '1';
    wait;
  end process;

  simdrv: nsl_simulation.driver.simulation_driver
  generic map(
    clock_count => 1,
    reset_count => 1,
    done_count => done_s'length
    )
  port map(
    clock_period(0) => 10 ns,
    reset_duration => (others => 100 ns),
    clock_o(0) => in_clock_s,
    reset_n_o(0) => in_reset_n_s,
    done_i => done_s
    );

  fifo: nsl_amba.stream_fifo.axi4_stream_fifo_cancellable
    generic map(
      config_c => cfg_c,
      word_count_l2_c => 20
      )
    port map(
      reset_n_i => in_reset_n_s,
      clock_i => in_clock_s,

      out_o => output_s.m,
      out_i => output_s.s,
      out_commit_i => r.commit,
      out_rollback_i => r.rollback,

      in_i => input_s.m,
      in_o => input_s.s,
      in_commit_i => t.commit,
      in_rollback_i => t.rollback
      );
end;
