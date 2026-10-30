library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_transceiver, nsl_math, nsl_data;
use nsl_transceiver.target.all;
use nsl_transceiver.lane.all;
use nsl_math.int_ext.all;
use nsl_data.text.all;

package transceiver_config_gthe4 is

  -- Types ------------------------------------------------------------
  -- CPLL multiplier divider types
  -- Refer to UG576 Table 2-9
  subtype M_t is natural range 1 to 2;
  subtype N2_t is natural range 1 to 5;
  subtype N1_t is natural range 4 to 5;
  subtype D_t is natural range 1 to 8;

  type pll_mult_div_t is
  record
    M  : M_t;
    N2 : N2_t;
    N1 : N1_t;
    D  : D_t;
  end record;

  -- GTHE4 data width type
  -- Internal width is internal to the GTHE4_CHANNEL primitive
  -- Interface is fabric-side width
  type data_width_t is
  record
    internal_width  : natural;
    interface_width : natural;
    int_data_width  : natural;
  end record;

  -- Loopback configuration, two bit vector
  subtype loopback_config_t is std_logic_vector(2 downto 0);

  -- Functions ---------------------------------------------------------
  -- Reference clock vector builder
  -- Assigns clock ID's to correct signals  
  function build_refclk_vec(ids  : integer_vector;
                            clks : std_ulogic_vector)
    return std_ulogic_vector;

  -- Select CPLL refclk, see Table 2-7 UG576
  function cpll_refclk_set (ids : integer_vector)
    return std_logic_vector;  

  -- PLL multiplier and divider calculator
  function pll_mult_div_assign (line_rate_mhz : natural;
                                pll_vco_mhz   : natural;
                                ref_clk_mhz   : natural)
    return pll_mult_div_t;

  -- Loopback configuration function, see Table 2-36 UG576  
  function loopback_configure (config : nsl_transceiver.lane.loopback_mode_t)
    return std_logic_vector;

  -- Data width calculation, see Table 3-1 UG576  
  function determine_data_width (byte_count : natural)
    return data_width_t;


  -- TX_PROGDIV_CFG calculator. The PROGDIV output (TXOUTCLKSEL = "101") must
  -- run at twice the GT interface clock, since the interface BUFG_GT divides
  -- by 2. Checks the result against the legal PROGDIV values, see UG576
  function prog_div_assign (pll_config : pll_mult_div_t;
                            data_width : data_width_t)
    return real;

  -- BUFG_GT DIV value (divider - 1) for the user-side clock.
  -- ratio = interface width / user width (real), divider = 2 / ratio, 1 to 8
  function bufg_gt_div_assign (ratio : real)
    return std_logic_vector;

end package;

