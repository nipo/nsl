library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;

package fifo is

  component fifo_2p
    generic(
      data_width : integer;
      depth      : integer;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_write  : in  std_ulogic;
      p_in_full_n : out std_ulogic;

      p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic
      );
  end component;

end package fifo;
