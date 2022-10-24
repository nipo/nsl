library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_hwdep, gowin, nsl_synthesis;
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

--  component rpll is
--    generic(
--      fclkin : string := "100.0"; --frequency of the clkin(m)
--      device : string := "gw1n-2";
--      dyn_idiv_sel : string := "false";--true:idsel; false:idiv_sel
--      idiv_sel : integer := 0;--input divider idiv, 0:1,1:2...63:64.  1~64
--      dyn_fbdiv_sel : string := "false";
--      fbdiv_sel : integer := 0;--feedback divider fbdiv,  0:1,1:2...63:64. 1~64
--      dyn_odiv_sel : string := "false";--true:odsel; false:odiv_sel
--      odiv_sel : integer := 8;--2/4/8/16/32/48/64/80/96/112/128
--      psda_sel : string := "0000";--
--      dyn_da_en : string := "false";--true:psda or dutyda or fda; false: da_sel
--      dutyda_sel : string := "1000";--
--      clkout_ft_dir : bit := '1'; -- clkout fine tuning direction. '1' only
--      clkoutp_ft_dir : bit := '1'; -- '1' only
--      clkout_dly_step : integer := 0; -- 0,1,2,4
--      clkoutp_dly_step : integer := 0; -- 0,1,2
--
--      clkoutd3_src : string := "clkout";--select div3 output, clkoutp or clkout
--      clkfb_sel : string := "internal"; --"internal", "external"
--      clkout_bypass : string := "false";
--      clkoutp_bypass : string := "false";
--      clkoutd_bypass : string := "false";
--      clkoutd_src : string := "clkout";--select div output,  clkoutp or clkout
--      dyn_sdiv_sel : integer := 2 -- 2~128,only even num
--      );
--    port(
--      clkin : in std_logic;
--      clkfb : in std_logic:='0';
--      idsel : in std_logic_vector(5 downto 0);
--      fbdsel : in std_logic_vector(5 downto 0);
--      odsel : in std_logic_vector(5 downto 0);
--      reset : in std_logic:='0';
--      reset_p : in std_logic:='0';
--      psda,fdly : in std_logic_vector(3 downto 0);
--      dutyda : in std_logic_vector(3 downto 0);
--      lock : out std_logic;
--      clkout : out std_logic;
--      clkoutd : out std_logic;
--      clkoutp : out std_logic;
--      clkoutd3 : out std_logic
--      );
--  end component rpll;
--
--  COMPONENT BUFG
--    PORT(
--      O:OUT std_logic;
--      I:IN std_logic
--      );
--  END COMPONENT;

  type gowin_pll_params is
  record
    odiv, idiv, fbdiv : integer;
  end record;

  type gowin_pll_constraints is
  record
    vcomin, vcomax : real;
    pfdmin, pfdmax : real;
  end record;

  type int_vector is array (integer range <>) of integer;
  constant odiv_possibilities_c : int_vector(0 to 10) :=
    (2,4,8,16,32,48,64,80,96,112,128);
  
  function calc_fclkout(fin : real;
                          params : gowin_pll_params;
                          constraints : gowin_pll_constraints)
    return real
  is
    variable fclkout : real;
  begin
    fclkout := (fin * real(params.fbdiv)) / real(params.idiv);
    return fclkout;
  end function;

  function gowin_pll_params_generate(fin, fout : integer;
                                     constraints : gowin_pll_constraints)
    return gowin_pll_params
  is
    constant fin_r : real := real(fin);
    constant fout_r : real := real(fout);
    variable best_params, params : gowin_pll_params := (0, 0, 0);
    variable best_found : boolean := false;
    variable best_fclkout, fclkout_calc, fclkout_err_next : real := 0.0;
    variable best_fvco, fvco_calc, pfd_freq : real := 0.0;
    variable fclkout_err : real := 1.0e9;
  begin
    for idiv in 64 downto 1
    loop
      for fbdiv in 1 to 64
      loop
        for odiv_idx in odiv_possibilities_c'reverse_range
        loop
          params.idiv := idiv;
          params.fbdiv := fbdiv;
          params.odiv := odiv_possibilities_c(odiv_idx);

          pfd_freq := fin_r / real(params.idiv);
          if pfd_freq < constraints.pfdmin or pfd_freq > constraints.pfdmax then
            next;
          end if;

          fclkout_calc := (fin_r * real(params.fbdiv)) / real(params.idiv);
          fvco_calc := fclkout_calc * real(params.odiv);
          if fvco_calc > constraints.vcomax or fvco_calc < constraints.vcomin then
            next;
          end if;

          fclkout_err_next := abs(fclkout_calc - fout_r);
          if fclkout_err_next > fclkout_err then
            next;
          end if;
            
          if fvco_calc < best_fvco and fclkout_err = 0.0 then
            next;
          end if;
          
          best_found := true;
          best_params := params;
          fclkout_err := fclkout_err_next;
          best_fclkout := fclkout_calc;
          best_fvco := fvco_calc;
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

    report "Best option: idiv=" & to_string(best_params.idiv) & ", "
      & "fbdiv=" & to_string(best_params.fbdiv) & ", "
      & "odiv=" & to_string(best_params.odiv) & ", "
      & "vco=" & to_string(best_fvco / 1.0e6) & "MHz, "
      & "pfd=" & to_string(fin_r / real(best_params.idiv) / 1.0e6) & "MHz, "
      & "fclkout=" & to_string(best_fclkout / 1.0e6) & "MHz, "
      & "fclkout error=" & to_string(fclkout_err / 1.0e6) & "MHz"
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

  constant synth_report_c : string
    := "Best option: idiv=" & to_string(params.idiv) & ", "
      & "fbdiv=" & to_string(params.fbdiv) & ", "
      & "odiv=" & to_string(params.odiv) & ", "
      & "vco=" & to_string(real(input_hz_c) * real(params.fbdiv) * real(params.odiv) / real(params.idiv) / 1.0e6) & "MHz, "
      & "pfd=" & to_string(real(input_hz_c) / real(params.idiv) / 1.0e6) & "MHz, "
      & "fclkout=" & to_string(real(input_hz_c) * real(params.fbdiv) / real(params.idiv) / 1.0e6) & "MHz";
  
  constant fin_mhz_str : string := to_string(real(input_hz_c) / 1.0e6);

  signal reset_s, clkout_s, clockout_buffered_s: std_ulogic;
  
begin

  log0: nsl_synthesis.logging.synth_log
    generic map(
      message_c => synth_report_c
      )
    port map(
      unused_i => '0'
      );
  
  reset_s <= not reset_n_i;
  clock_o <= clockout_buffered_s;

  buf: gowin.components.bufg
    port map(
      i => clkout_s,
      o => clockout_buffered_s
      );

  use_rpll: if nsl_hwdep.gowin_config.pll_type = "rpll"
  generate
    inst: gowin.components.rpll
      generic map(
        fclkin => fin_mhz_str,
        device => nsl_hwdep.gowin_config.device_name,
        idiv_sel => params.idiv - 1,
        fbdiv_sel => params.fbdiv - 1,
        odiv_sel => params.odiv,
        clkfb_sel => "internal",
        clkoutd_src => "clkout",
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

end architecture gw1n;
