library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;
use hwdep.jtag.jtag_tap_register;

entity jtag_reg is
  generic(
    width : integer;
    id    : natural range 1 to 4
    );
  port(
    p_clk       : out std_ulogic;
    p_resetn    : out std_ulogic;
    
    p_inbound_data   : out std_ulogic_vector(width-1 downto 0);
    p_inbound_update : out std_ulogic;

    p_outbound_data     : in std_ulogic_vector(width-1 downto 0);
    p_outbound_captured : out std_ulogic
    );
end entity;

architecture beh of jtag_reg is

  signal s_clk, s_shift, s_tdi, s_reset, s_capture, s_selected: std_ulogic;
  signal s_reg: std_ulogic_vector(width-1 downto 0);
  
begin

  tap : hwdep.jtag.jtag_tap_register
    generic map(
      id => id
      )
    port map(
      p_capture  => s_capture,
      p_reset    => s_reset,
      p_tck      => s_clk,
      p_selected => s_selected,
      p_shift    => s_shift,
      p_tdi      => s_tdi,
      p_update   => p_inbound_update,
      p_tdo      => s_reg(0)
      );

  p_resetn <= not s_reset;
  p_clk <= s_clk;
  p_outbound_captured <= s_capture;
  p_inbound_data <= s_reg;
  
  h: process(s_clk)
  begin
    if rising_edge(s_clk) then
      if s_selected = '1' then
        if s_capture = '1' then
          s_reg <= p_outbound_data;
        elsif s_shift = '1' then
          s_reg <= s_tdi & s_reg(width-1 downto 1);
        end if;
      end if;
    end if;
  end process;

end architecture;
