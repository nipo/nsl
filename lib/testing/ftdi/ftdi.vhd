library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package ftdi is

  component ft245_sync_fifo_merger
    port (
      p_clk    : in std_ulogic;

      p_data : inout std_logic_vector(7 downto 0);
      p_rxfn : out   std_ulogic;
      p_txen : out   std_ulogic;
      p_rdn  : in    std_ulogic;
      p_wrn  : in    std_ulogic;
      p_oen  : in    std_ulogic;

      -- connected to wrn and txen
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic;
      p_out_data    : out std_ulogic_vector(7 downto 0);

      -- connected to rdn and rxfn
      p_in_full_n : out std_ulogic;
      p_in_write  : in  std_ulogic;
      p_in_data   : in  std_ulogic_vector(7 downto 0)
      );
  end component;
  
end package ftdi;
