library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math, nsl_data, nsl_memory;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

entity sinus_stream_table is
  generic (
    scale_c : real := 1.0
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    angle_i : in ufixed;
    value_o : out sfixed
    );
end sinus_stream_table;

architecture beh of sinus_stream_table is

  constant dt_bit_count : integer := value_o'length-1;
  constant dt_byte_count : integer := (dt_bit_count + 7) / 8;
  subtype dt_word_type is std_ulogic_vector(dt_byte_count * 8 - 1 downto 0);

  -- Only store sinus for input values in (0 .. 0.25) angle range (0
  -- to pi/2), offset by 0.5 angle LSB. Rest of it will be computed.
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

  -- Decompose angle input as:
  -- -1 -2 -3 ... angle_i'right
  --  A  B  xxxxxxxxxxxxxxxxxxxx
  --
  -- A is rom output inversion enable
  -- B is rom index inversion enable

  type regs_t is
  record
    s0_index : unsigned(angle_i'length - 3 downto 0);
    s0_value_invert : boolean;
    s0_index_invert : boolean;
    
    s1_index : unsigned(angle_i'length - 3 downto 0);
    s1_value_invert : boolean;
    
    s2_value_invert : boolean;

    s3_value_invert : boolean;
    s3_value: ufixed(value_o'left-1 downto value_o'right);

    s4_value_invert : boolean;
    s4_value : sfixed(value_o'left downto value_o'right);
    s4_value_inverted : sfixed(value_o'left downto value_o'right);

    s5_value : sfixed(value_o'left downto value_o'right);
  end record;

  signal s2_value: ufixed(value_o'left-1 downto value_o'right);
  
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
  
  transition: process(r, angle_i, s2_value)
  begin
    rin <= r;

    -- Stage 0, store inputs without computation
    rin.s0_value_invert <= angle_i(angle_i'left) = '1';
    rin.s0_index_invert <= angle_i(angle_i'left-1) = '1';
    rin.s0_index <= unsigned(to_suv(angle_i(angle_i'left-2 downto angle_i'right)));

    -- Stage 1, compute actual ROM address
    if not r.s0_index_invert then
      rin.s1_index <= r.s0_index;
    else
      rin.s1_index <= not r.s0_index;
    end if;
    rin.s1_value_invert <= r.s0_value_invert;

    -- Stage 2, do ROM lookup
    rin.s2_value_invert <= r.s1_value_invert;

    -- Stage 3, get ROM data
    rin.s3_value <= s2_value;
    rin.s3_value_invert <= r.s2_value_invert;

    -- Stage 4, invert output
    rin.s4_value_invert <= r.s3_value_invert;
    rin.s4_value_inverted <= - sfixed("0" & r.s3_value);
    rin.s4_value <= sfixed("0" & r.s3_value);

    -- Stage 5, take the right one
    if r.s4_value_invert then
      rin.s5_value <= r.s4_value_inverted;
    else
      rin.s5_value <= r.s4_value;
    end if;
  end process;

  storage: nsl_memory.rom_fixed.rom_ufixed
    generic map(
      values_c => table_precalc(r.s1_index'length)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      address_i => r.s1_index,
      value_o => s2_value
      );

  value_o <= r.s5_value;

end architecture;
