library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library nsl_data;
use nsl_data.bytestream.byte_string;

package endian is

  function to_le(word : unsigned) return byte_string;
  function from_le(data : byte_string) return unsigned;
  function to_be(word : unsigned) return byte_string;
  function from_be(data : byte_string) return unsigned;

end package endian;

package body endian is

  function to_le(word : unsigned) return byte_string is
    variable mem_data : byte_string(0 to word'length/8-1);
    alias xword : unsigned(word'length-1 downto 0) is word;
  begin
    assert word'length mod 8 = 0
      report "Input word must be made of n * 8 bits"
      severity failure;

    for i in mem_data'range
    loop
      mem_data(i) := std_ulogic_vector(xword(i * 8 + 7 downto i * 8));
    end loop;

    return mem_data;
  end function;
    
  function from_le(data : byte_string) return unsigned is
    alias mem_data : byte_string(0 to data'length - 1) is data;
    variable word : unsigned(data'length * 8-1 downto 0);
  begin
    for i in mem_data'range
    loop
      word(i * 8 + 7 downto i * 8) := unsigned(to_stdlogicvector(mem_data(i)));
    end loop;

    return word;
  end function;

  function to_be(word : unsigned) return byte_string is
    variable mem_data : byte_string(0 to word'length/8-1);
    alias xword : unsigned(word'length-1 downto 0) is word;
  begin
    assert word'length mod 8 = 0
      report "Input word must be made of n * 8 bits"
      severity failure;

    for i in mem_data'range
    loop
      mem_data(mem_data'length - 1 - i) := std_ulogic_vector(xword(i * 8 + 7 downto i * 8));
    end loop;

    return mem_data;
  end function;

  function from_be(data : byte_string) return unsigned is
    alias mem_data : byte_string(0 to data'length - 1) is data;
    variable word : unsigned(data'length * 8-1 downto 0);
  begin
    for i in mem_data'range
    loop
      word(i * 8 + 7 downto i * 8) := unsigned(to_stdlogicvector(mem_data(mem_data'length - 1 - i)));
    end loop;

    return word;
  end function;

end package body endian;
