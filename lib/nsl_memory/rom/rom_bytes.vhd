library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;

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
begin

  assert
    contents_c'length = word_byte_count_c * 2 ** word_addr_size_c
    report "Initialization vector does not match ROM size"
    severity failure;

end entity;

architecture beh of rom_bytes is

  subtype word_t is unsigned(word_byte_count_c * 8 - 1 downto 0);
  type mem_t is array(natural range 0 to 2**word_addr_size_c-1) of word_t;

  function ram_init(blob : nsl_data.bytestream.byte_string) return mem_t is
    variable ret : mem_t;
    variable tmp : nsl_data.bytestream.byte_string(0 to word_byte_count_c-1);
  begin
    for i in 0 to ret'length-1
    loop
      tmp := blob(blob'left + i*word_byte_count_c to blob'left + (i+1) * word_byte_count_c - 1);
      if little_endian_c then
        ret(i) := nsl_data.endian.from_le(tmp);
      else
        ret(i) := nsl_data.endian.from_be(tmp);
      end if;
    end loop;

    return ret;
  end function;

  constant memory : mem_t := ram_init(contents_c);

begin

  reader: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      if read_i = '1' then
        data_o <= std_ulogic_vector(memory(to_integer(address_i)));
      end if;
    end if;
  end process;
  
end architecture;
