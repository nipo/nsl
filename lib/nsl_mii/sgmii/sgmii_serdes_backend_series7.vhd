library ieee;
use ieee.std_logic_1164.all;

library work, nsl_line_coding, nsl_io, nsl_logic, nsl_clocking;
use nsl_line_coding.ibm_8b10b.all;
use nsl_io.diff.all;
use nsl_io.pad.all;
use nsl_io.serdes.all;
use nsl_io.delay.all;
use work.sgmii.all;

library unisim;
use unisim.vcomponents.all;

entity sgmii_serdes_backend_series7 is
  generic (
    refclk_hz_c : positive := 25000000
  );
  port (
    ref_clk_i   : in std_ulogic;
    ref_rst_n_i : in std_ulogic;

    clk125_o : out std_ulogic;
    rst_n_o  : out std_ulogic;

    sgmii_i : in  sgmii_m2p;
    sgmii_o : out sgmii_p2m;

    pair_diff_i : in  nsl_io.diff.diff_pair;
    pair_diff_o : out nsl_io.diff.diff_pair
    );
end entity sgmii_serdes_backend_series7;

architecture beh of sgmii_serdes_backend_series7 is

  -- Internal signals
  signal s_data_m2p_se : std_ulogic;
  signal s_data_p2m_se : std_ulogic;

  signal s_ser2dec_code : nsl_line_coding.ibm_8b10b.code_word_t;
  signal s_enc2ser_code : nsl_line_coding.ibm_8b10b.code_word_t;

  signal s_delay_shift  : std_ulogic;
  signal s_delay_mark   : std_ulogic;
  signal s_slip_shift   : std_ulogic;
  signal s_slip_mark    : std_ulogic;
  signal s_delayed_data : std_ulogic;

  -- MMCM signals
  signal s_general_reset_sync_n  : std_ulogic;
  signal s_delay_clock           : std_ulogic;
  signal s_parallel_clock_buff   : std_ulogic;
  signal s_serial_clock          : std_ulogic;
  signal s_serial_clock_buff     : std_ulogic;
  signal s_domain_a_pll_reset    : std_ulogic;
  signal s_domain_a_pll_locked   : std_ulogic;
  signal s_domain_a_pll_feedback : std_ulogic;
  signal s_everything_ready      : std_ulogic;
  signal s_delay_rst             : std_ulogic;
  signal s_delay_rdy             : std_ulogic;
  signal s_delay_reset_n         : std_ulogic;
  signal s_bufr_rst              : std_ulogic;

  -- MMCM helper functions
  function gcd(a, b : positive) return positive is
    variable x : natural := a;
    variable y : natural := b;
    variable t : natural;
  begin
    while y /= 0 loop
      t := y;
      y := x mod y;
      x := t;
    end loop;
    return x;
  end function gcd;

  function calc_mmcm_vco_hz (
    refclk_hz_c  : positive;
    exact_out_hz : positive;
    vco_min_hz   : positive := 600_000_000;
    vco_max_hz   : positive := 1_200_000_000;
    max_mult_c   : positive := 128
  ) return positive is
    variable v_g        : positive;
    variable v_lcm_real : real;
    variable v_vco_real : real;
  begin
    v_g        := gcd(refclk_hz_c, exact_out_hz);
    v_lcm_real := real(refclk_hz_c / v_g) * real(exact_out_hz);

    for k in 1 to max_mult_c loop
      v_vco_real := v_lcm_real * real(k);

      if v_vco_real >= real(vco_min_hz) and v_vco_real <= real(vco_max_hz) then
        return integer(v_vco_real);
      end if;

      exit when v_vco_real > real(vco_max_hz);
    end loop;

    report "calc_mmcm_vco_hz: no valid VCO found for refclk=" &
           integer'image(refclk_hz_c) & " Hz, exact_out=" &
           integer'image(exact_out_hz) & " Hz within [" &
           integer'image(vco_min_hz) & "," & integer'image(vco_max_hz) & "] Hz."
      severity failure;

    return vco_min_hz;                  -- unreachable
  end function calc_mmcm_vco_hz;

  -- Constants
  constant serial_clock_hz_c     : positive := 625_000_000;
  constant delay_clock_hz_c      : positive := 200_000_000;
  constant domain_a_pll_vco_hz_c : positive := calc_mmcm_vco_hz(refclk_hz_c, serial_clock_hz_c);

