library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.text.all;

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

architecture ice40 of pll_basic is

  component SB_PLL40_CORE is
    generic (
      FEEDBACK_PATH : string := "SIMPLE";
      DELAY_ADJUSTMENT_MODE_FEEDBACK : string := "FIXED";
      DELAY_ADJUSTMENT_MODE_RELATIVE : string := "FIXED";
      SHIFTREG_DIV_MODE : bit_vector(1 downto 0) := "00";
      FDA_FEEDBACK : bit_vector(3 downto 0) := "0000";
      FDA_RELATIVE : bit_vector(3 downto 0) := "0000";
      PLLOUT_SELECT : string := "GENCLK";
      DIVF : bit_vector(6 downto 0);
      DIVR : bit_vector(3 downto 0);
      DIVQ : bit_vector(2 downto 0);
      FILTER_RANGE : bit_vector(2 downto 0);
      ENABLE_ICEGATE : bit := '0';
      TEST_MODE : bit := '0';
      EXTERNAL_DIVIDE_FACTOR : integer := 1
      );
    port (
      REFERENCECLK : in std_logic;
      PLLOUTCORE : out std_logic;
      PLLOUTGLOBAL : out std_logic;
      EXTFEEDBACK : in std_logic;
      DYNAMICDELAY : in std_logic_vector (7 downto 0);
      LOCK : out std_logic;
      BYPASS : in std_logic;
      RESETB : in std_logic;
      LATCHINPUTVALUE : in std_logic;
      SDO : out std_logic;
      SDI : in std_logic;
      SCLK : in std_logic
      );
  end component;

  component SB_PLL40_PAD is
    generic (
      FEEDBACK_PATH : string := "SIMPLE";
      DELAY_ADJUSTMENT_MODE_FEEDBACK : string := "FIXED";
      DELAY_ADJUSTMENT_MODE_RELATIVE : string := "FIXED";
      SHIFTREG_DIV_MODE : bit_vector(1 downto 0) := "00";
      FDA_FEEDBACK : bit_vector(3 downto 0) := "0000";
      FDA_RELATIVE : bit_vector(3 downto 0) := "0000";
      PLLOUT_SELECT : string := "GENCLK";
      DIVF : bit_vector(6 downto 0);
      DIVR : bit_vector(3 downto 0);
      DIVQ : bit_vector(2 downto 0);
      FILTER_RANGE : bit_vector(2 downto 0);
      ENABLE_ICEGATE : bit := '0';
      TEST_MODE : bit := '0';
      EXTERNAL_DIVIDE_FACTOR : integer := 1
      );
    port (
      PACKAGEPIN : in std_logic;
      PLLOUTCORE : out std_logic;
      PLLOUTGLOBAL : out std_logic;
      EXTFEEDBACK : in std_logic;
      DYNAMICDELAY : in std_logic_vector (7 downto 0);
      LOCK : out std_logic;
      BYPASS : in std_logic;
      RESETB : in std_logic;
      LATCHINPUTVALUE : in std_logic;
      SDO : out std_logic;
      SDI : in std_logic;
      SCLK : in std_logic
      );
  end component;

  type ice40_pll_params is
  record
    divf, divr, divq, filter_range : integer;
  end record;

  type ice40_pll_constraints is
  record
    vcomin, vcomax : real;
  end record;

  function ice40_out_freq(fin : real;
                          params : ice40_pll_params;
                          constraints : ice40_pll_constraints)
    return real
  is
    variable fd, fvco : real;
  begin
    fd := fin / real(params.divr + 1);
    fvco := fd * real(params.divf + 1);
    if fvco > constraints.vcomax or fvco < constraints.vcomin then
      return 0.0;
    end if;
    return fvco / 2.0 ** params.divq;
  end function;

  function ice40_pll_params_generate(fin, fout : integer;
                                     constraints : ice40_pll_constraints)
    return ice40_pll_params
  is
    constant fin_r : real := real(fin);
    constant fout_r : real := real(fout);
    variable best_params, params : ice40_pll_params := (0, 0, 0, 0);
    variable best_found : boolean := false;
    variable best_fout, fout_calc, fout_err_next, fd : real := 0.0;
    variable fout_err : real := 1.0e9;
  begin
    for divr in 0 to 15
    loop
      for divf in 0 to 128
      loop
        for divq in 0 to 7
        loop
          params.divr := divr;
          params.divf := divf;
          params.divq := divq;
          fout_calc := ice40_out_freq(fin_r, params, constraints);
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

    fd := fin_r / real(best_params.divr + 1);
    if fd < 17.0 then
      best_params.filter_range := 1;
    elsif fd < 26.0 then
      best_params.filter_range := 2;
    elsif fd < 44.0 then
      best_params.filter_range := 3;
    elsif fd < 66.0 then
      best_params.filter_range := 4;
    elsif fd < 101.0 then
      best_params.filter_range := 5;
    else
      best_params.filter_range := 6;
    end if;

    assert false
      report "Synthesizing iCE40 PLL, "
      & "fin=" & to_string(real(fin) / 1.0e6) & " MHz, "
      & "fout=" & to_string(real(fout) / 1.0e6) & "MHz"
      severity note;

    assert best_found
      report "Cannot find a matching configuration"
      severity failure;

    assert false
      report "Best option: divr=" & to_string(best_params.divr+1) & ", "
      & "divf=" & to_string(best_params.divf+1) & ", "
      & "divq=" & to_string(2**best_params.divq) & ", "
      & "filter_range=" & to_string(best_params.filter_range) & ", "
      & "vco=" & to_string(fin_r / real(best_params.divr + 1) * real(best_params.divf + 1) / 1.0e6) & "MHz, "
      & "fout error=" & to_string(real(fout_err) / 1.0e6) & "MHz"
      severity note;
    
    return best_params;
  end function;

  type pll_variant is (
    PLL_CORE,
    PLL_PAD
    );

  function ice40_pll_variant_get(hw_variant : string)
    return pll_variant
  is
  begin
    if strfind(hw_variant, "type=core", ',') then
      return PLL_CORE;
    else
      return PLL_PAD;
    end if;
  end function;

  type pll_output is (
    OUTPUT_CORE,
    OUTPUT_GLOBAL
    );

  function ice40_pll_output_get(hw_variant : string)
    return pll_output
  is
  begin
    if strfind(hw_variant, "out=core", ',') then
      return OUTPUT_CORE;
    else
      return OUTPUT_GLOBAL;
    end if;
  end function;
  
  -- Now the settings

  constant ice40_params : string := str_param_extract(hw_variant_c, "ice40");
  constant pll_constraints : ice40_pll_constraints := (533.0e6, 1066.0e6);
  constant params : ice40_pll_params := ice40_pll_params_generate(input_hz_c,
                                                                  output_hz_c,
                                                                  pll_constraints);
  constant variant : pll_variant := ice40_pll_variant_get(ice40_params);
  constant output : pll_output := ice40_pll_output_get(ice40_params);

  constant divf_c : bit_vector := to_bitvector(std_logic_vector(to_unsigned(params.divf, 7)));
  constant divr_c : bit_vector := to_bitvector(std_logic_vector(to_unsigned(params.divr, 4)));
  constant divq_c : bit_vector := to_bitvector(std_logic_vector(to_unsigned(params.divq, 3)));
  constant filter_range_c : bit_vector := to_bitvector(std_logic_vector(to_unsigned(params.filter_range, 3)));

