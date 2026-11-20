library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

-- UltraScale / UltraScale+ DDR output.
-- ODDRE1 always behaves like the 7-series ODDR in SAME_EDGE mode: d_i(0)
-- is output while clock is high, d_i(1) while it is low.
-- SIM_DEVICE only affects simulation models.
entity ddr_output is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i   : in std_ulogic_vector(1 downto 0);
    dd_o  : out std_ulogic
    );
end entity;

architecture xcu of ddr_output is

  attribute BOX_TYPE : string;

  component ODDRE1
    generic (
      IS_C_INVERTED : bit := '0';
      IS_D1_INVERTED : bit := '0';
      IS_D2_INVERTED : bit := '0';
      SIM_DEVICE : string := "ULTRASCALE";
      SRVAL : bit := '0'
      );
    port (
      Q : out std_ulogic;
      C : in std_ulogic;
      D1 : in std_ulogic;
      D2 : in std_ulogic;
      SR : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    ODDRE1 : component is "PRIMITIVE";

begin

  pad: oddre1
    generic map(
      sim_device => "ULTRASCALE_PLUS"
      )
    port map(
      q => dd_o,
      c => clock_i.p,
      d1 => d_i(0),
      d2 => d_i(1),
      sr => '0'
      );

end architecture;
