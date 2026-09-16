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
    channels => 1,
    sample_bits => 8,
    sideband_bits => 2,
    frames_per_packet => 4,
    id => 2,
    dest => 2,
    keep => true,
    ready => true);

  constant half_gain_c : ufixed(1 downto -8) := to_ufixed(0.5, 1, -8);
  constant unity_gain_c : ufixed(1 downto -8) := to_ufixed(1.0, 1, -8);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  signal in_a_m_s, in_b_m_s, out_m_s : nsl_amba.axi4_stream.master_t;
  signal in_a_s_s, in_b_s_s, out_s_s : nsl_amba.axi4_stream.slave_t;

  function sample_of(value : integer) return sample_t
  is
  begin
    return to_sample(unsigned(to_signed(value, 8)), CODING_SIGNED);
  end function;

  function frame_of(value : integer;
                    sideband : std_ulogic_vector(1 downto 0)) return frame_t
  is
    variable ret : frame_t := frame_zero_c;
  begin
    ret(0).sample := sample_of(value);
    ret(0).sideband(1 downto 0) := sideband;
    return ret;
  end function;

  function number_of(value : frame_t) return integer
  is
  begin
    return to_integer(signed(value(0).sample(7 downto 0)));
  end function;

  procedure put_pair(
    signal m_a : out nsl_amba.axi4_stream.master_t;
    signal m_b : out nsl_amba.axi4_stream.master_t;
    signal s_a : in nsl_amba.axi4_stream.slave_t;
    signal s_b : in nsl_amba.axi4_stream.slave_t;
    constant f_a : in frame_t;
    constant f_b : in frame_t;
    constant last : in boolean;
    constant block_start : in boolean;
    constant error : in boolean;
    constant id : in std_ulogic_vector(1 downto 0);
    constant dest : in std_ulogic_vector(1 downto 0)) is
  begin
    wait until falling_edge(clock_s);
    m_a <= transfer(cfg_c, f_a, id => id, dest => dest,
                    last => last, block_start => block_start, error => error);
    m_b <= transfer(cfg_c, f_b, id => id, dest => dest,
                    last => last, block_start => block_start, error => error);

    loop
      wait until rising_edge(clock_s);
      exit when is_ready(cfg_c, s_a) and is_ready(cfg_c, s_b);
    end loop;

    wait until falling_edge(clock_s);
    m_a <= transfer_defaults(cfg_c);
    m_b <= transfer_defaults(cfg_c);
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

  mixer : nsl_audio.mixer.pcm_mixer
    generic map(
      in_a_config_c => cfg_c,
      in_b_config_c => cfg_c,
      out_config_c => cfg_c)
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      in_a_i => in_a_m_s,
      in_a_o => in_a_s_s,
      in_b_i => in_b_m_s,
      in_b_o => in_b_s_s,
      out_o => out_m_s,
      out_i => out_s_s,
      gain_a_i => half_gain_c,
      gain_b_i => half_gain_c);

  main : process is
    variable got : frame_t;
    variable observed : nsl_amba.axi4_stream.master_t;
    constant id_c : std_ulogic_vector(1 downto 0) := "10";
    constant dest_c : std_ulogic_vector(1 downto 0) := "01";
  begin
    in_a_m_s <= transfer_defaults(cfg_c);
    in_b_m_s <= transfer_defaults(cfg_c);
    out_s_s <= accept(cfg_c, false);
    done_s <= "0";

    assert cfg_c = cfg_c
      and compatible(cfg_c, cfg_c)
      and same_frame(cfg_c, cfg_c)
      and same_stream(cfg_c, cfg_c)
      report "PCM stream configuration helpers failed"
      severity failure;

    wait until reset_n_s = '1';
    put_pair(in_a_m_s, in_b_m_s, in_a_s_s, in_b_s_s,
             frame_of(10, "01"), frame_of(20, "10"),
             true, true, true, id_c, dest_c);

    wait until falling_edge(clock_s);
    out_s_s <= accept(cfg_c, true);
    loop
      wait until rising_edge(clock_s);
      exit when is_valid(cfg_c, out_m_s);
    end loop;
    got := frame(cfg_c, out_m_s);
    observed := out_m_s;
    assert number_of(got) = 15
      report "Mixer did not combine the two inputs"
      severity failure;
    assert got(0).sideband(1 downto 0) = "01"
      and is_last(cfg_c, observed)
      and is_block(cfg_c, observed)
      and is_error(cfg_c, observed)
      and observed.id(1 downto 0) = id_c
      and observed.dest(1 downto 0) = dest_c
      and observed.keep(0) = '1'
      report "Mixer did not preserve input A metadata"
      severity failure;

    report "Terminating with error level: 0" severity note;
    done_s <= "1";
    wait;
  end process;

end architecture;
