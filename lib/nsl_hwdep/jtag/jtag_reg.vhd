library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep;
use nsl_hwdep.jtag.jtag_tap_register;

entity jtag_reg is
  generic(
    width_c : integer;
    id_c    : natural range 1 to 4
    );
  port(
    clock_o       : out std_ulogic;
    reset_n_o    : out std_ulogic;
    
    data_o   : out std_ulogic_vector(width_c-1 downto 0);
    update_o : out std_ulogic;

    data_i     : in std_ulogic_vector(width_c-1 downto 0);
    capture_o : out std_ulogic
    );
end entity;

architecture beh of jtag_reg is

  signal s_clk, s_shift, s_tdi, s_reset, s_capture, s_selected: std_ulogic;
  signal s_reg: std_ulogic_vector(width_c-1 downto 0);
  
begin

  tap : nsl_hwdep.jtag.jtag_tap_register
    generic map(
      id_c => id_c
      )
    port map(
      capture_o  => s_capture,
      reset_o    => s_reset,
      tck_o      => s_clk,
      selected_o => s_selected,
      shift_o    => s_shift,
      tdi_o      => s_tdi,
      update_o   => update_o,
      tdo_i      => s_reg(0)
      );

  reset_n_o <= not s_reset;
  clock_o <= s_clk;
  capture_o <= s_capture;
  data_o <= s_reg;
  
  h: process(s_clk)
  begin
    if rising_edge(s_clk) then
      if s_selected = '1' then
        if s_capture = '1' then
          s_reg <= data_i;
        elsif s_shift = '1' then
          s_reg <= s_tdi & s_reg(width_c-1 downto 1);
        end if;
      end if;
    end if;
  end process;

end architecture;
