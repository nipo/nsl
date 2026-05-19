library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_math, nsl_simulation, nsl_avalon;
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

  function mkcfg(spb: positive) return config_t is
  begin
    return config(symbols_per_beat     => spb,
                  data_bits_per_symbol => 8,
                  channel              => 3,
                  packet_user          => 5,
                  symbol_user          => 0,
                  has_ready            => true,
                  has_packet           => true,
                  has_empty            => spb > 1);
  end function;

  constant cfg1_c : config_t := mkcfg(1);
  constant cfg4_c : config_t := mkcfg(4);

  -- Packet size deliberately not a multiple of 4 to exercise the
  -- widener's PAD path and the narrower's mid-beat empty handling.
  constant packet_size_c : natural := 13;
  constant seed_w_c      : prbs_state(30 downto 0) := x"deadbee"&"111";
  constant seed_n_c      : prbs_state(30 downto 0) := x"cafef00"&"101";

  signal clock_s   : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s    : std_ulogic_vector(0 to 1);

  signal widen_in_s,  widen_out_s  : bus_t;
  signal narrow_in_s, narrow_out_s : bus_t;

  constant ch_const_c : std_ulogic_vector(2 downto 0) := "101";
  constant pu_const_c : std_ulogic_vector(4 downto 0) := "11001";

