library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 8;
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  
  signal s_bin : word_t := (others => '0');
  signal s_gray : word_t;
  signal s_bin2 : word_t := (others => '0');
  
begin

  encoder: util.gray.gray_encoder
    generic map(
      data_width => data_width
      )
    port map(
      p_binary => s_bin,
      p_gray => s_gray
      );

  decoder: util.gray.gray_decoder
    generic map(
      data_width => data_width
      )
    port map(
      p_gray => s_gray,
      p_binary => s_bin2
      );

  process
  begin

    for i in 0 to 2**data_width-1
    loop
      wait for 1 ns;
      s_bin <= std_ulogic_vector(unsigned(s_bin) + 1);
      assert s_bin = s_bin2 report "Bad encoding or decoding" severity failure;
    end loop;

    wait;
  end process;
  
end;
