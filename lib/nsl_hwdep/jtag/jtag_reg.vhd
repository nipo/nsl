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
    tlr_o    : out std_ulogic;
    run_o    : out std_ulogic;
    
    data_o   : out std_ulogic_vector(width_c-1 downto 0);
    update_o : out std_ulogic;

    data_i     : in std_ulogic_vector(width_c-1 downto 0);
    capture_o : out std_ulogic
    );
end entity;

architecture beh of jtag_reg is

  attribute keep : string;
  signal tck, shift, tdi, capture, selected, run, update: std_ulogic;
  signal reg: std_ulogic_vector(width_c-1 downto 0);
  attribute keep of reg : signal is "TRUE";
  
begin

  tap : nsl_hwdep.jtag.jtag_tap_register
    generic map(
      id_c => id_c
      )
    port map(
      capture_o  => capture,
      tlr_o  => tlr_o,
      tck_o      => tck,
      selected_o => selected,
      shift_o    => shift,
      run_o      => run,
      tdi_o      => tdi,
      update_o   => update,
      tdo_i      => reg(0)
      );

  clock_o <= tck;
  capture_o <= capture and selected;
  update_o <= update and selected;
  data_o <= reg;
  run_o <= run and selected;
  
  h: process(tck)
  begin
    if rising_edge(tck) then
      if selected = '1' then
        if capture = '1' then
          reg <= data_i;
        elsif shift = '1' then
          reg <= tdi & reg(width_c-1 downto 1);
        end if;
      end if;
    end if;
  end process;

end architecture;
