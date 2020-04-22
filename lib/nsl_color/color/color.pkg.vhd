library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package color is

  type rgb3 is record
    r, g, b : std_ulogic;
  end record;

  type rgb3_vector is array(natural range <>) of rgb3;

  constant rgb3_black   : rgb3 := ('0', '0', '0');
  constant rgb3_blue    : rgb3 := ('0', '0', '1');
  constant rgb3_red     : rgb3 := ('1', '0', '0');
  constant rgb3_green   : rgb3 := ('0', '1', '0');
  constant rgb3_yellow  : rgb3 := ('1', '1', '0');
  constant rgb3_cyan    : rgb3 := ('0', '1', '1');
  constant rgb3_magenta : rgb3 := ('1', '0', '1');
  constant rgb3_white   : rgb3 := ('1', '1', '1');
  
  function "="(l, r : rgb3) return boolean;
  function "/="(l, r : rgb3) return boolean;
  function "="(l, r : rgb3_vector) return boolean;
  function "/="(l, r : rgb3_vector) return boolean;
  function "and"(l, r : rgb3) return rgb3;
  function "or"(l, r : rgb3) return rgb3;
  function "xor"(l, r : rgb3) return rgb3;
  function "not"(l : rgb3) return rgb3;

  type rgb24 is record
    r, g, b : natural range 0 to 255;
  end record;

  type rgb24_vector is array(natural range <>) of rgb24;

  function "="(l, r : rgb24) return boolean;
  function "/="(l, r : rgb24) return boolean;
  function "="(l, r : rgb24_vector) return boolean;
  function "/="(l, r : rgb24_vector) return boolean;

  constant rgb24_maroon                  : rgb24 := (128,0,0);
  constant rgb24_dark_red                : rgb24 := (139,0,0);
  constant rgb24_brown                   : rgb24 := (165,42,42);
  constant rgb24_firebrick               : rgb24 := (178,34,34);
  constant rgb24_crimson                 : rgb24 := (220,20,60);
  constant rgb24_red                     : rgb24 := (255,0,0);
  constant rgb24_tomato                  : rgb24 := (255,99,71);
  constant rgb24_coral                   : rgb24 := (255,127,80);
  constant rgb24_indian_red              : rgb24 := (205,92,92);
  constant rgb24_light_coral             : rgb24 := (240,128,128);
  constant rgb24_dark_salmon             : rgb24 := (233,150,122);
  constant rgb24_salmon                  : rgb24 := (250,128,114);
  constant rgb24_light_salmon            : rgb24 := (255,160,122);
  constant rgb24_orange_red              : rgb24 := (255,69,0);
  constant rgb24_dark_orange             : rgb24 := (255,140,0);
  constant rgb24_orange                  : rgb24 := (255,165,0);
  constant rgb24_gold                    : rgb24 := (255,215,0);
  constant rgb24_dark_golden_rod         : rgb24 := (184,134,11);
  constant rgb24_golden_rod              : rgb24 := (218,165,32);
  constant rgb24_pale_golden_rod         : rgb24 := (238,232,170);
  constant rgb24_dark_khaki              : rgb24 := (189,183,107);
  constant rgb24_khaki                   : rgb24 := (240,230,140);
  constant rgb24_olive                   : rgb24 := (128,128,0);
  constant rgb24_yellow                  : rgb24 := (255,255,0);
  constant rgb24_yellow_green            : rgb24 := (154,205,50);
  constant rgb24_dark_olive_green        : rgb24 := (85,107,47);
  constant rgb24_olive_drab              : rgb24 := (107,142,35);
  constant rgb24_lawn_green              : rgb24 := (124,252,0);
  constant rgb24_chart_reuse             : rgb24 := (127,255,0);
  constant rgb24_green_yellow            : rgb24 := (173,255,47);
  constant rgb24_dark_green              : rgb24 := (0,100,0);
  constant rgb24_green                   : rgb24 := (0,128,0);
  constant rgb24_forest_green            : rgb24 := (34,139,34);
  constant rgb24_lime                    : rgb24 := (0,255,0);
  constant rgb24_lime_green              : rgb24 := (50,205,50);
  constant rgb24_light_green             : rgb24 := (144,238,144);
  constant rgb24_pale_green              : rgb24 := (152,251,152);
  constant rgb24_dark_sea_green          : rgb24 := (143,188,143);
  constant rgb24_medium_spring_green     : rgb24 := (0,250,154);
  constant rgb24_spring_green            : rgb24 := (0,255,127);
  constant rgb24_sea_green               : rgb24 := (46,139,87);
  constant rgb24_medium_aqua_marine      : rgb24 := (102,205,170);
  constant rgb24_medium_sea_green        : rgb24 := (60,179,113);
  constant rgb24_light_sea_green         : rgb24 := (32,178,170);
  constant rgb24_dark_slate_gray         : rgb24 := (47,79,79);
  constant rgb24_teal                    : rgb24 := (0,128,128);
  constant rgb24_dark_cyan               : rgb24 := (0,139,139);
  constant rgb24_aqua                    : rgb24 := (0,255,255);
  constant rgb24_cyan                    : rgb24 := (0,255,255);
  constant rgb24_light_cyan              : rgb24 := (224,255,255);
  constant rgb24_dark_turquoise          : rgb24 := (0,206,209);
  constant rgb24_turquoise               : rgb24 := (64,224,208);
  constant rgb24_medium_turquoise        : rgb24 := (72,209,204);
  constant rgb24_pale_turquoise          : rgb24 := (175,238,238);
  constant rgb24_aqua_marine             : rgb24 := (127,255,212);
  constant rgb24_powder_blue             : rgb24 := (176,224,230);
  constant rgb24_cadet_blue              : rgb24 := (95,158,160);
  constant rgb24_steel_blue              : rgb24 := (70,130,180);
  constant rgb24_corn_flower_blue        : rgb24 := (100,149,237);
  constant rgb24_deep_sky_blue           : rgb24 := (0,191,255);
  constant rgb24_dodger_blue             : rgb24 := (30,144,255);
  constant rgb24_light_blue              : rgb24 := (173,216,230);
  constant rgb24_sky_blue                : rgb24 := (135,206,235);
  constant rgb24_light_sky_blue          : rgb24 := (135,206,250);
  constant rgb24_midnight_blue           : rgb24 := (25,25,112);
  constant rgb24_navy                    : rgb24 := (0,0,128);
  constant rgb24_dark_blue               : rgb24 := (0,0,139);
  constant rgb24_medium_blue             : rgb24 := (0,0,205);
  constant rgb24_blue                    : rgb24 := (0,0,255);
  constant rgb24_royal_blue              : rgb24 := (65,105,225);
  constant rgb24_blue_violet             : rgb24 := (138,43,226);
  constant rgb24_indigo                  : rgb24 := (75,0,130);
  constant rgb24_dark_slate_blue         : rgb24 := (72,61,139);
  constant rgb24_slate_blue              : rgb24 := (106,90,205);
  constant rgb24_medium_slate_blue       : rgb24 := (123,104,238);
  constant rgb24_medium_purple           : rgb24 := (147,112,219);
  constant rgb24_dark_magenta            : rgb24 := (139,0,139);
  constant rgb24_dark_violet             : rgb24 := (148,0,211);
  constant rgb24_dark_orchid             : rgb24 := (153,50,204);
  constant rgb24_medium_orchid           : rgb24 := (186,85,211);
  constant rgb24_purple                  : rgb24 := (128,0,128);
  constant rgb24_thistle                 : rgb24 := (216,191,216);
  constant rgb24_plum                    : rgb24 := (221,160,221);
  constant rgb24_violet                  : rgb24 := (238,130,238);
  constant rgb24_magenta                 : rgb24 := (255,0,255);
  constant rgb24_fuchsia                 : rgb24 := (255,0,255);
  constant rgb24_orchid                  : rgb24 := (218,112,214);
  constant rgb24_medium_violet_red       : rgb24 := (199,21,133);
  constant rgb24_pale_violet_red         : rgb24 := (219,112,147);
  constant rgb24_deep_pink               : rgb24 := (255,20,147);
  constant rgb24_hot_pink                : rgb24 := (255,105,180);
  constant rgb24_light_pink              : rgb24 := (255,182,193);
  constant rgb24_pink                    : rgb24 := (255,192,203);
  constant rgb24_antique_white           : rgb24 := (250,235,215);
  constant rgb24_beige                   : rgb24 := (245,245,220);
  constant rgb24_bisque                  : rgb24 := (255,228,196);
  constant rgb24_blanched_almond         : rgb24 := (255,235,205);
  constant rgb24_wheat                   : rgb24 := (245,222,179);
  constant rgb24_corn_silk               : rgb24 := (255,248,220);
  constant rgb24_lemon_chiffon           : rgb24 := (255,250,205);
  constant rgb24_light_golden_rod_yellow : rgb24 := (250,250,210);
  constant rgb24_light_yellow            : rgb24 := (255,255,224);
  constant rgb24_saddle_brown            : rgb24 := (139,69,19);
  constant rgb24_sienna                  : rgb24 := (160,82,45);
  constant rgb24_chocolate               : rgb24 := (210,105,30);
  constant rgb24_peru                    : rgb24 := (205,133,63);
  constant rgb24_sandy_brown             : rgb24 := (244,164,96);
  constant rgb24_burly_wood              : rgb24 := (222,184,135);
  constant rgb24_tan                     : rgb24 := (210,180,140);
  constant rgb24_rosy_brown              : rgb24 := (188,143,143);
  constant rgb24_moccasin                : rgb24 := (255,228,181);
  constant rgb24_navajo_white            : rgb24 := (255,222,173);
  constant rgb24_peach_puff              : rgb24 := (255,218,185);
  constant rgb24_misty_rose              : rgb24 := (255,228,225);
  constant rgb24_lavender_blush          : rgb24 := (255,240,245);
  constant rgb24_linen                   : rgb24 := (250,240,230);
  constant rgb24_old_lace                : rgb24 := (253,245,230);
  constant rgb24_papaya_whip             : rgb24 := (255,239,213);
  constant rgb24_sea_shell               : rgb24 := (255,245,238);
  constant rgb24_mint_cream              : rgb24 := (245,255,250);
  constant rgb24_slate_gray              : rgb24 := (112,128,144);
  constant rgb24_light_slate_gray        : rgb24 := (119,136,153);
  constant rgb24_light_steel_blue        : rgb24 := (176,196,222);
  constant rgb24_lavender                : rgb24 := (230,230,250);
  constant rgb24_floral_white            : rgb24 := (255,250,240);
  constant rgb24_alice_blue              : rgb24 := (240,248,255);
  constant rgb24_ghost_white             : rgb24 := (248,248,255);
  constant rgb24_honeydew                : rgb24 := (240,255,240);
  constant rgb24_ivory                   : rgb24 := (255,255,240);
  constant rgb24_azure                   : rgb24 := (240,255,255);
  constant rgb24_snow                    : rgb24 := (255,250,250);
  constant rgb24_black                   : rgb24 := (0,0,0);
  constant rgb24_dim_gray                : rgb24 := (105,105,105);
  constant rgb24_dim_grey                : rgb24 := (105,105,105);
  constant rgb24_gray                    : rgb24 := (128,128,128);
  constant rgb24_grey                    : rgb24 := (128,128,128);
  constant rgb24_dark_gray               : rgb24 := (169,169,169);
  constant rgb24_dark_grey               : rgb24 := (169,169,169);
  constant rgb24_silver                  : rgb24 := (192,192,192);
  constant rgb24_light_gray              : rgb24 := (211,211,211);
  constant rgb24_light_grey              : rgb24 := (211,211,211);
  constant rgb24_gainsboro               : rgb24 := (220,220,220);
  constant rgb24_white_smoke             : rgb24 := (245,245,245);
  constant rgb24_white                   : rgb24 := (255,255,255);

