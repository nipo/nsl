library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package gray is

  function bin_to_gray(binary : unsigned) return std_ulogic_vector;
  function gray_to_bin(gray : std_ulogic_vector) return unsigned;

  component gray_encoder
    generic(
      data_width : integer
      );
    port(
      p_binary : in std_ulogic_vector(data_width-1 downto 0);
      p_gray : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

  component gray_decoder
    generic(
      data_width : integer
      );
    port(
      p_gray : in std_ulogic_vector(data_width-1 downto 0);
      p_binary : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

end package gray;
