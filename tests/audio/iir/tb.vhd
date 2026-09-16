library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_audio, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;

entity tb is
end entity;

architecture arch of tb is

  constant stage_count_c: natural := 2;
  constant coefficient_width_c: natural := 12;
  constant coefficient_fraction_bits_c: natural := 8;
  constant coefficient_count_c: natural
    := stage_count_c * nsl_audio.iir.biquad_coefficient_count_c;

  constant cfg_c: config_t := config(
    channels => 2,
    sample_bits => 8,
    sideband_bits => 2,
    frames_per_packet => 4,
    id => 2,
    dest => 2,
    keep => true,
    ready => true);

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);
  signal in_m_s, out_m_s: nsl_amba.axi4_stream.master_t;
  signal in_s_s, out_s_s: nsl_amba.axi4_stream.slave_t;
  signal coefficients_s: std_ulogic_vector(
    coefficient_count_c * coefficient_width_c - 1 downto 0);
  signal flush_s: std_ulogic;

  function sample_of(value: integer) return sample_t
  is
  begin
    return to_sample(unsigned(to_signed(value, 8)), CODING_SIGNED);
  end function;

  function frame_of(left, right: integer;
                    left_sideband, right_sideband: std_ulogic_vector(1 downto 0))
    return frame_t
  is
    variable ret: frame_t := frame_zero_c;
  begin
    ret(0).sample := sample_of(left);
    ret(1).sample := sample_of(right);
    ret(0).sideband(1 downto 0) := left_sideband;
    ret(1).sideband(1 downto 0) := right_sideband;
    return ret;
  end function;

  function coefficient_bank(b0, b1, b2, a1, a2: integer)
    return std_ulogic_vector
  is
    type integer_vector_t is array(0 to 4) of integer;
    constant values_c: integer_vector_t := (b0, b1, b2, a1, a2);
    variable ret: std_ulogic_vector(
      coefficient_count_c * coefficient_width_c - 1 downto 0)
      := (others => '0');
    variable low_v: natural;
  begin
    for stage in 0 to stage_count_c-1
    loop
      for coefficient in 0 to 4
      loop
        low_v := (stage * 5 + coefficient) * coefficient_width_c;
        ret(low_v + coefficient_width_c - 1 downto low_v)
          := std_ulogic_vector(to_signed(values_c(coefficient),
                                           coefficient_width_c));
      end loop;
    end loop;
    return ret;
  end function;

begin

  driver: nsl_simulation.driver.simulation_driver
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

  dut: nsl_audio.iir.pcm_iir_cascade
    generic map(
      config_c => cfg_c,
      stage_count_c => stage_count_c,
      coefficient_width_c => coefficient_width_c,
      coefficient_fraction_bits_c => coefficient_fraction_bits_c,
      guard_bits_c => 4)
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      in_i => in_m_s,
      in_o => in_s_s,
      out_o => out_m_s,
      out_i => out_s_s,
      coefficients_i => coefficients_s,
      flush_i => flush_s);

  main: process is
    variable sent_v, observed_v: nsl_amba.axi4_stream.master_t;
    variable got_v: frame_t;

    procedure flush is
    begin
      wait until falling_edge(clock_s);
      flush_s <= '1';
      wait until rising_edge(clock_s);
      wait until falling_edge(clock_s);
      flush_s <= '0';
    end procedure;

    procedure send_frame(constant beat: nsl_amba.axi4_stream.master_t) is
    begin
      wait until falling_edge(clock_s);
      in_m_s <= beat;
      loop
        wait until rising_edge(clock_s);
        exit when is_ready(cfg_c, in_s_s);
      end loop;
      wait until falling_edge(clock_s);
      in_m_s <= transfer_defaults(cfg_c);
    end procedure;

    procedure receive_frame(variable beat: out nsl_amba.axi4_stream.master_t) is
    begin
      wait until falling_edge(clock_s);
      out_s_s <= accept(cfg_c, true);
      loop
        wait until rising_edge(clock_s);
        if is_valid(cfg_c, out_m_s) then
          beat := out_m_s;
          exit;
        end if;
      end loop;
      wait until falling_edge(clock_s);
      out_s_s <= accept(cfg_c, false);
    end procedure;

    procedure transact(constant left, right: integer;
                       variable beat: out nsl_amba.axi4_stream.master_t) is
      variable request_v: nsl_amba.axi4_stream.master_t;
    begin
      request_v := transfer(cfg_c, frame_of(left, right, "00", "00"));
      send_frame(request_v);
      receive_frame(beat);
    end procedure;

    procedure check_samples(constant beat: nsl_amba.axi4_stream.master_t;
                            constant left, right: integer) is
      variable decoded_v: frame_t;
    begin
      decoded_v := frame(cfg_c, beat);
      assert to_integer(signed(decoded_v(0).sample(7 downto 0))) = left
        and to_integer(signed(decoded_v(1).sample(7 downto 0))) = right
        report "Unexpected filtered samples"
        severity failure;
    end procedure;
  begin
    in_m_s <= transfer_defaults(cfg_c);
    out_s_s <= accept(cfg_c, false);
    coefficients_s <= coefficient_bank(256, 0, 0, 0, 0);
    flush_s <= '0';
    done_s <= "0";

    wait until reset_n_s = '1';

    sent_v := transfer(
      cfg => cfg_c,
      frame => frame_of(37, -52, "01", "10"),
      keep => false,
      id => "10",
      dest => "01",
      last => true,
      block_start => true,
      error => true);
    sent_v.strobe(0 to frame_bytes(cfg_c)-1) := "10";
    send_frame(sent_v);
    receive_frame(observed_v);
    got_v := frame(cfg_c, observed_v);
    check_samples(observed_v, 37, -52);
    assert got_v(0).sideband(1 downto 0) = "01"
      and got_v(1).sideband(1 downto 0) = "10"
      and observed_v.user = sent_v.user
      and observed_v.id = sent_v.id
      and observed_v.dest = sent_v.dest
      and observed_v.keep = sent_v.keep
      and observed_v.strobe = sent_v.strobe
      and observed_v.last = sent_v.last
      report "AXI4-Stream metadata was not preserved"
      severity failure;

    -- Two cascaded one-pole sections, each y[n] = x[n]/2 + y[n-1]/2.
    coefficients_s <= coefficient_bank(128, 0, 0, -128, 0);
    flush;
    transact(40, -40, observed_v);
    check_samples(observed_v, 10, -10);
    transact(0, 0, observed_v);
    check_samples(observed_v, 10, -10);
    transact(0, 0, observed_v);
    check_samples(observed_v, 7, -8);

    -- A coherent section snapshot makes a live update deterministic.  The
    -- identity coefficients do not consume the retained IIR histories.
    coefficients_s <= coefficient_bank(256, 0, 0, 0, 0);
    transact(7, -9, observed_v);
    check_samples(observed_v, 7, -9);

    -- Returning to the IIR after a flush must not expose its old histories.
    coefficients_s <= coefficient_bank(128, 0, 0, -128, 0);
    flush;
    transact(40, -40, observed_v);
    check_samples(observed_v, 10, -10);

    report "Terminating with error level: 0" severity note;
    done_s <= "1";
    wait;
  end process;

end architecture;
