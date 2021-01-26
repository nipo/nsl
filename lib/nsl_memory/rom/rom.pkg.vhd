library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;

package rom is

  component rom_bytes
    generic (
      word_addr_size_c : natural;
      word_byte_count_c : natural;
      -- word_byte_count_c * 2 ** word_addr_size_c bytes
      contents_c : nsl_data.bytestream.byte_string;
      little_endian_c : boolean := true
      );
    port (
      clock_i : in std_ulogic;

      read_i : in std_ulogic := '1';
      address_i : in unsigned(word_addr_size_c-1 downto 0);
      data_o : out std_ulogic_vector(8*word_byte_count_c-1 downto 0)
      );
  end component;

end package rom;
