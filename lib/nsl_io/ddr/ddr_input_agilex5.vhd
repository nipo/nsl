library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_input is
  generic(
    invert_clock_polarity_c : boolean := false
    );
  port(
    clock_i : in nsl_io.diff.diff_pair;
    dd_i  : in std_ulogic;
    d_o   : out std_ulogic_vector(1 downto 0)
    );
end entity;

architecture alteran_tennm of ddr_input is

  signal clock_s: nsl_io.diff.diff_pair;

  component tennm_ph2_ddio_in is
    generic(
      mode : string := "MODE_DDR";
      asclr_ena : string := "ASCLR_ENA_NONE";
      sclr_ena : string := "SCLR_ENA_NONE"
      );
    port(
      clk : in std_logic := '1';
      areset : in std_logic := '1';
      sreset : in std_logic := '1';
      ena : in std_logic := '1';
      datain : in std_logic := '1';
      regoutlo : out std_logic;
      regouthi : out std_logic
      );
  end component;

begin

  clock_s <= nsl_io.diff.swap(clock_i, invert_clock_polarity_c);

  inst: tennm_ph2_ddio_in
    generic map(
      mode => "MODE_DDR",
      sclr_ena => "SCLR_ENA_NONE",
      asclr_ena => "ASCLR_ENA_NONE"
      )
    port map (
      ena => '1',
      areset => '1',
      sreset => '0',
      datain => dd_i,
      clk => clock_s.p,
      regoutlo => d_o(0),
      regouthi => d_o(1)
      );

end architecture;
