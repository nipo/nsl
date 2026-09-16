library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

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

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  signal in_m_s, out_m_s : nsl_amba.axi4_stream.master_t;
  signal in_s_s, out_s_s : nsl_amba.axi4_stream.slave_t;

  function sample_of(value : integer) return sample_t
  is
  begin
    return to_sample(unsigned(to_signed(value, 8)), CODING_SIGNED);
  end function;

  function frame_of(left, right : integer) return frame_t
  is
    variable ret : frame_t := frame_zero_c;
  begin
    ret(0).sample := sample_of(left);
    ret(0).sideband(0) := '1';
    ret(0).sideband(1) := '0';
    ret(1).sample := sample_of(right);
    ret(1).sideband(0) := '0';
    ret(1).sideband(1) := '1';
    return ret;
  end function;

  function number_of(value : frame_t; channel : natural) return integer
  is
  begin
    return to_integer(signed(value(channel).sample(7 downto 0)));
  end function;

  procedure stream_put(
    signal m : out nsl_amba.axi4_stream.master_t;
    signal s : in nsl_amba.axi4_stream.slave_t;
    constant f : in frame_t;
    constant last : in boolean;
    constant block_start : in boolean;
    constant error : in boolean;
    constant id : in std_ulogic_vector;
    constant dest : in std_ulogic_vector) is
  begin
    wait until falling_edge(clock_s);
    m <= transfer(cfg_c, f,
                  id => id,
                  dest => dest,
                  last => last,
                  block_start => block_start,
                  error => error);

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
    variable f : out frame_t;
    variable observed : out nsl_amba.axi4_stream.master_t) is
  begin
    wait until falling_edge(clock_s);
    s <= accept(cfg_c, true);

    loop
      wait until rising_edge(clock_s);
      exit when is_valid(cfg_c, m);
    end loop;

    f := frame(cfg_c, m);
    observed := m;

    wait until falling_edge(clock_s);
    s <= accept(cfg_c, false);
  end procedure;

begin

  driver : nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length)
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 20 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s);

  octaver : nsl_audio.octaver.pcm_octaver
    generic map(
      in_config_c => cfg_c,
      out_config_c => cfg_c)
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      in_i => in_m_s,
      in_o => in_s_s,
      out_o => out_m_s,
      out_i => out_s_s);

  main : process is
    variable got : frame_t;
    variable observed : nsl_amba.axi4_stream.master_t;
    constant id_c : std_ulogic_vector(1 downto 0) := "10";
    constant dest_c : std_ulogic_vector(1 downto 0) := "01";
  begin
    in_m_s <= transfer_defaults(cfg_c);
    out_s_s <= accept(cfg_c, false);
    done_s <= "0";

    wait until reset_n_s = '1';

    -- The first rising crossing toggles the local oscillator immediately.
    stream_put(in_m_s, in_s_s, frame_of(-20, 20), false, true, false,
               id_c, dest_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = -20 and number_of(got, 1) = 20
      report "Initial octaver sample was changed"
      severity failure;

    stream_put(in_m_s, in_s_s, frame_of(20, -20), false, false, false,
               id_c, dest_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = -20 and number_of(got, 1) = -20
      report "Zero crossing did not change the local oscillator"
      severity failure;

    stream_put(in_m_s, in_s_s, frame_of(-20, 20), false, false, false,
               id_c, dest_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 20 and number_of(got, 1) = -20
      report "Octaver mixer did not invert the next half-cycle"
      severity failure;

    stream_put(in_m_s, in_s_s, frame_of(20, -20), true, false, true,
               id_c, dest_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = 20 and number_of(got, 1) = 20
      report "Second zero crossing did not restore polarity"
      severity failure;

    assert observed.last = '1'
      and observed.user(user_block_c) = '0'
      and observed.user(user_error_c) = '1'
      and observed.user(user_sideband_c) = '1'
      and observed.user(user_sideband_c + 1) = '0'
      and observed.user(user_sideband_c + 2) = '0'
      and observed.user(user_sideband_c + 3) = '1'
      and observed.id(1 downto 0) = id_c
      and observed.dest(1 downto 0) = dest_c
      and observed.keep(0) = '1'
      report "Octaver did not preserve packet or AXI sidebands"
      severity failure;

    -- The state is continuous across packet boundaries: after the last
    -- crossing above, a negative sample is not inverted.
    stream_put(in_m_s, in_s_s, frame_of(-20, 20), true, false, false,
               id_c, dest_c);
    stream_get(out_m_s, out_s_s, got, observed);
    assert number_of(got, 0) = -20 and number_of(got, 1) = 20
      report "Octaver phase was reset at a packet boundary"
      severity failure;

    report "Terminating with error level: 0" severity note;
    done_s <= "1";
    wait;
  end process;

end architecture;
