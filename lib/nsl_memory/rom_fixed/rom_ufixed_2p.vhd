library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_memory, nsl_data;
use nsl_math.fixed.all;
use nsl_math.real_ext.all;

entity rom_ufixed_2p is
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
end entity;    

architecture beh of rom_ufixed_2p is

  constant dt_bit_count : integer := a_value_o'length;
  constant dt_byte_count : integer := (dt_bit_count + 7) / 8;
  subtype dt_word_type is std_ulogic_vector(dt_byte_count * 8 - 1 downto 0);
  signal a_rom_value, b_rom_value: dt_word_type;

begin

  storage: nsl_memory.rom.rom_bytes_2p
    generic map(
      word_addr_size_c => a_address_i'length,
      word_byte_count_c => dt_byte_count,
      contents_c => nsl_memory.rom_fixed.ufixed_rom_table_precalc(
        values_c, a_address_i'length, a_value_o'left, a_value_o'right)
      )
    port map(
      clock_i => clock_i,

      a_read_i => a_read_i,
      a_address_i => a_address_i,
      a_data_o => a_rom_value,

      b_read_i => b_read_i,
      b_address_i => b_address_i,
      b_data_o => b_rom_value
      );

  a_value_o <= ufixed(a_rom_value(a_value_o'length-1 downto 0));
  b_value_o <= ufixed(b_rom_value(b_value_o'length-1 downto 0));

end architecture;
