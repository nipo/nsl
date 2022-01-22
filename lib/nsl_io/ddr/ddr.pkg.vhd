library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

package ddr is

  component ddr_clock_output is
    port(
      clock_i : in nsl_io.diff.diff_pair;
      port_o    : out std_ulogic
      );
  end component;

  -- Source-synchronous DDR output, edge-aligned
  -- d_i is sampled on clock_i rising edge
  -- d_i(0) is on dd_o while clock_i is high (on wire first), to be sampled on falling edge
  -- d_i(1) is on dd_o while clock_i is low (on wire late), to be sampled on rising edge
  --
  --  Sample out of design
  --                     d0/d1     d2/d3     d4/d5
  --                       v         v         v
  --              ____      ____      ____      ____      __
  --  Clock  ____/    \____/    \____/    \____/    \____/ 
  --  d(0)        XXXXXX D0 XXXXXX D2 XXXXXX D4 XXXXXX
  --  d(1)        XXXXXX D1 XXXXXX D3 XXXXXX D5 XXXXXX
  --  dd         X    X    X D0 X D1 X D2 X D3 X D4 X D5 X
  
  component ddr_output
    port(
      clock_i : in nsl_io.diff.diff_pair;
      d_i   : in std_ulogic_vector(1 downto 0);
      dd_o  : out std_ulogic
      );
  end component;

  -- DDR input
  -- clock_i is sampling clock
  -- d_o(0) is synchronous to clock_i high (on wire first), to be sampled on falling edge
  -- d_o(1) is synchronous to clock_i low (on wire late), to be sampled on rising edge
  --
  --  Sample in design             d0/d1     d2/d3     d4/d5
  --                                 v         v         v
  --              ____      ____      ____      ____      __
  --  Clock  ____/    \____/    \____/    \____/    \____/ 
  --  dd         X D0 X D1 X D2 X D3 X D4 X D5 X
  --  d(0)                  XXXXXX D0 XXXXXX D2 XXXXXX D4 XXXXX
  --  d(1)                  XXXXXX D1 XXXXXX D3 XXXXXX D5 XXXXX
  component ddr_input
    generic(
      invert_clock_polarity_c : boolean := false
      );
    port(
      clock_i : in nsl_io.diff.diff_pair;
      dd_i  : in std_ulogic;
      d_o   : out std_ulogic_vector(1 downto 0)
      );
  end component;

  -- DDR output bus
  -- An array of ddr_output
  -- Clock propagation scheme is not handled here
  component ddr_bus_output
    generic(
      ddr_width : natural
      );
    port(
      clock_i   : in  nsl_io.diff.diff_pair;
      d_i     : in  std_ulogic_vector(2 * ddr_width - 1 downto 0);
      dd_o    : out std_ulogic_vector(ddr_width - 1 downto 0)
      );
  end component;

  -- DDR output bus
  -- An array of ddr_input
  -- Clock propagation scheme is not handled here
  component ddr_bus_input
    generic(
      invert_clock_polarity_c : boolean := false;
      ddr_width : natural
      );
    port(
      clock_i   : in  nsl_io.diff.diff_pair;
      dd_i    : in  std_ulogic_vector(ddr_width - 1 downto 0);
      d_o     : out std_ulogic_vector(2 * ddr_width - 1 downto 0)
      );
  end component;
  
end package ddr;
