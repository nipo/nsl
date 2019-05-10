library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity gray_encoder is
  generic(
    data_width : integer
    );
  port(
    p_binary : in std_ulogic_vector(data_width-1 downto 0);
    p_gray : out std_ulogic_vector(data_width-1 downto 0)
    );
end entity;

architecture rtl of gray_encoder is

begin

  p_gray <= util.gray.bin_to_gray(unsigned(p_binary));
  
end architecture;
