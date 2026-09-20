library ieee;
use ieee.std_logic_1164.all;

entity delay_reference is
  port(
    -- 200 MHz, which is what the delay lines of this family are told
    -- to expect
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ready_o : out std_ulogic
    );
end entity;

architecture xc7 of delay_reference is

  attribute BOX_TYPE : string;

  component IDELAYCTRL
    port (
      RDY : out std_ulogic;
      REFCLK : in std_ulogic;
      RST : in std_ulogic
      );
  end component;
  attribute BOX_TYPE of
    IDELAYCTRL : component is "PRIMITIVE";

  signal reset_s: std_ulogic;

begin

  reset_s <= not reset_n_i;

  inst: idelayctrl
    port map(
      rdy => ready_o,
      refclk => clock_i,
      rst => reset_s
      );

end architecture;
