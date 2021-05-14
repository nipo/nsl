library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_memory, nsl_data;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

entity rom_sfixed is
  generic(
    values_c : real_vector
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i : in std_ulogic;

    address_i : in unsigned(nsl_math.arith.log2(values_c'length-1)-1 downto 0);
    value_o : out sfixed
    );
end entity;    

architecture beh of rom_sfixed is

  constant dt_bit_count : integer := value_o'length;
  constant dt_byte_count : integer := (dt_bit_count + 7) / 8;
  subtype dt_word_type is std_ulogic_vector(dt_byte_count * 8 - 1 downto 0);

  function table_precalc(value: real_vector;
                         address_width: integer;
                         vl, vr: integer)
    return nsl_data.bytestream.byte_string
  is
    alias values: real_vector(0 to value'length-1) is value;
    variable value_f : sfixed(vl downto vr);
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

  signal rom_value: dt_word_type;

begin

  storage: nsl_memory.rom.rom_bytes
    generic map(
      word_addr_size_c => address_i'length,
      word_byte_count_c => dt_byte_count,
      contents_c => table_precalc(values_c, address_i'length, value_o'left, value_o'right)
      )
    port map(
      clock_i => clock_i,

      address_i => address_i,
      data_o => rom_value
      );

  value_o <= sfixed(rom_value(value_o'length-1 downto 0));

end architecture;
