library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_avalon;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;
use nsl_avalon.avalon_st.all;

entity tb is
end tb;

architecture arch of tb is

  -- Carries a representative mix of optional fields so vector_pack/unpack
  -- exercises packet framing, empty, channel, packet_user and symbol_user.
  constant cfg_c : config_t := config(symbols_per_beat     => 4,
                                      data_bits_per_symbol => 8,
                                      channel              => 3,
                                      packet_user          => 5,
                                      symbol_user          => 2,
                                      has_ready            => true,
                                      has_packet           => true,
                                      has_empty            => true);

  constant beat_count_c : natural := 64;

  signal in_clock_s, out_clock_s : std_ulogic;
  signal reset_n_s               : std_ulogic;
  signal done_s                  : std_ulogic_vector(0 to 0);

  signal input_s, output_s : bus_t;

  -- One PRBS state shared between producer and checker so they
  -- generate identical sequences.
  constant prbs_seed_c : prbs_state(30 downto 0) := x"deadbee"&"111";

begin

  dut: nsl_avalon.stream_fifo.avalon_st_fifo
    generic map(
      config_c      => cfg_c,
      depth_c       => 16,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => in_clock_s,
      clock_i(1) => out_clock_s,
      reset_n_i  => reset_n_s,

      in_i  => input_s.src,
      in_o  => input_s.snk,
      out_o => output_s.src,
      out_i => output_s.snk
      );

  producer: process
    variable state_v : prbs_state(30 downto 0) := prbs_seed_c;
    variable beat_v  : byte_string(0 to 3);
    variable ch_v    : std_ulogic_vector(2 downto 0);
    variable pu_v    : std_ulogic_vector(4 downto 0);
    variable su_v    : std_ulogic_vector(7 downto 0);
    variable n_v     : natural := 0;
  begin
    input_s.src <= transfer_defaults(cfg_c);
    wait until reset_n_s = '1';

    while n_v < beat_count_c loop
      wait until falling_edge(in_clock_s);

      beat_v := prbs_byte_string(state_v, prbs31, 4);
      state_v := prbs_forward(state_v, prbs31, 4*8);
      ch_v   := prbs_bit_string(state_v, prbs31, 3);
      state_v := prbs_forward(state_v, prbs31, 3);
      pu_v   := prbs_bit_string(state_v, prbs31, 5);
      state_v := prbs_forward(state_v, prbs31, 5);
      su_v   := prbs_bit_string(state_v, prbs31, 8);
      state_v := prbs_forward(state_v, prbs31, 8);

      input_s.src <= transfer(cfg_c,
                              bytes       => beat_v,
                              channel     => ch_v,
                              packet_user => pu_v,
                              symbol_user => su_v,
                              valid       => true,
                              sop         => n_v = 0,
                              eop         => n_v = beat_count_c - 1);

      -- Wait until the FIFO has accepted the beat this cycle.
      wait until rising_edge(in_clock_s);
      while input_s.snk.ready /= '1' loop
        wait until rising_edge(in_clock_s);
      end loop;

      n_v := n_v + 1;
    end loop;

    wait until falling_edge(in_clock_s);
    input_s.src <= transfer_defaults(cfg_c);
    wait;
  end process;

  checker: process
    variable state_v   : prbs_state(30 downto 0) := prbs_seed_c;
    variable beat_v    : byte_string(0 to 3);
    variable ch_v      : std_ulogic_vector(2 downto 0);
    variable pu_v      : std_ulogic_vector(4 downto 0);
    variable su_v      : std_ulogic_vector(7 downto 0);
    variable n_v       : natural := 0;
  begin
    output_s.snk <= accept(cfg_c, ready => false);
    done_s(0)    <= '0';

    wait until reset_n_s = '1';
    wait until falling_edge(out_clock_s);
    output_s.snk <= accept(cfg_c, ready => true);

    while n_v < beat_count_c loop
      wait until rising_edge(out_clock_s);

      if output_s.src.valid = '1' then
        beat_v := prbs_byte_string(state_v, prbs31, 4);
        state_v := prbs_forward(state_v, prbs31, 4*8);
        ch_v   := prbs_bit_string(state_v, prbs31, 3);
        state_v := prbs_forward(state_v, prbs31, 3);
        pu_v   := prbs_bit_string(state_v, prbs31, 5);
        state_v := prbs_forward(state_v, prbs31, 5);
        su_v   := prbs_bit_string(state_v, prbs31, 8);
        state_v := prbs_forward(state_v, prbs31, 8);

        assert_equal("beat "&integer'image(n_v),
                     bytes(cfg_c, output_s.src), beat_v, failure);
        assert_equal("channel "&integer'image(n_v),
                     channel(cfg_c, output_s.src), ch_v, failure);
        assert_equal("packet_user "&integer'image(n_v),
                     packet_user(cfg_c, output_s.src), pu_v, failure);
        assert std_ulogic_vector(output_s.src.symbol_user(7 downto 0)) = su_v
          report "symbol_user mismatch at beat "&integer'image(n_v)
          severity failure;

        if n_v = 0 then
          assert is_sop(cfg_c, output_s.src)
            report "expected sop on first beat" severity failure;
        end if;
        if n_v = beat_count_c - 1 then
          assert is_eop(cfg_c, output_s.src)
            report "expected eop on last beat" severity failure;
        end if;

        n_v := n_v + 1;
      end if;
    end loop;

    log_info("avalon_st_fifo "&integer'image(beat_count_c)&" beats OK");
    done_s(0) <= '1';
    wait;
  end process;

  watchdog: process
  begin
    wait for 50 us;
    log_info("watchdog timeout: done_s = "&to_string(done_s));
    terminate(1);
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count  => 1
      )
    port map(
      clock_period(0)   => 10 ns,
      clock_period(1)   => 7 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0)      => reset_n_s,
      clock_o(0)        => in_clock_s,
      clock_o(1)        => out_clock_s,
      done_i            => done_s
      );

end;
