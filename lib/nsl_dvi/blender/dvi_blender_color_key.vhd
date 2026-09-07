library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dvi_blender_color_key is
  generic(
    color_count_l2_c: natural;
    key_color_c: natural := 0
    );
  port(
    overlay_ready_o : out std_ulogic;
    overlay_valid_i : in std_ulogic;
    overlay_color_i : in unsigned(color_count_l2_c-1 downto 0);

    underlay_ready_o : out std_ulogic;
    underlay_valid_i : in std_ulogic;
    underlay_color_i : in unsigned(color_count_l2_c-1 downto 0);

    color_ready_i : in std_ulogic;
    color_valid_o : out std_ulogic;
    color_o : out unsigned(color_count_l2_c-1 downto 0)
    );
end entity;

architecture beh of dvi_blender_color_key is

  constant key_color_c_u : unsigned(color_count_l2_c-1 downto 0)
    := to_unsigned(key_color_c, color_count_l2_c);

  signal both_valid_s, taken_s : std_ulogic;

begin

  both_valid_s <= overlay_valid_i and underlay_valid_i;
  taken_s <= both_valid_s and color_ready_i;

  overlay_ready_o <= taken_s;
  underlay_ready_o <= taken_s;

  color_valid_o <= both_valid_s;
  color_o <= underlay_color_i when overlay_color_i = key_color_c_u
             else overlay_color_i;

end architecture;