package body transceiver_config_gthe4 is

  function build_refclk_vec(ids  : integer_vector;
                            clks : std_ulogic_vector)
    return std_ulogic_vector
  is
    variable v : std_ulogic_vector(0 to 6) := (others => '0');
  begin
    for i in ids'range loop
      v(ids(i)) := clks(i);
    end loop;
    return v;
  end function;

  function cpll_refclk_set(ids : integer_vector)
    return std_logic_vector
  is
    variable v : std_logic_vector(2 downto 0) := (others => '0');
  begin
    for i in ids'range loop
      if ids(i) /= 6 then -- not stableclk
        v := std_logic_vector(to_unsigned(ids(i) + 1, 3));
      end if;
    end loop;
    return v;
  end function;

  function pll_mult_div_assign (line_rate_mhz : natural;
                                pll_vco_mhz   : natural;
                                ref_clk_mhz   : natural)
    return pll_mult_div_t
  is
    variable d          : real;
    variable ratio      : real;
    variable pll_config : pll_mult_div_t;
  begin  -- function pll_mult_div_assign
    -- Check valid PLL VCO frequency
    assert (pll_vco_mhz >= 2000 and pll_vco_mhz <= 6250)
      report "transceiver_cluster/gthe2: Invalid PLL VCO frequency: CPLL in GTH transceivers accept a range of 2.0GHz to 6.25GHz"
      severity failure;

    -- Calculate D
    d := (real(pll_vco_mhz) * 2.0) / real(line_rate_mhz);
    assert d = 1.0 or d = 2.0 or d = 4.0 or d = 8.0
      report "transceiver_cluster/gthe2: Invalid PLL VCO to line rate ratio, valid ratios are 1, 2, 4, or 8"
      severity failure;
    pll_config.D := natural(d);

    -- Calculate PLL to Ref ratio and check valid value
    ratio := real(pll_vco_mhz) / real(ref_clk_mhz);
    assert ratio = 2.0 or ratio = 2.5 or ratio = 4.0 or ratio = 5.0 or ratio = 6.0 or ratio = 7.5 or
      ratio = 8.0 or ratio = 10.0 or ratio = 12.0 or ratio = 12.5 or ratio = 15.0 or ratio = 16.0 or
      ratio = 20.0 or ratio = 25.0
      report "transceiver_cluster/gthe2: Invalid PLL VCO to reference clock ratio, valid ratios are 2, 2.5, 4, 5, 6, 7.5, 8, 10, 12, 12.5, 15, 16, 20, or 25"
      severity failure;

    -- Assign M, N2, and N1
    if ratio = 2.0 then
      pll_config.M  := 2;
      pll_config.N2 := 1;
      pll_config.N1 := 4;

    elsif ratio = 2.5 then
      pll_config.M  := 2;
      pll_config.N2 := 1;
      pll_config.N1 := 5;

    elsif ratio = 4.0 then
      pll_config.M  := 1;
      pll_config.N2 := 1;
      pll_config.N1 := 4;

    elsif ratio = 5.0 then
      pll_config.M  := 1;
      pll_config.N2 := 1;
      pll_config.N1 := 5;

    elsif ratio = 6.0 then
      pll_config.M  := 2;
      pll_config.N2 := 3;
      pll_config.N1 := 4;

    elsif ratio = 7.5 then
      pll_config.M  := 2;
      pll_config.N2 := 3;
      pll_config.N1 := 5;

    elsif ratio = 8.0 then
      pll_config.M  := 1;
      pll_config.N2 := 2;
      pll_config.N1 := 4;

    elsif ratio = 10.0 then
      pll_config.M  := 1;
      pll_config.N2 := 2;
      pll_config.N1 := 5;

    elsif ratio = 12.0 then
      pll_config.M  := 1;
      pll_config.N2 := 3;
      pll_config.N1 := 4;

    elsif ratio = 12.5 then
      pll_config.M  := 2;
      pll_config.N2 := 5;
      pll_config.N1 := 5;

    elsif ratio = 15.0 then
      pll_config.M  := 1;
      pll_config.N2 := 3;
      pll_config.N1 := 5;

    elsif ratio = 16.0 then
      pll_config.M  := 1;
      pll_config.N2 := 4;
      pll_config.N1 := 4;

    elsif ratio = 20.0 then
      pll_config.M  := 1;
      pll_config.N2 := 5;
      pll_config.N1 := 4;

    elsif ratio = 25.0 then
      pll_config.M  := 1;
      pll_config.N2 := 5;
      pll_config.N1 := 5;

    end if;

    return pll_config;
  end function;

  function loopback_configure (config : nsl_transceiver.lane.loopback_mode_t)
    return std_logic_vector
  is
    variable return_val : std_logic_vector(2 downto 0) := (others => '0');
  begin
    case config is
      when nsl_transceiver.lane.LOOPBACK_NONE         => return_val := "000";
      when nsl_transceiver.lane.LOOPBACK_NEAR_END_PMA => return_val := "010";
      when nsl_transceiver.lane.LOOPBACK_NEAR_END_PCS => return_val := "001";
      when nsl_transceiver.lane.LOOPBACK_FAR_END_PMA  => return_val := "100";
      when nsl_transceiver.lane.LOOPBACK_FAR_END_PCS  => return_val := "110";
    end case;
    return return_val;
  end function;

  function determine_data_width (byte_count : natural)
    return data_width_t
  is
    variable return_val : data_width_t;
  begin
    if byte_count <= 2 then
      return_val.internal_width  := 20;
      return_val.interface_width := 16;
      return_val.int_data_width  := 0;
    elsif byte_count <= 4 then
      return_val.internal_width  := 40;
      return_val.interface_width := 32;
      return_val.int_data_width  := 1;
    elsif byte_count <= 8 then
      return_val.internal_width  := 80;
      return_val.interface_width := 64;
      return_val.int_data_width  := 1;      
    end if;
    return return_val;
  end function;

  function prog_div_assign (pll_config : pll_mult_div_t;
                            data_width : data_width_t)
    return real
  is
    -- 5 * D * (internal_width / 20): 5D for 16/20, 10D for 32/40, 20D for 64/80
    constant prog_div_c : real := real(5 * pll_config.D * data_width.internal_width) / 20.0;
    type real_array_t is array (natural range <>) of real;
    constant valid_c    : real_array_t := (4.0, 5.0, 10.0, 16.0, 16.5, 20.0, 32.0, 33.0, 40.0, 64.0, 66.0, 80.0, 100.0);
    variable found      : boolean := false;
  begin
    for i in valid_c'range loop
      if abs(prog_div_c - valid_c(i)) < 0.001 then
        found := true;
      end if;
    end loop;

    assert found
      report "transceiver_cluster/gthe4: Invalid PROGDIV value " & real'image(prog_div_c)
             & ", valid values are 4, 5, 10, 16, 16.5, 20, 32, 33, 40, 64, 66, 80, or 100"
      severity failure;

    return prog_div_c;
  end function;

  function bufg_gt_div_assign (ratio : real)
    return std_logic_vector
  is
    constant div_c : real := 2.0 / ratio;
    variable div_i : integer;
  begin
    div_i := integer(div_c);

    assert abs(div_c - real(div_i)) < 0.001 and div_i >= 1 and div_i <= 8
      report "transceiver_cluster/gthe4: Interface to user width ratio " & real'image(ratio)
             & " requires BUFG_GT divider " & real'image(div_c) & ", must be an integer from 1 to 8"
      severity failure;

    -- BUFG_GT DIV encodes divider - 1
    return std_logic_vector(to_unsigned(div_i - 1, 3));
  end function;

end package body;
