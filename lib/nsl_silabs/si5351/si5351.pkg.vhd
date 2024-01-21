library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_data, nsl_math, nsl_logic, nsl_bnoc;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_bnoc.framed_transactor.all;

-- This package defines constants and functions suitable to initialize
-- a SI5351 PLL using
-- nsl_bnoc.framed_transactor.framed_transactor_once piped to a
-- nsl_i2c.transactor.transactor_framed_controller.
--
-- This package also defines a configuration switcher that is able to
-- update PLL output port configuration among a pre-defined set (in
-- terms of generics).
--
-- This avoids having a soft-core in a design just to do PLL
-- management.
package si5351 is

  type pll_src_t is (PLL_SRC_XTAL, PLL_SRC_CLKIN);
  type ms_src_t is (MS_SRC_PLLA, MS_SRC_PLLB);
  type drv_src_t is (DRV_SRC_XTAL, DRV_SRC_CLKIN, DRV_SRC_MSREF, DRV_SRC_MS);
  type drv_strength_t is (DRV_2MA, DRV_4MA, DRV_6MA, DRV_8MA);
  type output_enable_t is (OUT_LOW, OUT_HIGH, OUT_HIGHZ, OUT_ON);

  type config_t is
  record
    enabled: boolean;
    integer_only: boolean;
    pll: ms_src_t;
    inverted: boolean;
    strength: drv_strength_t;
    source: drv_src_t;
    ratio: real;
    denom: integer;
  end record;

  type config_vector is array(natural range <>) of config_t;
  
  -- SI5351 dynamic configuration module
  --
  -- Takes a configuration ID for each multisynth and allows to apply
  -- given configuration when configuration index changes.
  --
  -- Use routed_transactor_once for initialization of other registers
  component si5351_config_switcher is
    generic(
      i2c_addr_c: unsigned(6 downto 0) := "1100000";
      config_c: config_vector
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      -- Forces refresh
      force_i : in std_ulogic := '0';
      busy_o  : out std_ulogic;

      ms0_i : natural range 0 to config_c'length-1;
      ms1_i : natural range 0 to config_c'length-1;
      ms2_i : natural range 0 to config_c'length-1;
      ms3_i : natural range 0 to config_c'length-1;
      ms4_i : natural range 0 to config_c'length-1;
      ms5_i : natural range 0 to config_c'length-1;
      ms6_i : natural range 0 to config_c'length-1;
      ms7_i : natural range 0 to config_c'length-1;

      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;
  
  function si5351_addr_set(
    saddr: unsigned(6 downto 0);
    lsb: integer range 0 to 15)
    return byte_string;

  function si5351_source_set(
    saddr: unsigned(6 downto 0);
    clkin_div_l2: integer range 0 to 3;
    plla, pllb: pll_src_t)
    return byte_string;

  function si5351_clock_ctrl_set(
    saddr: unsigned(6 downto 0);
    channel: integer range 0 to 7;
    enabled: boolean := true;
    integer_only: boolean := true;
    pll: ms_src_t := MS_SRC_PLLA;
    inverted: boolean := false;
    source: drv_src_t := DRV_SRC_MS;
    strength: drv_strength_t := DRV_2MA)
    return byte_string;

  function si5351_output_enable_set(
    saddr: unsigned(6 downto 0);
    ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7: boolean := true)
    return byte_string;

  function si5351_output_enable_mask_set(
    saddr: unsigned(6 downto 0);
    ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7: boolean := true)
    return byte_string;

  function si5351_clock_enable_set(
    saddr: unsigned(6 downto 0);
    ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7: output_enable_t := OUT_ON)
    return byte_string;

  function si5351_msn_set(
    saddr: unsigned(6 downto 0);
    pll: ms_src_t;
    ratio: real;
    denom: integer := 1)
    return byte_string;

  function si5351_ms05_set(
    saddr: unsigned(6 downto 0);
    channel: integer range 0 to 5;
    ratio: real;
    denom: integer := 1)
    return byte_string;

  function si5351_ms67_set(
    saddr: unsigned(6 downto 0);
    channel: integer range 6 to 7;
    ratio: integer)
    return byte_string;

  function si5351_ms67_div_set(
    saddr: unsigned(6 downto 0);
    r6_l2, r7_l2: integer range 0 to 7)
    return byte_string;

  function si5351_ss_none_set(
    saddr: unsigned(6 downto 0))
    return byte_string;

  function si5351_reset(
    saddr: unsigned(6 downto 0);
    plla, pllb: boolean := true)
    return byte_string;

end package si5351;

package body si5351 is
  
  function si5351_be_set(
    saddr: unsigned(6 downto 0);
    reg: integer range 0 to 255;
    value: unsigned)
    return byte_string
  is
  begin
    return i2c_write(saddr, to_byte(reg) & to_be(value));
  end function;

  function si5351_addr_set(
    saddr: unsigned(6 downto 0);
    lsb: integer range 0 to 15)
    return byte_string
  is
    constant addr_lsb: unsigned(3 downto 0) := to_unsigned(lsb, 4);
  begin
    return si5351_be_set(saddr, 7, addr_lsb & "0001");
  end function;

  function si5351_source_set(
    saddr: unsigned(6 downto 0);
    clkin_div_l2: integer range 0 to 3;
    plla, pllb: pll_src_t)
    return byte_string
  is
    constant div: unsigned(1 downto 0) := to_unsigned(clkin_div_l2, 2);
    constant pllb_src: std_ulogic := to_logic(pllb = PLL_SRC_CLKIN);
    constant plla_src: std_ulogic := to_logic(plla = PLL_SRC_CLKIN);
  begin
    return si5351_be_set(saddr, 15, div & "00" & pllb_src & plla_src & "00");
  end function;

  function si5351_clock_ctrl_set(
    saddr: unsigned(6 downto 0);
    channel: integer range 0 to 7;
    enabled: boolean := true;
    integer_only: boolean := true;
    pll: ms_src_t := MS_SRC_PLLA;
    inverted: boolean := false;
    source: drv_src_t := DRV_SRC_MS;
    strength: drv_strength_t := DRV_2MA)
    return byte_string
  is
    constant pdn: std_ulogic := to_logic(not enabled);
    constant int: std_ulogic := to_logic(integer_only);
    constant src: std_ulogic := to_logic(pll = MS_SRC_PLLB);
    constant inv: std_ulogic := to_logic(inverted);
    constant src10: unsigned(1 downto 0) := to_unsigned(drv_src_t'pos(source), 2);
    constant idrv10: unsigned(1 downto 0) := to_unsigned(drv_strength_t'pos(strength), 2);
    
  begin
    return si5351_be_set(saddr, 16 + channel,
                         pdn & int & src & inv & src10 & idrv10);
  end function;

  function si5351_output_enable_set(
    saddr: unsigned(6 downto 0);
    ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7: boolean := true)
    return byte_string
  is
  begin
    return si5351_be_set(saddr, 3,
                         to_logic(not ch7)
                         & to_logic(not ch6)
                         & to_logic(not ch5)
                         & to_logic(not ch4)
                         & to_logic(not ch3)
                         & to_logic(not ch2)
                         & to_logic(not ch1)
                         & to_logic(not ch0));
  end function;

  function si5351_output_enable_mask_set(
    saddr: unsigned(6 downto 0);
    ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7: boolean := true)
    return byte_string
  is
  begin
    return si5351_be_set(saddr, 9,
                         to_logic(not ch7)
                         & to_logic(not ch6)
                         & to_logic(not ch5)
                         & to_logic(not ch4)
                         & to_logic(not ch3)
                         & to_logic(not ch2)
                         & to_logic(not ch1)
                         & to_logic(not ch0));
  end function;

  function si5351_clock_enable_set(
    saddr: unsigned(6 downto 0);
    ch0, ch1, ch2, ch3, ch4, ch5, ch6, ch7: output_enable_t := OUT_ON)
    return byte_string
  is
  begin
    return si5351_be_set(saddr, 24,
                         to_unsigned(output_enable_t'pos(ch3), 2)
                         & to_unsigned(output_enable_t'pos(ch2), 2)
                         & to_unsigned(output_enable_t'pos(ch1), 2)
                         & to_unsigned(output_enable_t'pos(ch0), 2)
                         & to_unsigned(output_enable_t'pos(ch7), 2)
                         & to_unsigned(output_enable_t'pos(ch6), 2)
                         & to_unsigned(output_enable_t'pos(ch5), 2)
                         & to_unsigned(output_enable_t'pos(ch4), 2));
  end function;
  
  function si5351_msn_set(
    saddr: unsigned(6 downto 0);
    pll: ms_src_t;
    ratio: real;
    denom: integer := 1)
    return byte_string
  is
    variable p1, p2, p3: integer;
    variable p1u: unsigned(17 downto 0);
    variable p2u: unsigned(19 downto 0);
    variable p3u: unsigned(19 downto 0);
    variable bratio, rfrac: real;
    variable rint: integer;
  begin
    bratio := (ratio - 4.0) * 128.0;
    rint := integer(floor(bratio));
    rfrac := bratio - real(rint);
    p1 := rint;
    p2 := integer(round(rfrac * real(denom)));
    p3 := denom;

    p1u := to_unsigned(p1, 18);
    p2u := to_unsigned(p2, 20);
    p3u := to_unsigned(p3, 20);

    return si5351_be_set(saddr, if_else(pll = MS_SRC_PLLA, 26, 34),
                         p3u(15 downto 0)
                         & "000000" & p1u(17 downto 0)
                         & p3u(19 downto 16) & p2u(19 downto 0));
  end function;

  function si5351_ms05_set(
    saddr: unsigned(6 downto 0);
    channel: integer range 0 to 5;
    ratio: real;
    denom: integer := 1)
    return byte_string
  is
    variable p1, p2, p3: integer;
    variable p1u: unsigned(17 downto 0);
    variable p2u: unsigned(19 downto 0);
    variable p3u: unsigned(19 downto 0);
    constant div: unsigned(2 downto 0) := "000";
    variable divby4: std_ulogic;
    variable bratio, rfrac: real;
    variable rint: integer;
    variable div4: boolean;
  begin
    div4 := false;
    if ratio = 4.0 then
      p1 := 0;
      p2 := 0;
      p3 := 1;
      div4 := true;
    else
      assert ratio > 8.0 and ratio <= 2048.0
        report "Bad divisor"
        severity failure;
      bratio := (ratio - 4.0) * 128.0;
      rint := integer(floor(bratio));
      rfrac := bratio - real(rint);
      p1 := rint;
      p2 := integer(round(rfrac * real(denom)));
      p3 := denom;
    end if;

    divby4 := to_logic(div4);
    p1u := to_unsigned(p1, 18);
    p2u := to_unsigned(p2, 20);
    p3u := to_unsigned(p3, 20);

    return si5351_be_set(saddr, 42 + channel * 8,
                         p3u(15 downto 0)
                         & "0" & div & divby4 & divby4 & p1u(17 downto 0)
                         & p3u(19 downto 16) & p2u(19 downto 0));
  end function;

  function si5351_ms67_set(
    saddr: unsigned(6 downto 0);
    channel: integer range 6 to 7;
    ratio: integer)
    return byte_string
  is
    variable p1u: unsigned(7 downto 0) := to_unsigned(ratio, 8);
  begin
    return si5351_be_set(saddr, 90 + channel - 6, p1u);
  end function;

  function si5351_ms67_div_set(
    saddr: unsigned(6 downto 0);
    r6_l2, r7_l2: integer range 0 to 7)
    return byte_string
  is
    constant r6_div: unsigned(2 downto 0) := to_unsigned(r6_l2, 3);
    constant r7_div: unsigned(2 downto 0) := to_unsigned(r7_l2, 3);
  begin
    return si5351_be_set(saddr, 92, "0" & r7_div & "0" & r6_div);
  end function;

  function si5351_ss_none_set(
    saddr: unsigned(6 downto 0))
    return byte_string
  is
  begin
    return si5351_be_set(saddr, 149, x"00000000000000000000000000");
  end function;

  function si5351_reset(
    saddr: unsigned(6 downto 0);
    plla, pllb: boolean := true)
    return byte_string
  is
  begin
    return si5351_be_set(saddr, 177,
                         to_logic(pllb)
                         & "0"
                         & to_logic(plla)
                         & "0"
                         & x"c");
  end function;

end package body si5351;
