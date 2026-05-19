library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_math, nsl_simulation, nsl_amba, nsl_avalon;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;
use nsl_avalon.axi4_stream_adapter.all;

entity tb is
end tb;

architecture arch of tb is

  -- 4-byte beat with packet framing, dest (3 bits) and user (5 bits).
  constant axi_cfg_c : nsl_amba.axi4_stream.config_t :=
    nsl_amba.axi4_stream.config(bytes => 4,
                                user  => 5,
                                dest  => 3,
                                keep  => true,
                                ready => true,
                                last  => true);

  constant avst_cfg_c : nsl_avalon.avalon_st.config_t := to_avalon_st(axi_cfg_c);

  constant packet_size_c : natural := 13;

  signal clock_s   : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s    : std_ulogic_vector(0 to 1);

  signal a2a_in_s,  a2a_out_s : nsl_amba.axi4_stream.bus_t;
  signal a2a_mid_s            : nsl_avalon.avalon_st.bus_t;

  signal v2v_in_s,  v2v_out_s : nsl_avalon.avalon_st.bus_t;
  signal v2v_mid_s            : nsl_amba.axi4_stream.bus_t;

  constant dest_const_c : std_ulogic_vector(2 downto 0) := "101";
  constant user_const_c : std_ulogic_vector(4 downto 0) := "11001";