begin

  inst_core_core: if variant = PLL_CORE and output = OUTPUT_CORE
  generate
    inst: sb_pll40_core
      generic map(
        divf => divf_c,
        divr => divr_c,
        divq => divq_c,
        filter_range => filter_range_c
        )
      port map(
        referenceclk => clock_i,
        plloutcore => clock_o,
        dynamicdelay => "00000000",
        extfeedback => '0',
        lock => locked_o,
        bypass => '0',
        resetb => reset_n_i,
        latchinputvalue => '0',
        sdi => '0',
        sclk => '0'
        );
  end generate;    
  
  inst_core_global: if variant = PLL_CORE and output = OUTPUT_GLOBAL
  generate
    inst: sb_pll40_core
      generic map(
        divf => divf_c,
        divr => divr_c,
        divq => divq_c,
        filter_range => filter_range_c
        )
      port map(
        referenceclk => clock_i,
        plloutglobal => clock_o,
        dynamicdelay => "00000000",
        extfeedback => '0',
        lock => locked_o,
        bypass => '0',
        resetb => reset_n_i,
        latchinputvalue => '0',
        sdi => '0',
        sclk => '0'
        );
  end generate;    

  inst_pad_core: if variant = PLL_PAD and output = OUTPUT_CORE
  generate
    inst: sb_pll40_pad
      generic map(
        divf => divf_c,
        divr => divr_c,
        divq => divq_c,
        filter_range => filter_range_c
        )
      port map(
        packagepin => clock_i,
        plloutcore => clock_o,
        dynamicdelay => "00000000",
        extfeedback => '0',
        lock => locked_o,
        bypass => '0',
        resetb => reset_n_i,
        latchinputvalue => '0',
        sdi => '0',
        sclk => '0'
        );
  end generate;    

  inst_pad_global: if variant = PLL_PAD and output = OUTPUT_GLOBAL
  generate
    inst: sb_pll40_pad
      generic map(
        divf => divf_c,
        divr => divr_c,
        divq => divq_c,
        filter_range => filter_range_c
        )
      port map(
        packagepin => clock_i,
        plloutglobal => clock_o,
        dynamicdelay => "00000000",
        extfeedback => '0',
        lock => locked_o,
        bypass => '0',
        resetb => reset_n_i,
        latchinputvalue => '0',
        sdi => '0',
        sclk => '0'
        );
  end generate;    
  
end architecture;
