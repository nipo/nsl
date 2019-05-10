library ieee;
use ieee.std_logic_1164.all;

library util;

entity gray_decoder is
  generic(
    data_width : integer
    );
  port(
    p_gray : in std_ulogic_vector(data_width-1 downto 0);
    p_binary : out std_ulogic_vector(data_width-1 downto 0)
    );
end entity;

architecture rtl of gray_decoder is

  signal s_binary : std_ulogic_vector(data_width-1 downto 0);

  attribute register_balancing: string;
  attribute register_balancing of s_binary: signal is "yes";
  
begin

  s_binary <= std_ulogic_vector(util.gray.gray_to_bin(p_gray));
  p_binary <= s_binary;
  
end architecture;
