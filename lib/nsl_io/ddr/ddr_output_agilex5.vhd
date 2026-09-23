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

-- The GPIO IP drives datainlo with the word that leaves first, so
-- d_i(0) goes there.  areset is active low, sreset active high.
architecture agilex5 of ddr_output is

  component tennm_ph2_ddio_out is
    generic(
      mode      : string := "MODE_DDR";
      asclr_ena : string := "ASCLR_ENA_NONE";
      sclr_ena  : string := "SCLR_ENA_NONE"
      );
    port(
      areset   : in  std_logic := '1';
      sreset   : in  std_logic := '0';
      ena      : in  std_logic := '1';
      clk      : in  std_logic;
      datainlo : in  std_logic;
      datainhi : in  std_logic;
      dataout  : out std_logic
      );
  end component;

begin

  ddio: tennm_ph2_ddio_out
    generic map(
      mode      => "MODE_DDR",
      asclr_ena => "ASCLR_ENA_NONE",
      sclr_ena  => "SCLR_ENA_NONE"
      )
    port map(
      clk      => clock_i.p,
      datainlo => d_i(0),
      datainhi => d_i(1),
      dataout  => dd_o,
      areset   => '1',
      sreset   => '0',
      ena      => '1'
      );

end architecture;
