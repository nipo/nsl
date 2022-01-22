library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_data;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

package rom_fixed is

  component rom_ufixed is
    generic(
      values_c : real_vector
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      read_i : in std_ulogic := '1';
      address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      value_o : out ufixed
      );
  end component;    

  component rom_sfixed is
    generic(
      values_c : real_vector
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      read_i : in std_ulogic := '1';
      address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      value_o : out sfixed
      );
  end component;    

  component rom_ufixed_2p is
    generic(
      values_c : real_vector
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      a_read_i : in std_ulogic := '1';
      a_address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      a_value_o : out ufixed;

      b_read_i : in std_ulogic := '1';
      b_address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      b_value_o : out ufixed
      );
  end component;    

  component rom_sfixed_2p is
    generic(
      values_c : real_vector
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i : in std_ulogic;

      a_read_i : in std_ulogic := '1';
      a_address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      a_value_o : out sfixed;

      b_read_i : in std_ulogic := '1';
      b_address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
      b_value_o : out sfixed
      );
  end component;    

  function sfixed_rom_table_precalc(value: real_vector;
                                    address_width: integer;
                                    vl, vr: integer)
    return nsl_data.bytestream.byte_string;

  function ufixed_rom_table_precalc(value: real_vector;
                                    address_width: integer;
                                    vl, vr: integer)
    return nsl_data.bytestream.byte_string;

end package rom_fixed;

package body rom_fixed is

  function sfixed_rom_table_precalc(value: real_vector;
                                    address_width: integer;
                                    vl, vr: integer)
    return nsl_data.bytestream.byte_string
  is
    variable value_f : sfixed(vl downto vr);

    constant dt_bit_count : integer := value_f'length;
    constant dt_byte_count : integer := (dt_bit_count + 7) / 8;
    subtype dt_word_type is std_ulogic_vector(dt_byte_count * 8 - 1 downto 0);

    alias values: real_vector(0 to value'length-1) is value;
    variable ret : nsl_data.bytestream.byte_string(0 to ((2 ** address_width) * dt_byte_count)-1);
    variable entry : dt_word_type;
  begin
    ret := (others => (others => '-'));

    filler: for i in values'range
    loop
      value_f := to_sfixed(values(i), vl, vr);

      entry := (others => '-');
      entry(value_f'length-1 downto 0) := to_suv(value_f);

      ret(dt_byte_count * i to (dt_byte_count + 1) * i - 1)
        := nsl_data.endian.to_le(unsigned(entry));
    end loop;

    return ret;
  end function;

  function ufixed_rom_table_precalc(value: real_vector;
                                    address_width: integer;
                                    vl, vr: integer)
    return nsl_data.bytestream.byte_string
  is
    variable value_f : ufixed(vl downto vr);

    constant dt_bit_count : integer := value_f'length;
    constant dt_byte_count : integer := (dt_bit_count + 7) / 8;
    subtype dt_word_type is std_ulogic_vector(dt_byte_count * 8 - 1 downto 0);

    alias values: real_vector(0 to value'length-1) is value;
    variable ret : nsl_data.bytestream.byte_string(0 to ((2 ** address_width) * dt_byte_count)-1);
    variable entry : dt_word_type;
  begin
    ret := (others => (others => '0'));

    assert value'length <= 2 ** address_width;
    
    filler: for i in values'range
    loop
      value_f := to_ufixed(values(i), vl, vr);

      entry := (others => '-');
      entry(value_f'length-1 downto 0) := to_suv(value_f);

      ret(dt_byte_count * i to dt_byte_count * (i + 1) - 1)
        := nsl_data.endian.to_le(unsigned(entry));
    end loop;

    return ret;
  end function;
  
end package body;
