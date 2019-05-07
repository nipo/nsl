library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity jtag_tap_dr is
  generic(
    ir_len : natural;
    dr_len : natural
    );
  port(
    tck_i        : in  std_ulogic;
    tdi_i        : in  std_ulogic;
    tdo_o        : out std_ulogic;

    match_ir_i   : in  std_ulogic_vector(ir_len - 1 downto 0);
    current_ir_i : in  std_ulogic_vector(ir_len - 1 downto 0);
    active_o     : out std_ulogic;

    dr_capture_i : in  std_ulogic;
    dr_shift_i   : in  std_ulogic;
    value_o      : out std_ulogic_vector(dr_len - 1 downto 0);
    value_i      : in  std_ulogic_vector(dr_len - 1 downto 0)
    );
end entity;

architecture rtl of jtag_tap_dr is

  signal dr, dr_shreg: std_ulogic_vector(dr_len - 1 downto 0);
  signal s_selected : boolean;

begin

  s_selected <= std_match(current_ir_i, match_ir_i);
  active_o <= '1' when s_selected else '0';

  shreg: process(tck_i)
  begin
    if rising_edge(tck_i) and s_selected then
      if dr_capture_i = '1' then
        dr_shreg <= value_i;
      end if;
      
      if dr_shift_i = '1' then
        dr_shreg <= tdi_i & dr_shreg(dr_shreg'left downto 1);
      end if;
    end if;
  end process;

  tdo_o <= dr_shreg(0);
  value_o <= dr_shreg;

end architecture;
