library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math, nsl_data, nsl_memory;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

entity sinus_stream_table_interpolated is
  generic (
    lookup_bits_c : integer := 9;
    table_bits_c : integer := 9;
    scale_c : real := 1.0
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    angle_i : in ufixed;
    value_o : out sfixed
    );
end sinus_stream_table_interpolated;

architecture beh of sinus_stream_table_interpolated is

  subtype full_address_t is unsigned(nsl_math.arith.min(lookup_bits_c+2, angle_i'length)-1 downto 0);
  subtype table_address_t is unsigned(full_address_t'length-3 downto 0);
  subtype table_value_t is ufixed(value_o'left-1 downto value_o'left-1-table_bits_c+1);
  subtype inverted_value_t is sfixed(value_o'left downto value_o'left-1-table_bits_c+1);
  subtype scaled_value_t is sfixed(value_o'left downto value_o'right-1);
  subtype inter_amount_t is ufixed(0 downto -angle_i'length + full_address_t'length);

  constant scaled_lsb_c : scaled_value_t := to_sfixed(2.0 ** scaled_value_t'right, scaled_value_t'left, scaled_value_t'right);
  constant scale_one_c : inter_amount_t := to_ufixed(1.0, inter_amount_t'left, inter_amount_t'right);
  
  -- Only store sinus for input values in (0 .. 0.25) angle range (0
  -- to π/2) with a half-bit skew. It avoids phase noise on folding.
  function table_precalc(aw: integer)
    return real_vector
  is
    variable ret : real_vector(0 to (2 ** aw)-1);
  begin
    each_angle: for i in ret'range
    loop
      ret(i) := sin((real(i) + 0.5) / real(2 ** aw) * MATH_PI_OVER_2) * scale_c;
    end loop;

    return ret;
  end function;

  type regs_t is
  record
    s0_angle : full_address_t;
    s0_b_inter : inter_amount_t;
    s0_a_index : table_address_t;
    s0_a_value_invert : boolean;
    s0_a_index_invert : boolean;

    s1_b_inter : inter_amount_t;
    s1_a_index : table_address_t;
    s1_a_value_invert : boolean;
    s1_b_angle : full_address_t;

    s2_b_inter : inter_amount_t;
    s2_b_index : table_address_t;
    s2_a_value_invert : boolean;
    s2_b_value_invert : boolean;
    
    s3_a_inter : inter_amount_t;
    s3_a_value : inverted_value_t;
    s3_b_inter : inter_amount_t;
    s3_b_value_invert : boolean;
    
    s4_a_scaled : scaled_value_t;
    s4_b_value : inverted_value_t;
    s4_b_inter : inter_amount_t;

    s5_a_scaled : scaled_value_t;
    s5_b_scaled : scaled_value_t;

    s6_value : sfixed(value_o'range);
  end record;

  signal s2_a_value: table_value_t;
  signal s3_b_value: table_value_t;
  
  signal r, rin: regs_t;

begin

  assert angle_i'left = -1
    report "angle_i'left must be -1"
    severity failure;

  regs: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;
  
  transition: process(r, angle_i, s3_b_value, s2_a_value)
  begin
    rin <= r;

    -- Stage 0, store angle, interpolation amount, lookup for a
    rin.s0_angle <= to_unsigned(angle_i(angle_i'left downto angle_i'left-full_address_t'length+1));
    rin.s0_b_inter <= "0" & angle_i(angle_i'left-full_address_t'length downto angle_i'right);
    rin.s0_a_value_invert <= angle_i(angle_i'left) = '1';
    rin.s0_a_index_invert <= angle_i(angle_i'left-1) = '1';
    rin.s0_a_index <= to_unsigned(angle_i(angle_i'left-2 downto angle_i'left-full_address_t'length+1));

    -- Stage 1, compute next index for b, entry address for a
    rin.s1_b_inter <= r.s0_b_inter;
    rin.s1_b_angle <= r.s0_angle + 1;

    if not r.s0_a_index_invert then
      rin.s1_a_index <= r.s0_a_index;
    else
      rin.s1_a_index <= not r.s0_a_index;
    end if;
    rin.s1_a_value_invert <= r.s0_a_value_invert;

    -- Stage 2, compute lookup for b, gather a
    rin.s2_b_inter <= r.s1_b_inter;
    rin.s2_a_value_invert <= r.s1_a_value_invert;

    if r.s1_b_angle(r.s1_b_angle'left-1) = '0' then
      rin.s2_b_index <= r.s1_b_angle(r.s1_b_angle'left-2 downto 0);
    else
      rin.s2_b_index <= not r.s1_b_angle(r.s1_b_angle'left-2 downto 0);
    end if;
    rin.s2_b_value_invert <= r.s1_b_angle(r.s1_b_angle'left) = '1';

    -- Stage 3, invert a, gather b
    rin.s3_b_inter <= r.s2_b_inter;
    rin.s3_a_inter <= scale_one_c - r.s2_b_inter;
    if r.s2_a_value_invert then
      rin.s3_a_value <= - sfixed("0" & s2_a_value);
    else
      rin.s3_a_value <= sfixed("0" & s2_a_value);
    end if;

    rin.s3_b_value_invert <= r.s2_b_value_invert;

    -- Stage 4, scale a, invert b, invert scale for b
    rin.s4_b_inter <= r.s3_b_inter;
    if r.s3_b_value_invert then
      rin.s4_b_value <= - sfixed("0" & s3_b_value);
    else
      rin.s4_b_value <= sfixed("0" & s3_b_value);
    end if;
    rin.s4_a_scaled <= mul(r.s3_a_value, r.s3_a_inter, rin.s4_a_scaled'left, rin.s4_a_scaled'right);

    -- Stage 5, scale b
    rin.s5_b_scaled <= mul(r.s4_b_value, r.s4_b_inter, rin.s5_b_scaled'left, rin.s5_b_scaled'right);
    rin.s5_a_scaled <= r.s4_a_scaled;

    -- Stage 6, done
    rin.s6_value <= resize(r.s5_a_scaled + r.s5_b_scaled + scaled_lsb_c, value_o'left, value_o'right);
  end process;

  storage: nsl_memory.rom_fixed.rom_ufixed_2p
    generic map(
      values_c => table_precalc(table_address_t'length)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      a_address_i => r.s1_a_index,
      a_value_o => s2_a_value,

      b_address_i => r.s2_b_index,
      b_value_o => s3_b_value
      );

  value_o <= r.s6_value;

end architecture;
