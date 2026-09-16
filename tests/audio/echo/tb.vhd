library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_math, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_math.fixed.all;

entity tb is
end entity;

architecture arch of tb is

  constant cfg_c : config_t := config(
    channels => 2,
    sample_bits => 8,
    sideband_bits => 2,
    frames_per_packet => 4,
    id => 2,
    dest => 2,
    keep => true,
    ready => true);

  constant zero_gain_c : ufixed(1 downto -8) := to_ufixed(0.0, 1, -8);
  constant half_gain_c : ufixed(1 downto -8) := to_ufixed(0.5, 1, -8);
  constant unity_gain_c : ufixed(1 downto -8) := to_ufixed(1.0, 1, -8);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  signal in_m_s, out_m_s : nsl_amba.axi4_stream.master_t;
  signal in_s_s, out_s_s : nsl_amba.axi4_stream.slave_t;
  signal delay_s : unsigned(1 downto 0);
  signal dry_s, wet_s, feedback_s : ufixed(1 downto -8);

  function sample_of(value : integer) return sample_t
  is
  begin
    return to_sample(unsigned(to_signed(value, 8)), CODING_SIGNED);
  end function;

  function frame_of(left, right : integer;
                    sidebands : std_ulogic_vector(1 downto 0)) return frame_t
  is
    variable ret : frame_t := frame_zero_c;
  begin
    ret(0).sample := sample_of(left);
    ret(1).sample := sample_of(right);
    ret(0).sideband(1 downto 0) := sidebands;
    ret(1).sideband(1 downto 0) := not sidebands;
    return ret;
  end function;

  function number_of(value : frame_t; channel : natural) return integer
  is
  begin
    return to_integer(signed(value(channel).sample(7 downto 0)));
  end function;

  procedure check_samples(constant got : frame_t;
                          constant expected : frame_t;
                          constant message : string) is
  begin
    for channel in 0 to cfg_c.channel_count-1
    loop
      assert got(channel).sample = expected(channel).sample
        report message & ": sample changed"
        severity failure;
    end loop;
  end procedure;

  procedure check_sidebands(constant got : frame_t;
                            constant expected : frame_t;
                            constant message : string) is
  begin
    for channel in 0 to cfg_c.channel_count-1
    loop
      assert got(channel).sideband(1 downto 0)
        = expected(channel).sideband(1 downto 0)
        report message & ": sideband changed"
        severity failure;
    end loop;
  end procedure;

  procedure check_metadata(
    constant observed : nsl_amba.axi4_stream.master_t;
    constant last : boolean;
    constant block_start : boolean;
    constant error : boolean;
    constant id : std_ulogic_vector(1 downto 0);
    constant dest : std_ulogic_vector(1 downto 0);
    constant message : string) is
  begin
    assert is_last(cfg_c, observed) = last
      and is_block(cfg_c, observed) = block_start
      and is_error(cfg_c, observed) = error
      report message & ": packet markers changed"
      severity failure;
    assert observed.id(1 downto 0) = id
      and observed.dest(1 downto 0) = dest
      report message & ": ID or destination changed"
      severity failure;
    assert observed.keep(0) = '1' and observed.keep(1) = '1'
      report message & ": TKEEP was not preserved"
      severity failure;
  end procedure;

  procedure stream_put(
    signal m : out nsl_amba.axi4_stream.master_t;
    signal s : in nsl_amba.axi4_stream.slave_t;
    constant value : frame_t;
    constant last : boolean;
    constant block_start : boolean;
    constant error : boolean;
    constant id : std_ulogic_vector(1 downto 0);
    constant dest : std_ulogic_vector(1 downto 0)) is
  begin
    wait until falling_edge(clock_s);
    m <= transfer(cfg_c, value, id => id, dest => dest,
                  last => last, block_start => block_start, error => error);

    loop
      wait until rising_edge(clock_s);
      exit when is_ready(cfg_c, s);
    end loop;

    wait until falling_edge(clock_s);
    m <= transfer_defaults(cfg_c);
  end procedure;

  procedure stream_get(
    signal m : in nsl_amba.axi4_stream.master_t;
    signal s : out nsl_amba.axi4_stream.slave_t;
    variable value : out frame_t;
    variable observed : out nsl_amba.axi4_stream.master_t) is
  begin
    wait until falling_edge(clock_s);
    s <= accept(cfg_c, true);

    loop
      wait until rising_edge(clock_s);
      exit when is_valid(cfg_c, m);
    end loop;

    value := frame(cfg_c, m);
    observed := m;

    wait until falling_edge(clock_s);
    s <= accept(cfg_c, false);
  end procedure;

  procedure flush_to(
    constant value : natural;
    signal delay : out unsigned;
    signal input_m : out nsl_amba.axi4_stream.master_t;
    signal input_s : in nsl_amba.axi4_stream.slave_t;
    signal output_m : in nsl_amba.axi4_stream.master_t;
    signal output_s : out nsl_amba.axi4_stream.slave_t) is
    variable cycles : natural := 0;
  begin
    wait until falling_edge(clock_s);
    delay <= to_unsigned(value, delay'length);
    input_m <= transfer_defaults(cfg_c);
    output_s <= accept(cfg_c, false);

    loop
      wait until rising_edge(clock_s);
      cycles := cycles + 1;
      assert not is_valid(cfg_c, output_m)
        report "Delay change exposed stale output"
        severity failure;
      exit when is_ready(cfg_c, input_s);
    end loop;

    assert cycles >= 5
      report "Delay change did not perform the complete memory flush"
      severity failure;
  end procedure;

begin

  driver : nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length)
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s);

  echo : nsl_audio.ambience.pcm_echo
    generic map(
      in_config_c => cfg_c,
      out_config_c => cfg_c,
      max_delay_l2_c => 2,
      guard_bits_c => 4)
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      in_i => in_m_s,
      in_o => in_s_s,
      out_o => out_m_s,
      out_i => out_s_s,
      delay_i => delay_s,
      dry_i => dry_s,
      wet_i => wet_s,
      feedback_i => feedback_s);

  main : process is
    variable got : frame_t;
    variable observed : nsl_amba.axi4_stream.master_t;
    constant frame_a_c : frame_t := frame_of(10, -10, "01");
    constant frame_b_c : frame_t := frame_of(20, -20, "10");
    constant frame_c_c : frame_t := frame_of(30, -30, "11");
    constant id_a_c : std_ulogic_vector(1 downto 0) := "01";
    constant dest_a_c : std_ulogic_vector(1 downto 0) := "10";
    constant id_b_c : std_ulogic_vector(1 downto 0) := "10";
    constant dest_b_c : std_ulogic_vector(1 downto 0) := "01";
  begin
    in_m_s <= transfer_defaults(cfg_c);
    out_s_s <= accept(cfg_c, false);
    delay_s <= to_unsigned(1, delay_s'length);
    dry_s <= zero_gain_c;
    wet_s <= unity_gain_c;
    feedback_s <= zero_gain_c;
    done_s <= "0";

    wait until reset_n_s = '0';
    in_m_s <= transfer(cfg_c, frame_a_c);
    wait until rising_edge(clock_s);
    assert not is_ready(cfg_c, in_s_s)
      and not is_valid(cfg_c, out_m_s)
      report "Reset did not flush or backpressure the echo"
      severity failure;
    wait until falling_edge(clock_s);
    in_m_s <= transfer_defaults(cfg_c);

    wait until reset_n_s = '1';

    -- The first frame after reset has an empty one-frame delay line.
    stream_put(in_m_s, in_s_s, frame_a_c, false, true, false,
               id_a_c, dest_a_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 0 and number_of(got, 1) = 0
      report "Reset did not clear the wet path"
      severity failure;
    check_samples(got, frame_zero_c, "Reset output");
    check_sidebands(got, frame_a_c, "Reset metadata");
    check_metadata(observed, false, true, false, id_a_c, dest_a_c,
                   "First frame metadata");

    -- Wet audio is one accepted frame old, while metadata follows the
    -- current frame.
    stream_put(in_m_s, in_s_s, frame_b_c, true, false, true,
               id_b_c, dest_b_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 10 and number_of(got, 1) = -10
      report "Wet output was not delayed by one frame"
      severity failure;
    check_samples(got, frame_a_c, "Delayed audio");
    check_sidebands(got, frame_b_c, "Delayed metadata");
    check_metadata(observed, true, false, true, id_b_c, dest_b_c,
                   "Delayed frame metadata");

    -- Changing the delay clears old audio before accepting the new setting.
    feedback_s <= half_gain_c;
    flush_to(2, delay_s, in_m_s, in_s_s, out_m_s, out_s_s);
    stream_put(in_m_s, in_s_s, frame_c_c, false, true, false,
               id_a_c, dest_a_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 0 and number_of(got, 1) = 0
      report "Delay-change flush leaked the previous delay line"
      severity failure;

    -- With a two-frame delay, the input reaches the output first, then
    -- returns once more through the half-strength feedback path.
    stream_put(in_m_s, in_s_s, frame_zero_c, false, false, false,
               id_a_c, dest_a_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 0 and number_of(got, 1) = 0
      report "Two-frame delay produced audio too early"
      severity failure;

    stream_put(in_m_s, in_s_s, frame_zero_c, false, false, false,
               id_a_c, dest_a_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 30 and number_of(got, 1) = -30
      report "Delayed frame did not reach the output"
      severity failure;

    stream_put(in_m_s, in_s_s, frame_zero_c, false, false, false,
               id_a_c, dest_a_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 0 and number_of(got, 1) = 0
      report "Feedback appeared at the wrong delay"
      severity failure;

    stream_put(in_m_s, in_s_s, frame_zero_c, true, false, false,
               id_a_c, dest_a_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 15 and number_of(got, 1) = -15
      report "Feedback level was not preserved"
      severity failure;

    report "Terminating with error level: 0" severity note;
    done_s <= "1";
    wait;
  end process;

end architecture;