begin  -- architecture beh

  -- Component instatiation
  -- MMCM ----------------------------------------------------------------------------------

  s_domain_a_pll_reset <= not ref_rst_n_i;

  domain_a_pll_inst : mmcme2_adv
    generic map (
      divclk_divide    => 1,
      clkin1_period    => 1.0e9 / real(refclk_hz_c),  -- ns
      clkfbout_mult_f  => real(domain_a_pll_vco_hz_c) / real(refclk_hz_c),
      clkout0_divide_f => real(domain_a_pll_vco_hz_c) / real(delay_clock_hz_c),
      clkout1_divide   => domain_a_pll_vco_hz_c / serial_clock_hz_c
      )
    port map (
      rst      => s_domain_a_pll_reset,
      clkin1   => ref_clk_i,
      clkin2   => '0',
      clkinsel => '1',

      clkout0 => s_delay_clock,
      clkout1 => s_serial_clock,
      locked  => s_domain_a_pll_locked,

      daddr => "0000000",
      dclk  => '0',
      den   => '0',
      di    => x"0000",
      dwe   => '0',

      pwrdwn => '0',

      clkfbin  => s_domain_a_pll_feedback,
      clkfbout => s_domain_a_pll_feedback,

      psclk    => '0',
      psen     => '0',
      psincdec => '0'
      );

  s_everything_ready <= s_delay_rdy and s_domain_a_pll_locked;

  general_reset_sync : nsl_clocking.async.async_edge
    port map(
      clock_i => s_parallel_clock_buff,
      data_i  => s_everything_ready,
      data_o  => s_general_reset_sync_n
      );

  delay_reset_sync : nsl_clocking.async.async_edge
    port map(
      clock_i => s_delay_clock,
      data_i  => s_domain_a_pll_locked,
      data_o  => s_delay_reset_n
      );

  clk125_o <= s_parallel_clock_buff;
  rst_n_o  <= s_general_reset_sync_n;

  -- BUFR, BUFIO ----------------------------------------------------------------------

  BUFIO_inst : bufio
    port map (
      O => s_serial_clock_buff, 
      I => s_serial_clock  
      );

  s_bufr_rst <= not(s_domain_a_pll_locked);

  BUFR_inst : bufr
    generic map (
      BUFR_DIVIDE => "5",  
      SIM_DEVICE  => "7SERIES"       
      )
    port map (
      O   => s_parallel_clock_buff,  
      CE  => s_domain_a_pll_locked,  
      CLR => s_bufr_rst,  
      I   => s_serial_clock  
      );

  -- IDELAYCTRL ----------------------------------------------------------------------------
  
  s_delay_rst <= not(s_delay_reset_n);

  -- IDELAYCTRL, needed for the IO bank
  IDELAYCTRL_inst : idelayctrl
    port map (
      RDY    => s_delay_rdy,  
      REFCLK => s_delay_clock,
      RST    => s_delay_rst  
      );      

  -- RX side --------------------------------------------------------------------------------

  ibm_8b10b_decoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
    generic map (
      implementation_c => "logic")
    port map (
      clock_i           => s_parallel_clock_buff,
      reset_n_i         => sgmii_i.sys_reset_n,
      valid_i           => '1',
      data_i            => s_ser2dec_code,
      data_o            => sgmii_o.data_p2m_symbol,
      code_error_o      => sgmii_o.code_err,
      disparity_error_o => sgmii_o.disparity_err
      );

  aligner : nsl_io.delay.input_delay_aligner_slow
    generic map(
      stabilization_delay_c => 8,
      stabilization_cycle_c => 8
      )
    port map(
      clock_i   => s_parallel_clock_buff,
      reset_n_i => sgmii_i.sys_reset_n,

      delay_shift_o  => s_delay_shift,
      delay_mark_i   => s_delay_mark,
      serdes_shift_o => s_slip_shift,
      serdes_mark_i  => s_slip_mark,

      restart_i => sgmii_i.align_rst,
      valid_i   => sgmii_i.valid_symbol,
      ready_o   => sgmii_o.align_ready
      );

  delayer : nsl_io.delay.input_delay_variable
    port map(
      clock_i   => s_parallel_clock_buff,
      reset_n_i => sgmii_i.sys_reset_n,
      mark_o    => s_delay_mark,
      shift_i   => s_delay_shift,
      data_i    => s_data_p2m_se,
      data_o    => s_delayed_data
      );

  serdes_ddr10_input_1 : nsl_io.serdes.serdes_ddr10_input
    generic map (
      left_to_right_c => false)
    port map (
      bit_clock_i  => s_serial_clock_buff,
      word_clock_i => s_parallel_clock_buff,
      reset_n_i    => sgmii_i.sys_reset_n,
      serial_i     => s_delayed_data,
      parallel_o   => s_ser2dec_code,
      bitslip_i    => s_slip_shift,
      mark_o       => s_slip_mark
      );

  pad_diff_input_1 : nsl_io.pad.pad_diff_input
    generic map (
      diff_term => true,
      is_clock  => false,
      invert    => false)
    port map (
      p_diff => pair_diff_i,
      p_se   => s_data_p2m_se
      );

  -- TX side --------------------------------------------------------------------------------

  ibm_8b10b_encoder_1 : nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
    generic map (
      implementation_c => "logic")
    port map (
      clock_i   => s_parallel_clock_buff,
      reset_n_i => sgmii_i.sys_reset_n,
      valid_i   => '1',
      data_i    => sgmii_i.data_m2p_symbol,
      data_o    => s_enc2ser_code
      );

  serdes_ddr10_output_1 : nsl_io.serdes.serdes_ddr10_output
    generic map (
      left_to_right_c => false)
    port map (
      bit_clock_i  => s_serial_clock_buff,
      word_clock_i => s_parallel_clock_buff,
      reset_n_i    => sgmii_i.sys_reset_n,
      parallel_i   => s_enc2ser_code,
      serial_o     => s_data_m2p_se
      );

  pad_diff_output_1 : nsl_io.pad.pad_diff_output
    generic map (
      is_clock => false)
    port map (
      p_se   => s_data_m2p_se,
      p_diff => pair_diff_o
      );

end architecture beh;
