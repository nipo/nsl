library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library nsl_data;
use nsl_data.bytestream.byte_string;

-- Endianness handling
--
-- Converts multi-byte numbers to byte strings.
package endian is

  type endian_t is (
    ENDIAN_LITTLE,
    ENDIAN_BIG
    );
  
  function to_le(word : unsigned) return byte_string;
  function from_le(data : byte_string) return unsigned;
  function to_be(word : unsigned) return byte_string;
  function from_be(data : byte_string) return unsigned;
  function to_endian(word : unsigned; order: endian_t) return byte_string;
  function from_endian(data : byte_string; order: endian_t) return unsigned;
  function bitswap(x: std_ulogic_vector) return std_ulogic_vector;
  function byteswap(x: std_ulogic_vector) return std_ulogic_vector;
  function byteswap(x: unsigned) return unsigned;

end package endian;

package body endian is

  function bitswap(x:std_ulogic_vector) return std_ulogic_vector is
    alias xx: std_ulogic_vector(0 to x'length - 1) is x;
    variable rx: std_ulogic_vector(x'length - 1 downto 0);
  begin
    for i in xx'range
    loop
      rx(i) := xx(i);
    end loop;
    return rx;
  end function;

  function byteswap(x: unsigned) return unsigned is
  begin
    return from_le(to_be(x));
  end function;

  function byteswap(x:std_ulogic_vector) return std_ulogic_vector is
  begin
    return std_ulogic_vector(byteswap(unsigned(x)));
  end function;

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
      word(i * 8 + 7 downto i * 8) := unsigned(std_logic_vector(mem_data(i)));
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

  function to_endian(word : unsigned; order: endian_t) return byte_string
  is
  begin
    if order = ENDIAN_LITTLE then
      return to_le(word);
    else
      return to_be(word);
    end if;
  end function;
  
  function from_endian(data : byte_string; order: endian_t) return unsigned
  is
  begin
    if order = ENDIAN_LITTLE then
      return from_le(data);
    else
      return from_be(data);
    end if;
  end function;
  
end package body endian;