begin

  -- ----------------- Widening: 1 byte/beat -> 4 bytes/beat -----------------
  widener: avalon_st_width_adapter
    generic map(in_config_c => cfg1_c, out_config_c => cfg4_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             in_i => widen_in_s.src,  in_o => widen_in_s.snk,
             out_o => widen_out_s.src, out_i => widen_out_s.snk);

  widen_in_drv: process
    variable expected_v : byte_string(0 to packet_size_c-1);
    variable beat_v     : byte_string(0 to 0);
    variable state_v    : prbs_state(30 downto 0) := seed_w_c;
    variable idx_v      : natural := 0;
  begin
    widen_in_s.src <= transfer_defaults(cfg1_c);
    expected_v     := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';

    while idx_v < packet_size_c loop
      wait until falling_edge(clock_s);
      beat_v(0) := expected_v(idx_v);
      widen_in_s.src <= transfer(cfg1_c,
                                 bytes       => beat_v,
                                 channel     => ch_const_c,
                                 packet_user => pu_const_c,
                                 valid       => true,
                                 sop         => idx_v = 0,
                                 eop         => idx_v = packet_size_c - 1);
      wait until rising_edge(clock_s);
      while widen_in_s.snk.ready /= '1' loop
        wait until rising_edge(clock_s);
      end loop;
      idx_v := idx_v + 1;
    end loop;
    wait until falling_edge(clock_s);
    widen_in_s.src <= transfer_defaults(cfg1_c);
    wait;
  end process;

  widen_out_chk: process
    variable expected_v : byte_string(0 to packet_size_c-1);
    variable observed_v : byte_string(0 to packet_size_c-1);
    variable state_v    : prbs_state(30 downto 0) := seed_w_c;
    variable wide_v     : byte_string(0 to 3);
    variable take_v     : natural;
    variable idx_v      : natural := 0;
  begin
    done_s(0)       <= '0';
    widen_out_s.snk <= accept(cfg4_c, ready => false);
    expected_v      := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';
    widen_out_s.snk <= accept(cfg4_c, ready => true);

    while idx_v < packet_size_c loop
      wait until rising_edge(clock_s);
      if widen_out_s.src.valid = '1' then
        wide_v := bytes(cfg4_c, widen_out_s.src);
        take_v := byte_count(cfg4_c, widen_out_s.src);

        assert_equal("widen channel",     channel(cfg4_c, widen_out_s.src), ch_const_c, failure);
        assert_equal("widen packet_user", packet_user(cfg4_c, widen_out_s.src), pu_const_c, failure);
        if idx_v = 0 then
          assert is_sop(cfg4_c, widen_out_s.src)
            report "widen: expected sop on first emitted beat" severity failure;
        end if;
        if idx_v + take_v >= packet_size_c then
          assert is_eop(cfg4_c, widen_out_s.src)
            report "widen: expected eop on last emitted beat" severity failure;
        end if;

        for k in 0 to take_v - 1 loop
          observed_v(idx_v + k) := wide_v(k);
        end loop;
        idx_v := idx_v + take_v;
      end if;
    end loop;

    assert_equal("widen byte stream", observed_v, expected_v, failure);

    log_info("avalon_st_width_adapter 1->4 OK");
    done_s(0) <= '1';
    wait;
  end process;

  -- ----------------- Narrowing: 4 bytes/beat -> 1 byte/beat ----------------
  narrower: avalon_st_width_adapter
    generic map(in_config_c => cfg4_c, out_config_c => cfg1_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             in_i => narrow_in_s.src,  in_o => narrow_in_s.snk,
             out_o => narrow_out_s.src, out_i => narrow_out_s.snk);

  narrow_in_drv: process
    variable expected_v   : byte_string(0 to packet_size_c-1);
    variable wide_v       : byte_string(0 to 3);
    variable state_v      : prbs_state(30 downto 0) := seed_n_c;
    variable pos_v        : natural := 0;
    variable take_v       : natural;
  begin
    narrow_in_s.src <= transfer_defaults(cfg4_c);
    expected_v      := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';

    while pos_v < packet_size_c loop
      wait until falling_edge(clock_s);
      take_v := nsl_math.arith.min(packet_size_c - pos_v, 4);
      wide_v := (others => x"00");
      for k in 0 to take_v - 1 loop
        wide_v(k) := expected_v(pos_v + k);
      end loop;

      narrow_in_s.src <= transfer(cfg4_c,
                                  bytes         => wide_v,
                                  valid_symbols => nsl_logic.bool.if_else(take_v = 4, 0, take_v),
                                  channel       => ch_const_c,
                                  packet_user   => pu_const_c,
                                  valid         => true,
                                  sop           => pos_v = 0,
                                  eop           => pos_v + take_v = packet_size_c);
      wait until rising_edge(clock_s);
      while narrow_in_s.snk.ready /= '1' loop
        wait until rising_edge(clock_s);
      end loop;
      pos_v := pos_v + take_v;
    end loop;
    wait until falling_edge(clock_s);
    narrow_in_s.src <= transfer_defaults(cfg4_c);
    wait;
  end process;

  narrow_out_chk: process
    variable expected_v : byte_string(0 to packet_size_c-1);
    variable observed_v : byte_string(0 to packet_size_c-1);
    variable state_v    : prbs_state(30 downto 0) := seed_n_c;
    variable narrow_v   : byte_string(0 to 0);
    variable idx_v      : natural := 0;
  begin
    done_s(1)        <= '0';
    narrow_out_s.snk <= accept(cfg1_c, ready => false);
    expected_v       := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';
    narrow_out_s.snk <= accept(cfg1_c, ready => true);

    while idx_v < packet_size_c loop
      wait until rising_edge(clock_s);
      if narrow_out_s.src.valid = '1' then
        narrow_v := bytes(cfg1_c, narrow_out_s.src);
        assert_equal("narrow channel",     channel(cfg1_c, narrow_out_s.src), ch_const_c, failure);
        assert_equal("narrow packet_user", packet_user(cfg1_c, narrow_out_s.src), pu_const_c, failure);
        if idx_v = 0 then
          assert is_sop(cfg1_c, narrow_out_s.src)
            report "narrow: expected sop on first beat" severity failure;
        end if;
        if idx_v = packet_size_c - 1 then
          assert is_eop(cfg1_c, narrow_out_s.src)
            report "narrow: expected eop on last beat" severity failure;
        end if;
        observed_v(idx_v) := narrow_v(0);
        idx_v := idx_v + 1;
      end if;
    end loop;

    assert_equal("narrow byte stream", observed_v, expected_v, failure);

    log_info("avalon_st_width_adapter 4->1 OK");
    done_s(1) <= '1';
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
      clock_count => 1,
      reset_count => 1,
      done_count  => 2
      )
    port map(
      clock_period(0)   => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0)      => reset_n_s,
      clock_o(0)        => clock_s,
      done_i            => done_s
      );

end;
