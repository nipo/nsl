library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package util is

  function log2 (x : positive) return natural;

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

  component reset_synchronizer
  generic(
    cycle_count : natural := 2
    );
    port (
      p_resetn      : in  std_ulogic;
      p_clk         : in  std_ulogic;
      p_resetn_sync : out std_ulogic
      );
  end component;

  component resync_reg is
    generic(
      cycle_count : natural := 2;
      data_width : integer
      );
    port(
      p_clk : in std_ulogic;
      p_in  : in std_ulogic_vector(data_width-1 downto 0);
      p_out : out std_ulogic_vector(data_width-1 downto 0)
      );
  end component;

  component baudrate_generator is
    generic(
      p_clk_rate : natural;
      rate_lsb   : natural := 8;
      rate_msb   : natural := 27
      );
    port(
      p_clk      : in std_ulogic;
      p_resetn   : in std_ulogic;
      p_rate     : in unsigned(rate_msb downto rate_lsb);
      p_tick     : out std_ulogic
      );
  end component;

end package util;

package body util is
    
  function log2 (x : positive) return natural is
  begin  -- log2
    if x <= 1 then
      return 0;
    else
      return log2((x+1)/2) + 1;
    end if;
  end log2;

end package body util;