begin

  -- =========================================================================
  -- Test 1: AXI -> Avalon -> AXI round-trip. Verifies axi4_stream_to_avalon_st
  -- followed by avalon_st_to_axi4_stream preserves every field.
  -- =========================================================================
  a2v: axi4_stream_to_avalon_st
    generic map(axi_config_c => axi_cfg_c, avst_config_c => avst_cfg_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             in_i  => a2a_in_s.m,   in_o  => a2a_in_s.s,
             out_o => a2a_mid_s.src, out_i => a2a_mid_s.snk);

  v2a: avalon_st_to_axi4_stream
    generic map(avst_config_c => avst_cfg_c, axi_config_c => axi_cfg_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             in_i  => a2a_mid_s.src, in_o  => a2a_mid_s.snk,
             out_o => a2a_out_s.m,   out_i => a2a_out_s.s);

  a2a_drv: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable expected_v : byte_string(0 to packet_size_c-1);
    variable wide_v  : byte_string(0 to 3);
    variable keep_v  : std_ulogic_vector(0 to 3);
    variable pos_v   : natural := 0;
    variable take_v  : natural;
  begin
    a2a_in_s.m <= nsl_amba.axi4_stream.transfer_defaults(axi_cfg_c);
    expected_v := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';

    while pos_v < packet_size_c loop
      wait until falling_edge(clock_s);
      take_v := nsl_math.arith.min(packet_size_c - pos_v, 4);
      wide_v := (others => x"00");
      keep_v := (others => '0');
      for k in 0 to take_v - 1 loop
        wide_v(k) := expected_v(pos_v + k);
        keep_v(k) := '1';
      end loop;

      a2a_in_s.m <= nsl_amba.axi4_stream.transfer(
        cfg    => axi_cfg_c,
        bytes  => wide_v,
        keep   => keep_v,
        user   => user_const_c,
        dest   => dest_const_c,
        valid  => true,
        last   => pos_v + take_v = packet_size_c);

      wait until rising_edge(clock_s);
      while a2a_in_s.s.ready /= '1' loop
        wait until rising_edge(clock_s);
      end loop;
      pos_v := pos_v + take_v;
    end loop;
    wait until falling_edge(clock_s);
    a2a_in_s.m <= nsl_amba.axi4_stream.transfer_defaults(axi_cfg_c);
    wait;
  end process;

  a2a_chk: process
    variable state_v   : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable expected_v: byte_string(0 to packet_size_c-1);
    variable observed_v: byte_string(0 to packet_size_c-1);
    variable wide_v    : byte_string(0 to 3);
    variable take_v    : natural;
    variable pos_v     : natural := 0;
  begin
    done_s(0)    <= '0';
    a2a_out_s.s  <= nsl_amba.axi4_stream.accept(axi_cfg_c, false);
    expected_v   := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';
    a2a_out_s.s <= nsl_amba.axi4_stream.accept(axi_cfg_c, true);

    while pos_v < packet_size_c loop
      wait until rising_edge(clock_s);
      if a2a_out_s.m.valid = '1' then
        wide_v := nsl_amba.axi4_stream.bytes(axi_cfg_c, a2a_out_s.m);
        take_v := nsl_amba.axi4_stream.byte_count(axi_cfg_c, a2a_out_s.m);

        assert_equal("a2a dest",
                     nsl_amba.axi4_stream.dest(axi_cfg_c, a2a_out_s.m),
                     dest_const_c, failure);
        assert_equal("a2a user",
                     nsl_amba.axi4_stream.user(axi_cfg_c, a2a_out_s.m),
                     user_const_c, failure);
        if pos_v + take_v >= packet_size_c then
          assert nsl_amba.axi4_stream.is_last(axi_cfg_c, a2a_out_s.m)
            report "a2a: expected tlast on last beat" severity failure;
        end if;

        for k in 0 to take_v - 1 loop
          observed_v(pos_v + k) := wide_v(k);
        end loop;
        pos_v := pos_v + take_v;
      end if;
    end loop;

    assert_equal("AXI->Avalon->AXI byte stream", observed_v, expected_v, failure);
    log_info("axi4_stream <-> avalon_st AXI round-trip OK");
    done_s(0) <= '1';
    wait;
  end process;

  -- =========================================================================
  -- Test 2: Avalon -> AXI -> Avalon round-trip. Symmetric.
  -- =========================================================================
  v2a2: avalon_st_to_axi4_stream
    generic map(avst_config_c => avst_cfg_c, axi_config_c => axi_cfg_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             in_i  => v2v_in_s.src, in_o  => v2v_in_s.snk,
             out_o => v2v_mid_s.m,  out_i => v2v_mid_s.s);

  a2v2: axi4_stream_to_avalon_st
    generic map(axi_config_c => axi_cfg_c, avst_config_c => avst_cfg_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             in_i  => v2v_mid_s.m,  in_o  => v2v_mid_s.s,
             out_o => v2v_out_s.src, out_i => v2v_out_s.snk);

  v2v_drv: process
    variable state_v : prbs_state(30 downto 0) := x"cafef00"&"101";
    variable expected_v : byte_string(0 to packet_size_c-1);
    variable wide_v : byte_string(0 to 3);
    variable pos_v  : natural := 0;
    variable take_v : natural;
  begin
    v2v_in_s.src <= nsl_avalon.avalon_st.transfer_defaults(avst_cfg_c);
    expected_v := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';

    while pos_v < packet_size_c loop
      wait until falling_edge(clock_s);
      take_v := nsl_math.arith.min(packet_size_c - pos_v, 4);
      wide_v := (others => x"00");
      for k in 0 to take_v - 1 loop
        wide_v(k) := expected_v(pos_v + k);
      end loop;

      v2v_in_s.src <= nsl_avalon.avalon_st.transfer(
        cfg           => avst_cfg_c,
        bytes         => wide_v,
        valid_symbols => nsl_logic.bool.if_else(take_v = 4, 0, take_v),
        channel       => dest_const_c,
        packet_user   => user_const_c,
        valid         => true,
        sop           => pos_v = 0,
        eop           => pos_v + take_v = packet_size_c);

      wait until rising_edge(clock_s);
      while v2v_in_s.snk.ready /= '1' loop
        wait until rising_edge(clock_s);
      end loop;
      pos_v := pos_v + take_v;
    end loop;
    wait until falling_edge(clock_s);
    v2v_in_s.src <= nsl_avalon.avalon_st.transfer_defaults(avst_cfg_c);
    wait;
  end process;

  v2v_chk: process
    variable state_v   : prbs_state(30 downto 0) := x"cafef00"&"101";
    variable expected_v: byte_string(0 to packet_size_c-1);
    variable observed_v: byte_string(0 to packet_size_c-1);
    variable wide_v    : byte_string(0 to 3);
    variable take_v    : natural;
    variable pos_v     : natural := 0;
    variable beat_idx_v: natural := 0;
  begin
    done_s(1)     <= '0';
    v2v_out_s.snk <= nsl_avalon.avalon_st.accept(avst_cfg_c, false);
    expected_v    := prbs_byte_string(state_v, prbs31, packet_size_c);

    wait until reset_n_s = '1';
    v2v_out_s.snk <= nsl_avalon.avalon_st.accept(avst_cfg_c, true);

    while pos_v < packet_size_c loop
      wait until rising_edge(clock_s);
      if v2v_out_s.src.valid = '1' then
        wide_v := nsl_avalon.avalon_st.bytes(avst_cfg_c, v2v_out_s.src);
        take_v := nsl_avalon.avalon_st.byte_count(avst_cfg_c, v2v_out_s.src);

        assert_equal("v2v channel",
                     nsl_avalon.avalon_st.channel(avst_cfg_c, v2v_out_s.src),
                     dest_const_c, failure);
        assert_equal("v2v packet_user",
                     nsl_avalon.avalon_st.packet_user(avst_cfg_c, v2v_out_s.src),
                     user_const_c, failure);
        if beat_idx_v = 0 then
          assert nsl_avalon.avalon_st.is_sop(avst_cfg_c, v2v_out_s.src)
            report "v2v: expected sop on first beat" severity failure;
        end if;
        if pos_v + take_v >= packet_size_c then
          assert nsl_avalon.avalon_st.is_eop(avst_cfg_c, v2v_out_s.src)
            report "v2v: expected eop on last beat" severity failure;
        end if;

        for k in 0 to take_v - 1 loop
          observed_v(pos_v + k) := wide_v(k);
        end loop;
        pos_v := pos_v + take_v;
        beat_idx_v := beat_idx_v + 1;
      end if;
    end loop;

    assert_equal("Avalon->AXI->Avalon byte stream", observed_v, expected_v, failure);
    log_info("axi4_stream <-> avalon_st Avalon round-trip OK");
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
