library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_hwdep, gowin;
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
    vcodiv, idiv, fdiv : integer;
  end record;

  type gowin_pll_constraints is
  record
    vcomin, vcomax : real;
  end record;

  type int_vector is array (integer range <>) of integer;
  constant vcodiv_possibilities_c : int_vector(0 to 10) :=
    (2,4,8,16,32,48,64,80,96,112,128);
  
  function gowin_out_freq(fin : real;
                          params : gowin_pll_params;
                          constraints : gowin_pll_constraints)
    return real
  is
    variable fvco : real;
  begin
    fvco := (fin / real(params.idiv + 1)) * real(params.fdiv + 1) * real(params.vcodiv);
    if fvco > constraints.vcomax or fvco < constraints.vcomin then
      return 0.0;
    end if;

    return fvco / real(params.vcodiv);
  end function;

  function gowin_pll_params_generate(fin, fout : integer;
                                     constraints : gowin_pll_constraints)
    return gowin_pll_params
  is
    constant fin_r : real := real(fin);
    constant fout_r : real := real(fout);
    variable best_params, params : gowin_pll_params := (0, 0, 0);
    variable best_found : boolean := false;
    variable best_fout, fout_calc, fout_err_next : real := 0.0;
    variable fout_err : real := 1.0e9;
    variable vcodiv: integer;
  begin
    for idiv in 0 to 63
    loop
      for fdiv in 0 to 63
      loop
        for vcodiv_idx in vcodiv_possibilities_c'range
        loop
          vcodiv := vcodiv_possibilities_c(vcodiv_idx);
          params.idiv := idiv;
          params.fdiv := fdiv;
          params.vcodiv := vcodiv;

          fout_calc := gowin_out_freq(fin_r, params, constraints);

          fout_err_next := abs(fout_calc - fout_r);

          if fout_err_next < fout_err and fout_calc /= 0.0 then
            best_found := true;
            best_params := params;
            fout_err := fout_err_next;
            best_fout := fout_calc;
          end if;
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

    report "Best option: idiv=" & to_string(best_params.idiv+1) & ", "
      & "fdiv=" & to_string(best_params.fdiv+1) & ", "
      & "vcodiv=" & to_string(2**best_params.vcodiv) & ", "
      & "vco=" & to_string(fin_r / real(best_params.idiv + 1) * real(best_params.fdiv + 1) / 1.0e6) & "MHz, "
      & "fout=" & to_string(best_fout / 1.0e6) & "MHz, "
      & "fout error=" & to_string(real(fout_err) / 1.0e6) & "MHz"
      severity note;
    
    return best_params;
  end function;
  
  -- Now the settings

  constant gowin_params : string := str_param_extract(hw_variant_c, "gowin");
  constant pll_constraints : gowin_pll_constraints := (
    vcomin => nsl_hwdep.gowin_config.pll_vco_fmin,
    vcomax => nsl_hwdep.gowin_config.pll_vco_fmax);

  constant params : gowin_pll_params := gowin_pll_params_generate(input_hz_c,
                                                                  output_hz_c,
                                                                  pll_constraints);

  
  constant fin_mhz_str : string := to_string(real(input_hz_c) / 1.0e6);

  signal reset_s, clkout_s, clockout_buffered_s: std_ulogic;
  
begin

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
        idiv_sel => params.idiv,
        fbdiv_sel => params.fdiv,
        odiv_sel => params.vcodiv,
        clkfb_sel => "external",
        clkoutd_src => "clkout"
        )
      port map(
        clkin => clock_i,
        clkfb => clockout_buffered_s,
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
