library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_output is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i   : in std_ulogic_vector(1 downto 0);
    dd_o  : out std_ulogic
    );
end entity;

architecture ecp5 of ddr_output is

  -- D0 leaves on the rising edge of SCLK and D1 on the falling one,
  -- which is the order this interface asks for.  The name is the same
  -- under Diamond and under Trellis, so one architecture serves both.
  component ODDRX1F
    port (
      D0 : in std_logic;
      D1 : in std_logic;
      SCLK : in std_logic;
      RST : in std_logic;
      Q : out std_logic
      );
  end component;

  signal q_s: std_logic;

begin

  inst: ODDRX1F
    port map(
      d0 => d_i(0),
      d1 => d_i(1),
      sclk => clock_i.p,
      rst => '0',
      q => q_s
      );

  dd_o <= q_s;

end architecture;
