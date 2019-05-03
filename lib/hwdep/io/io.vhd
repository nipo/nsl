library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;
use signalling.diff.all;

package io is

  component io_clock_output is
    port(
      p_clk : in signalling.diff.diff_pair;
      p_port    : out std_ulogic
      );
  end component;

  -- Source-synchronous DDR output, edge-aligned
  -- p_d is sampled on p_clk rising edge
  -- p_d(0) is on p_dd while p_clk is high (on wire first), to be sampled on falling edge
  -- p_d(1) is on p_dd while p_clk is low (on wire late), to be sampled on rising edge
  --
  --  Sample out of design
  --                     d0/d1     d2/d3     d4/d5
  --                       v         v         v
  --              ____      ____      ____      ____      __
  --  Clock  ____/    \____/    \____/    \____/    \____/ 
  --  d(0)        XXXXXX D0 XXXXXX D2 XXXXXX D4 XXXXXX
  --  d(1)        XXXXXX D1 XXXXXX D3 XXXXXX D5 XXXXXX
  --  dd         X    X    X D0 X D1 X D2 X D3 X D4 X D5 X
  
  component io_ddr_output
    port(
      p_clk : in diff_pair;
      p_d   : in std_ulogic_vector(1 downto 0);
      p_dd  : out std_ulogic
      );
  end component;

  -- DDR input
  -- p_clk is sampling clock
  -- p_d(0) is synchronous to p_clk high (on wire first), to be sampled on falling edge
  -- p_d(1) is synchronous to p_clk low (on wire late), to be sampled on rising edge
  --
  --  Sample in design             d0/d1     d2/d3     d4/d5
  --                                 v         v         v
  --              ____      ____      ____      ____      __
  --  Clock  ____/    \____/    \____/    \____/    \____/ 
  --  dd         X D0 X D1 X D2 X D3 X D4 X D5 X
  --  d(0)                  XXXXXX D0 XXXXXX D2 XXXXXX D4 XXXXX
  --  d(1)                  XXXXXX D1 XXXXXX D3 XXXXXX D5 XXXXX
  component io_ddr_input
    port(
      p_clk : in diff_pair;
      p_dd  : in std_ulogic;
      p_d   : out std_ulogic_vector(1 downto 0)
      );
  end component;

  -- DDR output bus
  -- An array of io_ddr_output
  -- Clock propagation scheme is not handled here
  component io_ddr_bus_output
    generic(
      ddr_width : natural
      );
    port(
      p_clk   : in  diff_pair;
      p_d     : in  std_ulogic_vector(2 * ddr_width - 1 downto 0);
      p_dd    : out std_ulogic_vector(ddr_width - 1 downto 0)
      );
  end component;

  -- DDR output bus
  -- An array of io_ddr_input
  -- Clock propagation scheme is not handled here
  component io_ddr_bus_input
    generic(
      ddr_width : natural
      );
    port(
      p_clk   : in  diff_pair;
      p_dd    : in  std_ulogic_vector(ddr_width - 1 downto 0);
      p_d     : out std_ulogic_vector(2 * ddr_width - 1 downto 0)
      );
  end component;
  
end package io;
