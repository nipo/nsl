library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 8;
  subtype word_t is unsigned(data_width-1 downto 0);
  
begin

  process
    variable s_bin : word_t := (others => '0');
    variable s_bin2 : word_t := (others => '0');
  begin
    for i in 0 to 2**data_width-1
    loop
      s_bin2 := nsl_math.gray.gray_to_bin(nsl_math.gray.bin_to_gray(s_bin));
      assert s_bin = s_bin2 report "Bad encoding or decoding" severity failure;
      s_bin := s_bin + 1;
    end loop;
    assert false report "OK" severity note;
    wait;
  end process;
  
end;
