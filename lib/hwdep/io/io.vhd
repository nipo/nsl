library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;
use signalling.diff.all;

package io is

  component diff_clock_input
    port(
      p_i : in  diff_pair;
      p_o : out diff_pair
      );
  end component;

  -- Source-synchronous DDR output, edge-aligned
  -- p_d is sampled on p_clk rising edge
  -- p_d(0) is on p_dd while p_clk is high (on wire first)
  -- p_d(1) is on p_dd while p_clk is low (on wire late)
  component io_ddr_output
    port(
      p_clk : in diff_pair;
      p_d   : in std_ulogic_vector(1 downto 0);
      p_dd  : out std_ulogic
      );
  end component;

  -- DDR input
  -- p_clk is sampling clock, it should be 90° late on signal edges
  -- p_d is updated on p_clk90 falling edge, it is stable on signal clock
  -- rising edge, so that it can be resynchronized in the design.
  -- p_d(0) is synchronous to p_clk high (on wire first)
  -- p_d(1) is synchronous to p_clk low (on wire late)
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
