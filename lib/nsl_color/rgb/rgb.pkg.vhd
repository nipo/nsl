library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package rgb is

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
    r, g, b : unsigned(7 downto 0);
  end record;

  type rgb24_vector is array(natural range <>) of rgb24;

  function "="(l, r : rgb24) return boolean;
  function "/="(l, r : rgb24) return boolean;
  function "="(l, r : rgb24_vector) return boolean;
  function "/="(l, r : rgb24_vector) return boolean;

  constant rgb24_maroon                  : rgb24 := (x"80",x"00",x"00");
  constant rgb24_dark_red                : rgb24 := (x"8B",x"00",x"00");
  constant rgb24_brown                   : rgb24 := (x"A5",x"2A",x"2A");
  constant rgb24_firebrick               : rgb24 := (x"B2",x"22",x"22");
  constant rgb24_crimson                 : rgb24 := (x"DC",x"14",x"3C");
  constant rgb24_red                     : rgb24 := (x"FF",x"00",x"00");
  constant rgb24_tomato                  : rgb24 := (x"FF",x"63",x"47");
  constant rgb24_coral                   : rgb24 := (x"FF",x"7F",x"50");
  constant rgb24_indian_red              : rgb24 := (x"CD",x"5C",x"5C");
  constant rgb24_light_coral             : rgb24 := (x"F0",x"80",x"80");
  constant rgb24_dark_salmon             : rgb24 := (x"E9",x"96",x"7A");
  constant rgb24_salmon                  : rgb24 := (x"FA",x"80",x"72");
  constant rgb24_light_salmon            : rgb24 := (x"FF",x"A0",x"7A");
  constant rgb24_orange_red              : rgb24 := (x"FF",x"45",x"00");
  constant rgb24_dark_orange             : rgb24 := (x"FF",x"8C",x"00");
  constant rgb24_orange                  : rgb24 := (x"FF",x"A5",x"00");
  constant rgb24_gold                    : rgb24 := (x"FF",x"D7",x"00");
  constant rgb24_dark_golden_rod         : rgb24 := (x"B8",x"86",x"0B");
  constant rgb24_golden_rod              : rgb24 := (x"DA",x"A5",x"20");
  constant rgb24_pale_golden_rod         : rgb24 := (x"EE",x"E8",x"AA");
  constant rgb24_dark_khaki              : rgb24 := (x"BD",x"B7",x"6B");
  constant rgb24_khaki                   : rgb24 := (x"F0",x"E6",x"8C");
  constant rgb24_olive                   : rgb24 := (x"80",x"80",x"00");
  constant rgb24_yellow                  : rgb24 := (x"FF",x"FF",x"00");
  constant rgb24_yellow_green            : rgb24 := (x"9A",x"CD",x"32");
  constant rgb24_dark_olive_green        : rgb24 := (x"55",x"6B",x"2F");
  constant rgb24_olive_drab              : rgb24 := (x"6B",x"8E",x"23");
  constant rgb24_lawn_green              : rgb24 := (x"7C",x"FC",x"00");
  constant rgb24_chart_reuse             : rgb24 := (x"7F",x"FF",x"00");
  constant rgb24_green_yellow            : rgb24 := (x"AD",x"FF",x"2F");
  constant rgb24_dark_green              : rgb24 := (x"00",x"64",x"00");
  constant rgb24_green                   : rgb24 := (x"00",x"80",x"00");
  constant rgb24_forest_green            : rgb24 := (x"22",x"8B",x"22");
  constant rgb24_lime                    : rgb24 := (x"00",x"FF",x"00");
  constant rgb24_lime_green              : rgb24 := (x"32",x"CD",x"32");
  constant rgb24_light_green             : rgb24 := (x"90",x"EE",x"90");
  constant rgb24_pale_green              : rgb24 := (x"98",x"FB",x"98");
  constant rgb24_dark_sea_green          : rgb24 := (x"8F",x"BC",x"8F");
  constant rgb24_medium_spring_green     : rgb24 := (x"00",x"FA",x"9A");
  constant rgb24_spring_green            : rgb24 := (x"00",x"FF",x"7F");
  constant rgb24_sea_green               : rgb24 := (x"2E",x"8B",x"57");
  constant rgb24_medium_aqua_marine      : rgb24 := (x"66",x"CD",x"AA");
  constant rgb24_medium_sea_green        : rgb24 := (x"3C",x"B3",x"71");
  constant rgb24_light_sea_green         : rgb24 := (x"20",x"B2",x"AA");
  constant rgb24_dark_slate_gray         : rgb24 := (x"2F",x"4F",x"4F");
  constant rgb24_teal                    : rgb24 := (x"00",x"80",x"80");
  constant rgb24_dark_cyan               : rgb24 := (x"00",x"8B",x"8B");
  constant rgb24_aqua                    : rgb24 := (x"00",x"FF",x"FF");
  constant rgb24_cyan                    : rgb24 := (x"00",x"FF",x"FF");
  constant rgb24_light_cyan              : rgb24 := (x"E0",x"FF",x"FF");
  constant rgb24_dark_turquoise          : rgb24 := (x"00",x"CE",x"D1");
  constant rgb24_turquoise               : rgb24 := (x"40",x"E0",x"D0");
  constant rgb24_medium_turquoise        : rgb24 := (x"48",x"D1",x"CC");
  constant rgb24_pale_turquoise          : rgb24 := (x"AF",x"EE",x"EE");
  constant rgb24_aqua_marine             : rgb24 := (x"7F",x"FF",x"D4");
  constant rgb24_powder_blue             : rgb24 := (x"B0",x"E0",x"E6");
  constant rgb24_cadet_blue              : rgb24 := (x"5F",x"9E",x"A0");
  constant rgb24_steel_blue              : rgb24 := (x"46",x"82",x"B4");
  constant rgb24_corn_flower_blue        : rgb24 := (x"64",x"95",x"ED");
  constant rgb24_deep_sky_blue           : rgb24 := (x"00",x"BF",x"FF");
  constant rgb24_dodger_blue             : rgb24 := (x"1E",x"90",x"FF");
  constant rgb24_light_blue              : rgb24 := (x"AD",x"D8",x"E6");
  constant rgb24_sky_blue                : rgb24 := (x"87",x"CE",x"EB");
  constant rgb24_light_sky_blue          : rgb24 := (x"87",x"CE",x"FA");
  constant rgb24_midnight_blue           : rgb24 := (x"19",x"19",x"70");
  constant rgb24_navy                    : rgb24 := (x"00",x"00",x"80");
  constant rgb24_dark_blue               : rgb24 := (x"00",x"00",x"8B");
  constant rgb24_medium_blue             : rgb24 := (x"00",x"00",x"CD");
  constant rgb24_blue                    : rgb24 := (x"00",x"00",x"FF");
  constant rgb24_royal_blue              : rgb24 := (x"41",x"69",x"E1");
  constant rgb24_blue_violet             : rgb24 := (x"8A",x"2B",x"E2");
  constant rgb24_indigo                  : rgb24 := (x"4B",x"00",x"82");
  constant rgb24_dark_slate_blue         : rgb24 := (x"48",x"3D",x"8B");
  constant rgb24_slate_blue              : rgb24 := (x"6A",x"5A",x"CD");
  constant rgb24_medium_slate_blue       : rgb24 := (x"7B",x"68",x"EE");
  constant rgb24_medium_purple           : rgb24 := (x"93",x"70",x"DB");
  constant rgb24_dark_magenta            : rgb24 := (x"8B",x"00",x"8B");
  constant rgb24_dark_violet             : rgb24 := (x"94",x"00",x"D3");
  constant rgb24_dark_orchid             : rgb24 := (x"99",x"32",x"CC");
  constant rgb24_medium_orchid           : rgb24 := (x"BA",x"55",x"D3");
  constant rgb24_purple                  : rgb24 := (x"80",x"00",x"80");
  constant rgb24_thistle                 : rgb24 := (x"D8",x"BF",x"D8");
  constant rgb24_plum                    : rgb24 := (x"DD",x"A0",x"DD");
  constant rgb24_violet                  : rgb24 := (x"EE",x"82",x"EE");
  constant rgb24_magenta                 : rgb24 := (x"FF",x"00",x"FF");
  constant rgb24_fuchsia                 : rgb24 := (x"FF",x"00",x"FF");
  constant rgb24_orchid                  : rgb24 := (x"DA",x"70",x"D6");
  constant rgb24_medium_violet_red       : rgb24 := (x"C7",x"15",x"85");
  constant rgb24_pale_violet_red         : rgb24 := (x"DB",x"70",x"93");
  constant rgb24_deep_pink               : rgb24 := (x"FF",x"14",x"93");
  constant rgb24_hot_pink                : rgb24 := (x"FF",x"69",x"B4");
  constant rgb24_light_pink              : rgb24 := (x"FF",x"B6",x"C1");
  constant rgb24_pink                    : rgb24 := (x"FF",x"C0",x"CB");
  constant rgb24_antique_white           : rgb24 := (x"FA",x"EB",x"D7");
  constant rgb24_beige                   : rgb24 := (x"F5",x"F5",x"DC");
  constant rgb24_bisque                  : rgb24 := (x"FF",x"E4",x"C4");
  constant rgb24_blanched_almond         : rgb24 := (x"FF",x"EB",x"CD");
  constant rgb24_wheat                   : rgb24 := (x"F5",x"DE",x"B3");
  constant rgb24_corn_silk               : rgb24 := (x"FF",x"F8",x"DC");
  constant rgb24_lemon_chiffon           : rgb24 := (x"FF",x"FA",x"CD");
  constant rgb24_light_golden_rod_yellow : rgb24 := (x"FA",x"FA",x"D2");
  constant rgb24_light_yellow            : rgb24 := (x"FF",x"FF",x"E0");
  constant rgb24_saddle_brown            : rgb24 := (x"8B",x"45",x"13");
  constant rgb24_sienna                  : rgb24 := (x"A0",x"52",x"2D");
  constant rgb24_chocolate               : rgb24 := (x"D2",x"69",x"1E");
  constant rgb24_peru                    : rgb24 := (x"CD",x"85",x"3F");
  constant rgb24_sandy_brown             : rgb24 := (x"F4",x"A4",x"60");
  constant rgb24_burly_wood              : rgb24 := (x"DE",x"B8",x"87");
  constant rgb24_tan                     : rgb24 := (x"D2",x"B4",x"8C");
  constant rgb24_rosy_brown              : rgb24 := (x"BC",x"8F",x"8F");
  constant rgb24_moccasin                : rgb24 := (x"FF",x"E4",x"B5");
  constant rgb24_navajo_white            : rgb24 := (x"FF",x"DE",x"AD");
  constant rgb24_peach_puff              : rgb24 := (x"FF",x"DA",x"B9");
  constant rgb24_misty_rose              : rgb24 := (x"FF",x"E4",x"E1");
  constant rgb24_lavender_blush          : rgb24 := (x"FF",x"F0",x"F5");
  constant rgb24_linen                   : rgb24 := (x"FA",x"F0",x"E6");
  constant rgb24_old_lace                : rgb24 := (x"FD",x"F5",x"E6");
  constant rgb24_papaya_whip             : rgb24 := (x"FF",x"EF",x"D5");
  constant rgb24_sea_shell               : rgb24 := (x"FF",x"F5",x"EE");
  constant rgb24_mint_cream              : rgb24 := (x"F5",x"FF",x"FA");
  constant rgb24_slate_gray              : rgb24 := (x"70",x"80",x"90");
  constant rgb24_light_slate_gray        : rgb24 := (x"77",x"88",x"99");
  constant rgb24_light_steel_blue        : rgb24 := (x"B0",x"C4",x"DE");
  constant rgb24_lavender                : rgb24 := (x"E6",x"E6",x"FA");
  constant rgb24_floral_white            : rgb24 := (x"FF",x"FA",x"F0");
  constant rgb24_alice_blue              : rgb24 := (x"F0",x"F8",x"FF");
  constant rgb24_ghost_white             : rgb24 := (x"F8",x"F8",x"FF");
  constant rgb24_honeydew                : rgb24 := (x"F0",x"FF",x"F0");
  constant rgb24_ivory                   : rgb24 := (x"FF",x"FF",x"F0");
  constant rgb24_azure                   : rgb24 := (x"F0",x"FF",x"FF");
  constant rgb24_snow                    : rgb24 := (x"FF",x"FA",x"FA");
  constant rgb24_black                   : rgb24 := (x"00",x"00",x"00");
  constant rgb24_dim_gray                : rgb24 := (x"69",x"69",x"69");
  constant rgb24_dim_grey                : rgb24 := (x"69",x"69",x"69");
  constant rgb24_gray                    : rgb24 := (x"80",x"80",x"80");
  constant rgb24_grey                    : rgb24 := (x"80",x"80",x"80");
  constant rgb24_dark_gray               : rgb24 := (x"A9",x"A9",x"A9");
  constant rgb24_dark_grey               : rgb24 := (x"A9",x"A9",x"A9");
  constant rgb24_silver                  : rgb24 := (x"C0",x"C0",x"C0");
  constant rgb24_light_gray              : rgb24 := (x"D3",x"D3",x"D3");
  constant rgb24_light_grey              : rgb24 := (x"D3",x"D3",x"D3");
  constant rgb24_gainsboro               : rgb24 := (x"DC",x"DC",x"DC");
  constant rgb24_white_smoke             : rgb24 := (x"F5",x"F5",x"F5");
  constant rgb24_white                   : rgb24 := (x"FF",x"FF",x"FF");

  function rgb24_to_suv(color: rgb24;
                        lsb_right: boolean := true;
                        color_order: string := "RGB") return std_ulogic_vector;

  function rgb24_from_suv(color: std_ulogic_vector;
                          lsb_right: boolean := true;
                          color_order: string := "RGB") return rgb24;

  function to_rgb24(r, g, b : real) return rgb24;

  -- h : angle (radians)
  -- s : [0..1]
  -- v : [0..1]
  function rgb24_from_hsv(h, s, v : real) return rgb24;
  
