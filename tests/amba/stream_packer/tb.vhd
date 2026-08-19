library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Stimulus and checker around one axi4_stream_packer instance.
--
-- The stream carries a byte counter: byte of index N holds N mod 256
-- as data and bits of N / 256 as user bits.  Both sides derive the
-- sequence from the index alone, so a reordered, duplicated or lost
-- byte shows up as a value mismatch, and a byte taking the user bits
-- of another lane shows up as a user mismatch.
entity packer_checker is
  generic(
    name_c: string;
    data_width_c: positive;
    user_per_byte_c: natural;
    beat_count_c: positive;
    backpressure_c: boolean;
    seed_c: std_ulogic_vector(30 downto 0)
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    done_o: out std_ulogic
    );
end entity;

architecture beh of packer_checker is

  constant user_width_c: natural := data_width_c * user_per_byte_c;
  constant cfg_c: config_t := config(bytes => data_width_c,
                                     user => user_width_c,
                                     strobe => true);
  constant full_strobe_c: std_ulogic_vector(0 to data_width_c-1) := (others => '1');
  -- Cycles without an output beat after the stimulus ended before the
  -- pipeline is considered empty.  Latency is data_width+1, plus
  -- backpressure.
  constant drain_c: natural := 64;

  signal in_s, out_s: bus_t;
  signal sender_done_s: boolean;
  signal sent_count_s: natural;

  function tx_byte(index: natural) return byte
  is
  begin
    return byte(to_unsigned(index mod 256, 8));
  end function;

  function tx_user(index: natural) return std_ulogic_vector
  is
    variable v: unsigned(31 downto 0) := to_unsigned((index / 256) mod 65536, 32);
    variable ret: std_ulogic_vector(user_per_byte_c-1 downto 0);
  begin
    for i in ret'range
    loop
      ret(i) := v(i);
    end loop;
    return ret;
  end function;

