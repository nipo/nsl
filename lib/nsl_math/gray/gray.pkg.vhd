library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gray is

  function bin_to_gray(binary : unsigned) return std_ulogic_vector;
  function gray_to_bin(gray : std_ulogic_vector) return unsigned;

end package gray;

package body gray is

  function bin_to_gray(binary : unsigned) return std_ulogic_vector is
    constant b_left: integer := binary'length-1;
    alias binary_uns: unsigned(b_left downto 0) is binary;
    variable binary_suv : std_ulogic_vector(binary_uns'range);
  begin
    binary_suv := std_ulogic_vector(binary_uns);
    return binary_suv xor ("0" & binary_suv(binary_suv'left downto 1));
  end function;
  
  function gray_to_bin(gray : std_ulogic_vector) return unsigned is
    constant g_left: integer := gray'length-1;
    alias gray_suv: std_ulogic_vector(g_left downto 0) is gray;
    variable binary_suv: std_ulogic_vector(g_left downto 0);
  begin
    bit_loop: for i in 0 to g_left
    loop
      binary_suv(i) := '0';
      bit_loop2: for j in i to g_left
      loop
        binary_suv(i) := binary_suv(i) xor gray_suv(j);
      end loop;
    end loop;

    return unsigned(binary_suv);
  end function;

end package body gray;
