library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_avalon;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s   : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s    : std_ulogic_vector(0 to 2);

begin

  -- Vector pack/unpack torture: build a random vector, decode it
  -- through vector_unpack, re-encode via vector_pack, and check the
  -- round-trip is bit-exact.
  vec_torture: process
    use nsl_avalon.avalon_st.all;

    procedure serializer_torture(cfg: config_t;
                                 elements: string;
                                 loops: integer)
    is
      variable serin_v, serout_v : std_ulogic_vector(vector_length(cfg, elements)-1 downto 0);
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    begin
      for i in 0 to loops-1
      loop
        serin_v := prbs_bit_string(state_v, prbs31, serin_v'length);
        serout_v := vector_pack(cfg, elements, vector_unpack(cfg, elements, serin_v));
        if serin_v /= serout_v then
          log_info("Hint: "&to_string(serin_v xor serout_v));
        end if;
        assert_equal(to_string(cfg), serin_v, serout_v, failure);
        state_v := prbs_forward(state_v, prbs31, serin_v'length);
      end loop;
      log_info(to_string(cfg) & " serializer torture OK");
    end procedure;

  begin
    done_s(0) <= '0';

    serializer_torture(config(symbols_per_beat => 1,
                              data_bits_per_symbol => 8),
                       "dv", 64);

    serializer_torture(config(symbols_per_beat => 4,
                              data_bits_per_symbol => 8,
                              has_packet => true,
                              has_empty => true),
                       "dvpqm", 64);

    serializer_torture(config(symbols_per_beat => 2,
                              data_bits_per_symbol => 16,
                              channel => 3,
                              packet_user => 5,
                              has_packet => true),
                       "dvpqcu", 64);

    serializer_torture(config(symbols_per_beat => 2,
                              data_bits_per_symbol => 8,
                              symbol_user => 3,
                              error => 4,
                              has_packet => true,
                              ready_latency => 2),
                       "dvpqes", 64);

    done_s(0) <= '1';
    wait;
  end process;

  -- Byte / data / symbol accessor round-trip.
  bytes_roundtrip: process
    use nsl_avalon.avalon_st.all;

    constant cfg_c : config_t := config(symbols_per_beat => 4,
                                        data_bits_per_symbol => 8,
                                        has_packet => true,
                                        has_empty => true);
    constant ref_c : byte_string(0 to 3) := from_hex("deadbeef");
    variable s   : source_t;
    variable bs  : byte_string(0 to 3);
    variable dv  : std_ulogic_vector(31 downto 0);
  begin
    done_s(1) <= '0';

    s := transfer(cfg_c, bytes => ref_c, sop => true, eop => true);
    bs := bytes(cfg_c, s);
    dv := data(cfg_c, s);

    assert_equal("bytes roundtrip", bs, ref_c, failure);
    assert_equal("byte_count", byte_count(cfg_c, s), 4, failure);
    assert is_sop(cfg_c, s) report "sop expected" severity failure;
    assert is_eop(cfg_c, s) report "eop expected" severity failure;
    assert symbol(cfg_c, s, 0) = std_ulogic_vector'(x"de")
      report "symbol(0) mismatch" severity failure;
    assert symbol(cfg_c, s, 3) = std_ulogic_vector'(x"ef")
      report "symbol(3) mismatch" severity failure;
    assert dv(7 downto 0) = x"de"
      report "data low bits should hold symbol 0" severity failure;

    s := transfer(cfg_c, bytes => ref_c, valid_symbols => 2,
                  sop => false, eop => true);
    assert_equal("valid_symbol_count", valid_symbol_count(cfg_c, s), 2, failure);
    assert_equal("empty count", empty(cfg_c, s), 2, failure);
    assert byte_count(cfg_c, s) = 2
      report "byte_count should drop to 2 on eop+empty" severity failure;

    log_info("bytes/data/symbol round-trip OK");

    done_s(1) <= '1';
    wait;
  end process;

  -- Dumper exercise: hands a few transfers to the dumper to make sure
  -- the clocked path and to_string() work end-to-end.
  dumper_inst: block
    use nsl_avalon.avalon_st.all;
    constant cfg_c : config_t := config(symbols_per_beat => 4,
                                        data_bits_per_symbol => 8,
                                        channel => 2,
                                        has_packet => true,
                                        has_empty => true);
    signal bus_s : bus_t;
    signal done_local : std_ulogic := '0';
  begin
    done_s(2) <= done_local;

    bus_s.snk <= accept(cfg_c, ready => true);

    src: process(clock_s, reset_n_s)
      variable count : natural := 0;
    begin
      if reset_n_s = '0' then
        bus_s.src <= transfer_defaults(cfg_c);
        count := 0;
      elsif rising_edge(clock_s) then
        case count is
          when 1 =>
            bus_s.src <= transfer(cfg_c, bytes => from_hex("01020304"),
                                  channel => "01", sop => true);
          when 2 =>
            bus_s.src <= transfer(cfg_c, bytes => from_hex("05060708"),
                                  channel => "01");
          when 3 =>
            bus_s.src <= transfer(cfg_c, bytes => from_hex("090a0000"),
                                  valid_symbols => 2,
                                  channel => "01", eop => true);
          when 8 =>
            done_local <= '1';
            bus_s.src <= transfer_defaults(cfg_c);
          when others =>
            bus_s.src <= transfer_defaults(cfg_c);
        end case;
        if count < 8 then
          count := count + 1;
        end if;
      end if;
    end process;

    dumper: avalon_st_dumper
      generic map(config_c => cfg_c, prefix_c => "AVST_DEMO")
      port map(clock_i => clock_s, reset_n_i => reset_n_s, bus_i => bus_s);
  end block;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count  => 3
      )
    port map(
      clock_period(0)   => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0)      => reset_n_s,
      clock_o(0)        => clock_s,
      done_i            => done_s
      );

end;
