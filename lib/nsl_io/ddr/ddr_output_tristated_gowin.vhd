library ieee;
use ieee.std_logic_1164.all;

library nsl_io, gowin;

entity ddr_output_tristated is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i : in std_ulogic_vector(1 downto 0);
    oe_i : in std_ulogic;
    pad_o : out nsl_io.io.tristated
    );
end entity;

architecture gowin of ddr_output_tristated is

  attribute syn_black_box: boolean;

  component ODDR is
    GENERIC (
      TXCLK_POL : bit := '0';
      CONSTANT INIT : std_logic := '0'
      );
    PORT (
      Q0 : OUT std_logic;
      Q1 : OUT std_logic;
      D0 : IN std_logic;
      D1 : IN std_logic;
      TX : IN std_logic;
      CLK : IN std_logic
      );
  end component;
  attribute syn_black_box of ODDR : component is true;

  signal disable_s, tristate_s: std_logic;

begin

  -- Q1 is meant to reach the pad driver's OEN, which is a disable: the
  -- vendor's own buffer drives its pin only while OEN is low.  So TX
  -- carries the complement of an output enable, and so does Q1.
  --
  -- The tristate path is one register per clock period where the data
  -- path is two, which is what the silicon offers: a pad turns around
  -- on a period boundary, never inside one.
  inst: ODDR
    port map (
      q0 => pad_o.v,
      q1 => disable_s,
      clk => clock_i.p,
      tx => tristate_s,
      d0 => d_i(0),
      d1 => d_i(1)
      );

  tristate_s <= not oe_i;
  pad_o.en <= not disable_s;

end architecture;