end package color;

package body color is

  function "="(l, r : rgb24) return boolean is
  begin
    return l.r = r.r and l.g = r.g and l.b = r.b;
  end "=";

  function "/="(l, r : rgb24) return boolean is
  begin
    return l.r /= r.r or l.g /= r.g or l.b /= r.b;
  end "/=";

  function "="(l, r : rgb24_vector) return boolean is
    alias lv : rgb24_vector(1 to l'length) is l;
    alias rv : rgb24_vector(1 to r'length) is r;
    variable result : boolean;
  begin
    t: if l'length /= r'length THEN
      assert false
        report "Vectors of differing sizes passed"
        severity failure;
      result := false;
    else
      result := true;
      fe: for i in lv'range loop
        result := result and (lv(i) = rv(i));
      end loop;
    end if;

    return result;
  end "=";

  function "/="(l, r : rgb24_vector) return boolean is
  begin
    return not (l = r);
  end "/=";

  function "="(l, r : rgb3) return boolean is
  begin
    return l.r = r.r and l.g = r.g and l.b = r.b;
  end "=";

  function "/="(l, r : rgb3) return boolean is
  begin
    return l.r /= r.r or l.g /= r.g or l.b /= r.b;
  end "/=";

  function "="(l, r : rgb3_vector) return boolean is
    alias lv : rgb3_vector(1 to l'length) is l;
    alias rv : rgb3_vector(1 to r'length) is r;
    variable result : boolean;
  begin
    t: if l'length /= r'length THEN
      assert false
        report "Vectors of differing sizes passed"
        severity failure;
      result := false;
    else
      result := true;
      fe: for i in lv'range loop
        result := result and (lv(i) = rv(i));
      end loop;
    end if;

    return result;
  end "=";

  function "/="(l, r : rgb3_vector) return boolean is
  begin
    return not (l = r);
  end "/=";

  function "and"(l, r : rgb3) return rgb3 is
  begin
    return rgb3'(r => l.r and r.r,
                 g => l.g and r.g,
                 b => l.b and r.b);
  end "and";

  function "or"(l, r : rgb3) return rgb3 is
  begin
    return rgb3'(r => l.r or r.r,
                 g => l.g or r.g,
                 b => l.b or r.b);
  end "or";

  function "xor"(l, r : rgb3) return rgb3 is
  begin
    return rgb3'(r => l.r xor r.r,
                 g => l.g xor r.g,
                 b => l.b xor r.b);
  end "xor";

  function "not"(l : rgb3) return rgb3 is
  begin
    return l xor rgb3_white;
  end "not";

end package body color;