begin

  sender: process is
    variable state_v: prbs_state(30 downto 0) := prbs_state(seed_c);
    variable ctrl_v: std_ulogic_vector(0 to data_width_c+15);
    variable junk_v: byte_string(0 to data_width_c-1);
    variable strobe_v: std_ulogic_vector(0 to data_width_c-1);
    variable data_v: byte_string(0 to data_width_c-1);
    variable user_v: std_ulogic_vector(user_width_c-1 downto 0);
    variable mode_v, gap_v: integer;
    variable count_v: natural := 0;
  begin
    in_s.m <= transfer_defaults(cfg_c);
    sender_done_s <= false;
    sent_count_s <= 0;

    wait for 40 ns;
    wait until falling_edge(clock_i);

    for beat in 1 to beat_count_c
    loop
      ctrl_v := prbs_bit_string(state_v, prbs31, ctrl_v'length);
      state_v := prbs_forward(state_v, prbs31, ctrl_v'length);
      junk_v := prbs_byte_string(state_v, prbs31, data_width_c);
      state_v := prbs_forward(state_v, prbs31, 8 * data_width_c);

      mode_v := to_integer(unsigned(ctrl_v(data_width_c to data_width_c+7)));
      gap_v := to_integer(unsigned(ctrl_v(data_width_c+8 to data_width_c+15)));

      strobe_v := ctrl_v(0 to data_width_c-1);
      if mode_v < 24 then
        strobe_v := (others => '0');
      elsif mode_v < 72 then
        strobe_v := (others => '1');
      elsif mode_v < 96 then
        strobe_v := (others => '0');
        strobe_v(mode_v mod data_width_c) := '1';
      end if;

      -- Lanes that are not strobed carry data unrelated to the
      -- sequence and inverted user bits, so that a packer picking a
      -- masked-out lane cannot go unnoticed.
      for i in 0 to data_width_c-1
      loop
        if strobe_v(i) = '1' then
          data_v(i) := tx_byte(count_v);
          if user_per_byte_c /= 0 then
            user_v((i+1)*user_per_byte_c-1 downto i*user_per_byte_c) := tx_user(count_v);
          end if;
          count_v := count_v + 1;
        else
          data_v(i) := junk_v(i);
          if user_per_byte_c /= 0 then
            user_v((i+1)*user_per_byte_c-1 downto i*user_per_byte_c) := not tx_user(count_v);
          end if;
        end if;
      end loop;

      send(cfg_c, clock_i, in_s.s, in_s.m,
           bytes => data_v,
           strobe => strobe_v,
           user => user_v);
      sent_count_s <= count_v;

      if gap_v >= 160 then
        for i in 1 to (gap_v - 160) / 32 + 1
        loop
          wait until falling_edge(clock_i);
        end loop;
      end if;
    end loop;

    sender_done_s <= true;

    wait;
  end process;

  checker: process is
    variable state_v: prbs_state(30 downto 0) := prbs_state(not seed_c);
    variable bits_v: std_ulogic_vector(0 to 7);
    variable beat_v: master_t;
    variable data_v: byte_string(0 to data_width_c-1);
    variable user_v: std_ulogic_vector(user_width_c-1 downto 0);
    variable ready_v: boolean;
    variable expected_v: natural := 0;
    variable idle_v: natural := 0;
  begin
    done_o <= '0';
    out_s.s <= accept(cfg_c, false);

    wait for 40 ns;

    loop
      wait until falling_edge(clock_i);

      if backpressure_c then
        bits_v := prbs_bit_string(state_v, prbs31, bits_v'length);
        state_v := prbs_forward(state_v, prbs31, bits_v'length);
        ready_v := to_integer(unsigned(bits_v)) >= 64;
      else
        ready_v := true;
      end if;
      out_s.s <= accept(cfg_c, ready_v);

      wait until rising_edge(clock_i);

      if ready_v and is_valid(cfg_c, out_s.m) then
        beat_v := out_s.m;
        data_v := bytes(cfg_c, beat_v);
        user_v := user(cfg_c, beat_v);

        assert_equal(name_c, "output strobe",
                     strobe(cfg_c, beat_v), full_strobe_c, FAILURE);

        for i in 0 to data_width_c-1
        loop
          assert_equal(name_c, "data of byte "&to_string(expected_v),
                       data_v(i), tx_byte(expected_v), FAILURE);
          if user_per_byte_c /= 0 then
            assert_equal(name_c, "user of byte "&to_string(expected_v),
                         user_v((i+1)*user_per_byte_c-1 downto i*user_per_byte_c),
                         tx_user(expected_v), FAILURE);
          end if;
          expected_v := expected_v + 1;
        end loop;

        idle_v := 0;
      else
        idle_v := idle_v + 1;
      end if;

      exit when sender_done_s and idle_v > drain_c;
    end loop;

    -- Nothing is dropped and only full beats leave, so what is left
    -- in the buffer is exactly the remainder of the division.
    assert_equal(name_c, "packed byte count",
                 expected_v, sent_count_s - (sent_count_s mod data_width_c),
                 FAILURE);

    log_info(name_c, "packed "&to_string(expected_v)&" bytes out of "
             &to_string(sent_count_s)&" strobed bytes sent");

    done_o <= '1';

    wait;
  end process;

  dut: nsl_amba.stream_processing.axi4_stream_packer
    generic map(
      config_c => cfg_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => in_s.m,
      in_o => in_s.s,

      out_o => out_s.m,
      out_i => out_s.s
      );

end architecture;

library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 2);

begin

  -- Degenerate width: the packer can only drop the empty beats.
  narrow: entity work.packer_checker
    generic map(
      name_c => "packer 1B",
      data_width_c => 1,
      user_per_byte_c => 0,
      beat_count_c => 3000,
      backpressure_c => false,
      seed_c => x"deadbee"&"111"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  -- One user bit per byte, as an 8b10b stream would carry its control
  -- flag.
  medium: entity work.packer_checker
    generic map(
      name_c => "packer 4B",
      data_width_c => 4,
      user_per_byte_c => 1,
      beat_count_c => 3000,
      backpressure_c => true,
      seed_c => x"1234567"&"101"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  wide: entity work.packer_checker
    generic map(
      name_c => "packer 8B",
      data_width_c => 8,
      user_per_byte_c => 2,
      beat_count_c => 3000,
      backpressure_c => true,
      seed_c => x"0badf00"&"011"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
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
