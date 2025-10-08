library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_hwdep, nsl_synthesis, work;
use nsl_data.text.all;
use nsl_hwdep.gowin_config.all;

entity pll_basic is
  generic(
    input_hz_c  : natural;
    output_hz_c : natural;
    hw_variant_c : string := ""
    );
  port(
    clock_i    : in  std_ulogic;
    clock_o    : out std_ulogic;

    reset_n_i  : in  std_ulogic;
    locked_o   : out std_ulogic
    );
end entity;

architecture gw1n of pll_basic is

  type gowin_pll_params is
  record
    odiv, idiv, fbdiv : integer;
    fin, fpfd, fvco, fout, fout_err : real;
  end record;

  type gowin_pll_constraints is
  record
    vcomin, vcomax : real;
    pfdmin, pfdmax : real;
  end record;

  type int_vector is array (integer range <>) of integer;
  constant odiv_possibilities_c : ivec :=
    pll_odiv_possibilities;
  
  function calc_fout(fin : real;
                          params : gowin_pll_params;
                          constraints : gowin_pll_constraints)
    return real
  is
    variable fout : real;
  begin
    fout := (fin * real(params.fbdiv)) / real(params.idiv);
    return fout;
  end function;

  function params_for(fin, fout: real;
                      idiv, fbdiv, odiv: integer) return gowin_pll_params
  is
    variable params: gowin_pll_params;
  begin
    params.fin := fin;
    params.idiv := idiv;
    params.fbdiv := fbdiv;
    params.odiv := odiv;
    params.fpfd := fin / real(idiv);
    params.fvco := params.fpfd * real(fbdiv);
    params.fout := params.fvco / real(odiv);
    params.fout_err := abs(params.fout - fout);

    return params;
  end function;

  function is_possible(constant params: gowin_pll_params;
                       constant constraints: gowin_pll_constraints) return boolean
  is
  begin
    if params.fpfd < constraints.pfdmin
      or params.fpfd > constraints.pfdmax then
      return false;
    end if;

    if params.fvco > constraints.vcomax
      or params.fvco < constraints.vcomin then
      return false;
    end if;

    return true;
  end function;

  function to_string(constant params: gowin_pll_params) return string
  is
  begin
    return "fin=" & to_string(params.fin) & ", "
      & "idiv=" & to_string(params.idiv) & ", "
      & "fbdiv=" & to_string(params.fbdiv) & ", "
      & "odiv=" & to_string(params.odiv) & ", "
      & "vco=" & to_string(params.fvco / 1.0e6) & "MHz, "
      & "pfd=" & to_string(params.fpfd / 1.0e6) & "MHz, "
      & "fout=" & to_string(params.fout / 1.0e6) & "MHz, "
      & "fout error=" & to_string(params.fout_err / 1.0e6) & "MHz";
  end function;
  
  function gowin_pll_params_generate(fin, fout : integer;
                                     constraints : gowin_pll_constraints)
    return gowin_pll_params
  is
    constant fin_r : real := real(fin);
    constant fout_r : real := real(fout);
    variable best_params, params : gowin_pll_params := (0, 0, 0, 0.0, 0.0, 0.0, 0.0, 100.0e9);
    variable best_found : boolean := false;
  begin
    idivs: for idiv in 64 downto 1
    loop
      if fin_r / real(idiv) < constraints.pfdmin then
        next idivs;
      end if;
      if fin_r / real(idiv) > constraints.pfdmax then
        next idivs;
      end if;
        
      fbdivs: for fbdiv in 2 to 64
      loop
        odivs: for odiv_idx in odiv_possibilities_c'reverse_range
        loop
          params := params_for(fin_r, fout_r, idiv, fbdiv, odiv_possibilities_c(odiv_idx));

          if not is_possible(params, constraints) then
            next odivs;
          end if;

          if params.fout_err > best_params.fout_err then
            next odivs;
          end if;

          if params.fpfd < best_params.fpfd then
            next odivs;
          end if;
          
          best_found := true;
          best_params := params;
        end loop;
      end loop;
    end loop;

    report "Synthesizing gowin PLL, "
      & "fin=" & to_string(real(fin) / 1.0e6) & " MHz, "
      & "fout=" & to_string(real(fout) / 1.0e6) & "MHz"
      severity note;

    assert best_found
      report "Cannot find a matching configuration"
      severity failure;

    report "Best option: "&to_string(best_params)
      severity note;
    
    return best_params;
  end function;
  
  -- Now the settings

  constant gowin_params : string := str_param_extract(hw_variant_c, "gowin");
  constant pll_constraints : gowin_pll_constraints := (
    vcomin => nsl_hwdep.gowin_config.pll_vco_fmin,
    vcomax => nsl_hwdep.gowin_config.pll_vco_fmax,
    pfdmin => nsl_hwdep.gowin_config.pll_pfd_fmin,
    pfdmax => nsl_hwdep.gowin_config.pll_pfd_fmax);

  constant params : gowin_pll_params := gowin_pll_params_generate(input_hz_c,
                                                                  output_hz_c,
                                                                  pll_constraints);

  constant fin_hz_str : string := to_string(input_hz_c);
  constant fin_hz_str2 : string(fin_hz_str'length downto 1) := fin_hz_str;
  constant fin_mhz_str : string := fin_hz_str2(fin_hz_str2'left downto 7) & "." & fin_hz_str2(6 downto 1);
  constant period_out_str : string := to_string(1.0e9 / real(output_hz_c));

  signal reset_s, clkout_s, clockout_buffered_s: std_ulogic;
  
  attribute period: string;  
  attribute period of clockout_buffered_s : signal is period_out_str & " ns";

begin

  has_pll: if input_hz_c /= output_hz_c
  generate
    log0: nsl_synthesis.logging.synth_log
      generic map(
        message_c => "Best option: " & to_string(params)
        )
      port map(
        unused_i => '0'
        );
    
    reset_s <= not reset_n_i;
    clock_o <= clockout_buffered_s;

    buf: work.distribution.clock_buffer
      port map(
        clock_i => clkout_s,
        clock_o => clockout_buffered_s
        );

    use_rpll: if nsl_hwdep.gowin_config.pll_type = "rpll"
    generate
      component rpll is
        generic(
          fclkin : string := "100.0"; --frequency of the clkin(m)
          device : string := "gw1n-2";
          dyn_idiv_sel : string := "false";--true:idsel; false:idiv_sel
          idiv_sel : integer := 0;--input divider idiv, 0:1,1:2...63:64.  1~64
          dyn_fbdiv_sel : string := "false";
          fbdiv_sel : integer := 0;--feedback divider fbdiv,  0:1,1:2...63:64. 1~64
          dyn_odiv_sel : string := "false";--true:odsel; false:odiv_sel
          odiv_sel : integer := 8;--2/4/8/16/32/48/64/80/96/112/128
          psda_sel : string := "0000";--
          dyn_da_en : string := "false";--true:psda or dutyda or fda; false: da_sel
          dutyda_sel : string := "1000";--
          clkout_ft_dir : bit := '1'; -- clkout fine tuning direction. '1' only
          clkoutp_ft_dir : bit := '1'; -- '1' only
          clkout_dly_step : integer := 0; -- 0,1,2,4
          clkoutp_dly_step : integer := 0; -- 0,1,2

          clkoutd3_src : string := "clkout";--select div3 output, clkoutp or clkout
          clkfb_sel : string := "internal"; --"internal", "external"
          clkout_bypass : string := "false";
          clkoutp_bypass : string := "false";
          clkoutd_bypass : string := "false";
          clkoutd_src : string := "clkout";--select div output,  clkoutp or clkout
          dyn_sdiv_sel : integer := 2 -- 2~128,only even num
          );
        port(
          clkin : in std_logic;
          clkfb : in std_logic:='0';
          idsel : in std_logic_vector(5 downto 0);
          fbdsel : in std_logic_vector(5 downto 0);
          odsel : in std_logic_vector(5 downto 0);
          reset : in std_logic:='0';
          reset_p : in std_logic:='0';
          psda,fdly : in std_logic_vector(3 downto 0);
          dutyda : in std_logic_vector(3 downto 0);
          lock : out std_logic;
          clkout : out std_logic;
          clkoutd : out std_logic;
          clkoutp : out std_logic;
          clkoutd3 : out std_logic
          );
      end component rpll;
    begin
      inst: rpll
        generic map(
          fclkin => fin_mhz_str,
          device => nsl_hwdep.gowin_config.device_name,
          idiv_sel => params.idiv - 1,
          fbdiv_sel => params.fbdiv - 1,
          odiv_sel => params.odiv,
          clkfb_sel => "internal",
          clkoutd_src => "CLKOUT",
          dyn_idiv_sel => "false",
          dyn_fbdiv_sel => "false",
          dyn_odiv_sel => "false"
          )
        port map(
          clkin => clock_i,
--        clkfb => clockout_buffered_s,
          idsel => "000000",
          fbdsel => "000000",
          odsel => "000000",
          reset => reset_s,
          reset_p => '0',
          psda => "0000",
          fdly => "0000",
          dutyda => "0000",
          lock => locked_o,
          clkout => clkout_s
          );
    end generate;

    use_pll: if nsl_hwdep.gowin_config.pll_type = "pll"
    generate
      COMPONENT PLL
        GENERIC(
          FCLKIN : STRING := "100.0"; --frequency of the clkin(M)
          DEVICE : STRING := "GW2A-18"; --"GW2A-18","GW2A-55","GW2AR-18","GW2A-55C","GW2A-18C","GW2AR-18C","GW2ANR-18C","GW2AN-55C"
          DYN_IDIV_SEL : STRING := "false"; --true:IDSEL; false:IDIV_SEL
          IDIV_SEL : integer := 0; --Input divider IDIV, 0:1,1:2...63:64.  1~64
          DYN_FBDIV_SEL : STRING := "false";
          FBDIV_SEL : integer := 0; --Feedback divider FBDIV,  0:1,1:2...63:64. 1~64
          DYN_ODIV_SEL : STRING := "false"; --true:ODSEL; false:ODIV_SEL
          ODIV_SEL : integer := 8; --2/4/8/16/32/48/64/80/96/112/128
          PSDA_SEL : STRING := "0000"; --
          DYN_DA_EN : STRING := "false"; --true:PSDA or DUTYDA or FDA; false: DA_SEL
          DUTYDA_SEL : STRING := "1000"; --
          CLKOUT_FT_DIR : bit := '1'; -- CLKOUT fine tuning direction. '1' only
          CLKOUTP_FT_DIR : bit := '1'; -- '1' only
          CLKOUT_DLY_STEP : integer := 0; -- 0,1,2,4
          CLKOUTP_DLY_STEP : integer := 0; -- 0,1,2

          CLKOUTD3_SRC : STRING := "CLKOUT"; --select div3 output, CLKOUTP or CLKOUT
          CLKFB_SEL : STRING := "internal"; --"internal","external"
          CLKOUT_BYPASS : STRING := "false";
          CLKOUTP_BYPASS : STRING := "false";
          CLKOUTD_BYPASS : STRING := "false";
          CLKOUTD_SRC : STRING := "CLKOUT"; --select div output,  CLKOUTP or CLKOUT
          DYN_SDIV_SEL : integer := 2 -- 2~128,only even num
          
          );
        PORT(
          CLKIN : IN std_logic;
          CLKFB : IN std_logic:='0';
          IDSEL : In std_logic_vector(5 downto 0);
          FBDSEL : In std_logic_vector(5 downto 0);
          ODSEL : In std_logic_vector(5 downto 0);
          RESET : in std_logic:='0';
          RESET_P : in std_logic:='0';
          RESET_I :in std_logic:='0';
          RESET_S : in std_logic :='0';
          PSDA,FDLY : In std_logic_vector(3 downto 0);
          DUTYDA : In std_logic_vector(3 downto 0);
          LOCK : OUT std_logic;
          CLKOUT : OUT std_logic;
          CLKOUTD : out std_logic;
          CLKOUTP : out std_logic;
          CLKOUTD3 : out std_logic
          );
      end COMPONENT;
    begin
      inst: pll
        generic map(
          fclkin => fin_mhz_str,
          device => nsl_hwdep.gowin_config.device_name,
          idiv_sel => params.idiv - 1,
          fbdiv_sel => params.fbdiv - 1,
          odiv_sel => params.odiv,
          clkfb_sel => "internal",
          clkoutd_src => "CLKOUT",
          dyn_idiv_sel => "false",
          dyn_fbdiv_sel => "false",
          dyn_odiv_sel => "false"
          )
        port map(
          clkin => clock_i,
--        clkfb => clockout_buffered_s,
          idsel => "000000",
          fbdsel => "000000",
          odsel => "000000",
          reset => reset_s,
          reset_p => '0',
          psda => "0000",
          fdly => "0000",
          dutyda => "0000",
          lock => locked_o,
          clkout => clkout_s
          );
    end generate;

    use_plla: if nsl_hwdep.gowin_config.pll_type = "plla"
    generate
      COMPONENT PLLA
        generic(
          FCLKIN : string := "100.0"; --frequency of the clkin(M)
          IDIV_SEL : integer := 1; --Input divider IDIV, 1~64;
          FBDIV_SEL : integer := 1; --Feedback divider FBDIV, 1~64
          
          ODIV0_SEL : integer := 8; --1~128,integer
          ODIV1_SEL : integer := 8; --1~128,integer
          ODIV2_SEL : integer := 8; --1~128,integer
          ODIV3_SEL : integer := 8; --1~128,integer
          ODIV4_SEL : integer := 8; --1~128,integer
          ODIV5_SEL : integer := 8; --1~128,integer
          ODIV6_SEL : integer := 8; --1~128,integer
          MDIV_SEL : integer := 8; --2~128,integer
          MDIV_FRAC_SEL : integer := 0; --0~7,integer
          ODIV0_FRAC_SEL : integer := 0; --0~7,integer
          
          CLKOUT0_EN : string := "TRUE"; --"TRUE","FALSE"
          CLKOUT1_EN : string := "FALSE"; --"TRUE","FALSE"
          CLKOUT2_EN : string := "FALSE"; --"TRUE","FALSE"
          CLKOUT3_EN : string := "FALSE"; --"TRUE","FALSE"
          CLKOUT4_EN : string := "FALSE"; --"TRUE","FALSE"
          CLKOUT5_EN : string := "FALSE"; --"TRUE","FALSE"
          CLKOUT6_EN : string := "FALSE"; --"TRUE","FALSE"
          
          CLKFB_SEL : string := "INTERNAL"; -- "INTERNAL", "EXTERNAL";
          
          CLKOUT0_DT_DIR : bit := '1'; -- CLKOUT0 dutycycle adjust direction. '1': + ; '0': -
          CLKOUT1_DT_DIR : bit := '1'; -- CLKOUT1 dutycycle adjust direction. '1': + ; '0': -
          CLKOUT2_DT_DIR : bit := '1'; -- CLKOUT2 dutycycle adjust direction. '1': + ; '0': -
          CLKOUT3_DT_DIR : bit := '1'; -- CLKOUT3 dutycycle adjust direction. '1': + ; '0': -
          CLKOUT0_DT_STEP : integer := 0; -- 0,1,2,4; 50ps/step
          CLKOUT1_DT_STEP : integer := 0; -- 0,1,2,4; 50ps/step
          CLKOUT2_DT_STEP : integer := 0; -- 0,1,2,4; 50ps/step
          CLKOUT3_DT_STEP : integer := 0; -- 0,1,2,4; 50ps/step

          --ODIVx input source select. 0:from VCO;1:from CLKIN
          --CLKOUTx output select. 0:DIVx output; 1:CLKIN
          CLK0_IN_SEL  : bit := '0';
          CLK0_OUT_SEL : bit := '0';
          CLK1_IN_SEL  : bit := '0';
          CLK1_OUT_SEL : bit := '0';
          CLK2_IN_SEL  : bit := '0';
          CLK2_OUT_SEL : bit := '0';
          CLK3_IN_SEL  : bit := '0';
          CLK3_OUT_SEL : bit := '0';
          CLK4_IN_SEL  : bit_vector := "00";
          CLK4_OUT_SEL : bit := '0';
          CLK5_IN_SEL  : bit := '0';
          CLK5_OUT_SEL : bit := '0';
          CLK6_IN_SEL  : bit := '0';
          CLK6_OUT_SEL : bit := '0';

          DYN_DPA_EN : string := "FALSE"; --dynamic phaseshift adjustment Enable."TRUE","FALSE"

          CLKOUT0_PE_COARSE : integer := 0; --0~127    
          CLKOUT0_PE_FINE : integer := 0; --0~7
          CLKOUT1_PE_COARSE : integer := 0;  --0~127       
          CLKOUT1_PE_FINE : integer := 0; --0~7
          CLKOUT2_PE_COARSE : integer := 0;  --0~127       
          CLKOUT2_PE_FINE : integer := 0; --0~7
          CLKOUT3_PE_COARSE : integer := 0;  --0~127       
          CLKOUT3_PE_FINE : integer := 0; --0~7
          CLKOUT4_PE_COARSE : integer := 0;  --0~127       
          CLKOUT4_PE_FINE : integer := 0; --0~7
          CLKOUT5_PE_COARSE : integer := 0;  --0~127       
          CLKOUT5_PE_FINE : integer := 0; --0~7
          CLKOUT6_PE_COARSE : integer := 0;  --0~127       
          CLKOUT6_PE_FINE : integer := 0; --0~7

          --"TRUE": select dpa port as the dynamic control signal for
          --ODIV0 phase shift. "FALSE":select CLKOUT0_PE_COARSE &
          --CLKOUT0_PE_FINE as the static control signal for ODIV0
          --phase shift
          DYN_PE0_SEL : string := "FALSE";
          DYN_PE1_SEL : string := "FALSE";
          DYN_PE2_SEL : string := "FALSE";
          DYN_PE3_SEL : string := "FALSE";
          DYN_PE4_SEL : string := "FALSE";
          DYN_PE5_SEL : string := "FALSE";
          DYN_PE6_SEL : string := "FALSE";

          --"FALSE":fixed 50% duty cycle for case odiv0=2~128;
          --"TRUE":select CLKOUT0_PE_COARSE & CLKOUT0_PE_FINE as duty
          --edge when DYN_PE0_SEL="TRUE" for case ODIV0=2~128
          DE0_EN : string := "FALSE";
          DE1_EN : string := "FALSE";
          DE2_EN : string := "FALSE";
          DE3_EN : string := "FALSE";
          DE4_EN : string := "FALSE";
          DE5_EN : string := "FALSE";
          DE6_EN : string := "FALSE";

          RESET_I_EN : string := "FALSE";
          RESET_O_EN : string := "FALSE";

          ICP_SEL : std_logic_vector(5 downto 0) := "XXXXXX";
          LPF_RES : std_logic_vector(2 downto 0) := "XXX";
          LPF_CAP : bit_vector := "00"; --00,C0 ;01,C1; 10,C2

          SSC_EN : string := "FALSE"; --"FALSE","TRUE".ssc mode enable

          VR_EN : bit := '0' --1'b0,regulator off; 1'b1,regulator on
          );
        port(
          CLKIN : in std_logic;
          CLKFB : in std_logic:='0';
          RESET,PLLPWD : in std_logic:='0';
          RESET_I,RESET_O : in std_logic:='0';
          PSSEL : in std_logic_vector(2 downto 0);
          PSDIR,PSPULSE : in std_logic;
          SSCPOL,SSCON : in std_logic;
          SSCMDSEL : in std_logic_vector(6 downto 0);
          SSCMDSEL_FRAC : in std_logic_vector(2 downto 0);
          MDCLK : in std_logic;
          MDOPC : in std_logic_vector(1 downto 0);
          MDAINC : in std_logic;
          MDWDI : in std_logic_vector(7 downto 0);

          MDRDO : out std_logic_vector(7 downto 0);    
          LOCK : out std_logic;
          CLKOUT0,CLKOUT1 : out std_logic;
          CLKOUT2,CLKOUT3 : out std_logic;
          CLKOUT4,CLKOUT5 : out std_logic;
          CLKOUT6,CLKFBOUT : out std_logic
          );
      end COMPONENT;
    begin
      inst: plla
        generic map(
          fclkin => fin_mhz_str,
          idiv_sel => params.idiv,
          fbdiv_sel => 1,
          mdiv_sel => params.fbdiv,
          odiv0_sel => params.odiv,
          clkfb_sel => "INTERNAL"
          )
        port map(
          clkin => clock_i,
          reset => reset_s,
          pssel => "000",
          psdir => '0',
          pspulse => '0',
          sscpol => '0',
          sscon => '0',
          sscmdsel => "0000000",
          sscmdsel_frac => "000",
          mdclk => '0',
          mdopc => "00",
          mdainc => '0',
          mdwdi => x"00",
          lock => locked_o,
          clkout0 => clkout_s
          );
    end generate;
  end generate;

  no_pll: if input_hz_c = output_hz_c
  generate
    log0: nsl_synthesis.logging.synth_log
      generic map(
        message_c => "No PLL generated as both clock have the same rate"
        )
      port map(
        unused_i => '0'
        );

    locked_o <= reset_n_i;
    clock_o <= clock_i;
  end generate;
  
end architecture gw1n;