end package rgb;

package body rgb is

  function bit_reverse(i : std_ulogic_vector) return std_ulogic_vector is
    constant w : natural := i'length;
    alias iv : std_ulogic_vector(w-1 downto 0) is i;
    variable ret : std_ulogic_vector(0 to w-1);
  begin
    bits: for i in 0 to w-1
    loop
      ret(i) := iv(i);
    end loop;
    return ret;
  end bit_reverse;

  function rgb24_to_suv_lsb_right(color: rgb24;
                                  color_order: string := "RGB")
    return std_ulogic_vector is
    variable a, b, c : unsigned(7 downto 0);
    variable ret : unsigned(23 downto 0);
  begin
    case color_order(1) is
      when 'R' => a := color.r;
      when 'G' => a := color.g;
      when others => a := color.b;
    end case;
    case color_order(2) is
      when 'R' => b := color.r;
      when 'G' => b := color.g;
      when others => b := color.b;
    end case;
    case color_order(3) is
      when 'R' => c := color.r;
      when 'G' => c := color.g;
      when others => c := color.b;
    end case;

    ret(23 downto 16) := a;
    ret(15 downto 8) := b;
    ret(7 downto 0) := c;

    return std_ulogic_vector(ret);
  end rgb24_to_suv_lsb_right;

  function rgb24_from_suv_lsb_right(color: std_ulogic_vector;
                                    color_order: string := "RGB") return rgb24
  is
    alias rc : std_ulogic_vector(color'length-1 downto 0) is color;
    variable ret: rgb24 := rgb24_black;
  begin
    if color'length /= 24 then
      assert false
        report "RGB24 from suv only works for vector of length 24, returning black"
        severity warning;
      return ret;
    end if;

    case color_order(1) is
      when 'R' => ret.r := unsigned(rc(23 downto 16));
      when 'G' => ret.g := unsigned(rc(23 downto 16));
      when others => ret.b := unsigned(rc(23 downto 16));
    end case;

    case color_order(2) is
      when 'R' => ret.r := unsigned(rc(15 downto 8));
      when 'G' => ret.g := unsigned(rc(15 downto 8));
      when others => ret.b := unsigned(rc(15 downto 8));
    end case;

    case color_order(3) is
      when 'R' => ret.r := unsigned(rc(7 downto 0));
      when 'G' => ret.g := unsigned(rc(7 downto 0));
      when others => ret.b := unsigned(rc(7 downto 0));
    end case;

    return ret;
  end function;
  
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
  
  function rgb24_to_suv(color: rgb24;
                        lsb_right : boolean := true;
                        color_order: string := "RGB")
    return std_ulogic_vector is
    variable color_order_swapped : string(1 to 3);
  begin
    if lsb_right then
      return rgb24_to_suv_lsb_right(color, color_order);
    else
      color_order_swapped(1) := color_order(3);
      color_order_swapped(2) := color_order(2);
      color_order_swapped(3) := color_order(1);
      return bit_reverse(rgb24_to_suv_lsb_right(color, color_order_swapped));
    end if;
  end rgb24_to_suv;

  function rgb24_from_suv(color: std_ulogic_vector;
                          lsb_right: boolean := true;
                          color_order: string := "RGB") return rgb24
  is
    variable color_order_swapped : string(1 to 3);
  begin
    if lsb_right then
      return rgb24_from_suv_lsb_right(color, color_order);
    else
      color_order_swapped(1) := color_order(3);
      color_order_swapped(2) := color_order(2);
      color_order_swapped(3) := color_order(1);
      return rgb24_from_suv_lsb_right(bit_reverse(color), color_order_swapped);
    end if;
  end function;

  function realminmax(x, v, y : real) return real
  is
  begin
    return realmin(realmax(x, v), y);
  end function;

  function to_rgb24(r, g, b : real) return rgb24
  is
    variable ret : rgb24;
  begin
    ret.r := to_unsigned(integer(realminmax(0.0, r, 1.0) * 255.0), 8);
    ret.g := to_unsigned(integer(realminmax(0.0, g, 1.0) * 255.0), 8);
    ret.b := to_unsigned(integer(realminmax(0.0, b, 1.0) * 255.0), 8);

    return ret;
  end function;

  function rgb24_from_hsv(h, s, v : real) return rgb24
  is
    variable ar, ag, ab, hr, hg, hb : real;
    variable sr, vr : real;
  begin
    ar := h / math_pi mod 2.0 - 1.0;
    ag := (h + math_pi * 4.0 / 3.0) / math_pi mod 2.0 - 1.0;
    ab := (h + math_pi * 2.0 / 3.0) / math_pi mod 2.0 - 1.0;
    hr := realminmax(0.0, -1.0 + abs(ar) * 3.0, 1.0);
    hg := realminmax(0.0, -1.0 + abs(ag) * 3.0, 1.0);
    hb := realminmax(0.0, -1.0 + abs(ab) * 3.0, 1.0);

    sr := realminmax(0.0, s, 1.0);
    vr := realminmax(0.0, v, 1.0);
    hr := hr * s + (1.0 - s);
    hg := hg * s + (1.0 - s);
    hb := hb * s + (1.0 - s);

    return to_rgb24(hr * v, hg * v, hb * v);
  end function;

end package body rgb;
