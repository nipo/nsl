library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package logic_analyzer is

  component event_monitor
  generic(
    data_width : integer;
    delta_width : integer;
    sync_depth : integer
    );
  port(
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_in      : in std_ulogic_vector(data_width-1 downto 0);

    p_delta   : out std_ulogic_vector(delta_width-1 downto 0);
    p_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_valid   : out std_ulogic
    );
  end component;

end package logic_analyzer;
