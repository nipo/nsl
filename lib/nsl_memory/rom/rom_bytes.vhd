library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_memory;

entity rom_bytes is
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
end entity;

architecture beh of rom_bytes is

  constant a_zero : unsigned(word_addr_size_c-1 downto 0) := (others => '0');
  
begin

  impl: nsl_memory.rom.rom_bytes_2p
    generic map(
      word_addr_size_c => word_addr_size_c,
      word_byte_count_c => word_byte_count_c,
      contents_c => contents_c,
      little_endian_c => little_endian_c
      )
    port map(
      clock_i => clock_i,

      a_read_i => read_i,
      a_address_i => address_i,
      a_data_o => data_o,

      b_read_i => '0',
      b_address_i => a_zero,
      b_data_o => open
      );
  
end architecture;
