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

-- Realized on the ALTDDIO_OUT megafunction rather than on the
-- cyclone10lp_ddio_out atom underneath it, for the same reason the
-- PLL wrapper takes ALTPLL: the atom carries clkhi, clklo, muxsel and
-- a use_new_clocking_model switch whose combinations decide which of
-- the two output registers reaches the pad in which half period, and
-- none of that encoding is documented.  ALTDDIO_OUT states the two
-- halves as datain_h and datain_l and leaves the atom's settings to
-- Quartus.
--
-- Of the megafunction's interface only width has no default: every
-- input holds a safe value and every output may stay open.
architecture cyclone10lp of ddr_output is

  component altddio_out is
    generic(
      width : positive;
      intended_device_family : string := "Cyclone 10 LP";
      power_up_high : string := "OFF";
      oe_reg : string := "UNUSED";
      extend_oe_disable : string := "UNUSED";
      invert_output : string := "OFF";
      lpm_type : string := "altddio_out"
      );
    port(
      datain_h : in std_logic_vector(width-1 downto 0);
      datain_l : in std_logic_vector(width-1 downto 0);
      outclock : in std_logic;
      outclocken : in std_logic := '1';
      aset : in std_logic := '0';
      aclr : in std_logic := '0';
      sset : in std_logic := '0';
      sclr : in std_logic := '0';
      oe : in std_logic := '1';
      dataout : out std_logic_vector(width-1 downto 0);
      oe_out : out std_logic_vector(width-1 downto 0)
      );
  end component;

  signal datain_h_s, datain_l_s, dataout_s : std_logic_vector(0 downto 0);

begin

  -- dataout carries datain_h while outclock is high and datain_l
  -- while it is low, which is the order this interface asks for:
  -- d_i(0) reaches the wire first.
  datain_h_s(0) <= d_i(0);
  datain_l_s(0) <= d_i(1);

  ddio: altddio_out
    generic map(
      width => 1,
      intended_device_family => "Cyclone 10 LP"
      )
    port map(
      datain_h => datain_h_s,
      datain_l => datain_l_s,
      outclock => clock_i.p,
      dataout => dataout_s
      );

  dd_o <= dataout_s(0);

end architecture;
