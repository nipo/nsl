library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic;
use nsl_logic.logic.popcnt;
use nsl_logic.bool.to_logic;
use nsl_logic.bool.if_else;
use work.ibm_8b10b.all;

-- 8b/10b codec implemented in a way suitable for pipelining.  It
-- features classification methods for 3b/4b, 5b/6b, 6b/5b, 4b/3b
-- codes, and merge function suitable for implementing the full 8b/10b
-- coding.
--
-- Decoder has an optional strictness:
--
-- - In strict version, all disparity errors and all coding errors are
--   asserted.
--
-- - In non-strict version, some undefined yet valid codes are
--   accepted. For instance, spec requires to use D/K.y.A7 encoding in
--   some conditions, even if D.x.P7 still abides run length and
--   disparity constraints. Moreover, disparity is only checked at
--   symbol 'i' and 'j' boundaries (disparity after symbol 'c' is not
--   checked, for instance).
package ibm_8b10b_logic is

  procedure encode(
    data_i      : in data_t;
    disparity_i : in std_ulogic;

    data_o      : out code_word_t;
    disparity_o : out std_ulogic
    );

  procedure decode(
    data_i      : in code_word_t;
    disparity_i : in std_ulogic;

    data_o            : out data_t;
    disparity_o       : out std_ulogic;
    code_error_o      : out std_ulogic;
    disparity_error_o : out std_ulogic;

    strict_c : boolean := true
    );

  type classification_3b4b_t is
  record
    has_alternate, d_changes : boolean;
    assumed_disp : std_ulogic;
    data : std_ulogic_vector(9 downto 6);
    is7: boolean;
  end record;

  type classification_5b6b_t is
  record
    d_changes, has_alternate: boolean;
    assumed_disp: std_ulogic;
    data : std_ulogic_vector(5 downto 0);
  end record;

  type encoded_8b10b_t is
  record
    data : code_word_t;
    rd : std_ulogic;
  end record;
    
  function classify_3b4b(data_i: in std_ulogic_vector(7 downto 5);
                         control_i: in std_ulogic)
    return classification_3b4b_t;

  function classify_5b6b(data_i: in std_ulogic_vector(4 downto 0);
                         control_i: in std_ulogic)
    return classification_5b6b_t;

  function merge_8b10b(disparity_i : in std_ulogic;
                           control_i    : in std_ulogic;
                           cl5 : classification_5b6b_t;
                           cl3 : classification_3b4b_t)
    return encoded_8b10b_t;

  type classification_4b3b_t is
  record
    valid: boolean;
    data: std_ulogic_vector(7 downto 5);
    d_changes: std_ulogic;
  end record;

  type classification_6b5b_t is
  record
    valid: boolean;
    data: std_ulogic_vector(4 downto 0);
    d_changes: std_ulogic;
  end record;

  type decoded_10b8b_t is
  record
    data            : data_t;
    disparity       : std_ulogic;
    code_error      : std_ulogic;
    disparity_error : std_ulogic;
  end record;

  type classification_10b8b_t is
  record
    k, k28 : boolean;
    c6_0, c6_1: classification_6b5b_t;
    c4_0_0, c4_0_1, c4_1_1, c4_1_0: classification_4b3b_t;
    p: integer range 0 to 4;
    p6: integer range 0 to 6;
    p3: integer range 0 to 3;
    p8: integer range 0 to 8;
    p4: integer range 0 to 4;
    is_y7_pri: boolean;
    is_y7_alt: boolean;
  end record;

  function classify_4b3b(data_i : in std_ulogic_vector(9 downto 6);
                         k_i : in boolean;
                         disp_i : in std_ulogic) return classification_4b3b_t;
  function classify_6b5b(data_i : in std_ulogic_vector(5 downto 0);
                         k_i : in boolean) return classification_6b5b_t;

  function classify_10b8b(data_i : in code_word_t)
    return classification_10b8b_t;

  function merge_10b8b(
    data_i : code_word_t;
    disparity_i : std_ulogic;
    classif_i : classification_10b8b_t;
    strict_c : boolean := true)
    return decoded_10b8b_t;

end package;

package body ibm_8b10b_logic is

  type decoder_8b10b_classification_t is
  record
    p : integer range 0 to 4;
    k : boolean;
  end record;
  
  function decoder_8b10b_classify(data_i : in code_word_t) return decoder_8b10b_classification_t
  is
    variable p : integer range 0 to 4;
    variable k : boolean;
  begin
    p := popcnt(data_i(3 downto 0));
    k := std_match(data_i, "----1111--") -- (c=d=e=i=1)
         or std_match(data_i, "----0000--") -- (c=d=e=i=0)
         or (p = 1 and std_match(data_i, "111-10----")) -- P13.e'.i.g.h.j
         or (p = 3 and std_match(data_i, "000-01----")); -- P31.e.i'.g'.h'.j'

    return (
      p => p,
      k => k
      );
  end function;

  function classify_4b3b(data_i : in std_ulogic_vector(9 downto 6);
                            k_i : in boolean;
                            disp_i : in std_ulogic) return classification_4b3b_t
  is
    variable tmp: std_ulogic_vector(5 downto 0);
  begin
    tmp := to_logic(k_i) & disp_i & data_i;
    case tmp is
      when "010010" | "110010" => return (true, "000", '1');  -- D/K.x.0
      when "001101" | "101101" => return (true, "000", '1');  -- D/K.x.0
      when "001001"            => return (true, "001", '0');  -- D.x.1
      when "011001"            => return (true, "001", '0');  -- D.x.1
      when "100110"            => return (true, "001", '0');  -- K.28.1
      when "110110"            => return (true, "110", '0');  -- K.28.6
      when "001010"            => return (true, "010", '0');  -- D.x.2
      when "011010"            => return (true, "010", '0');  -- D.x.2
      when "110101"            => return (true, "101", '0');  -- K.28.5
      when "100101"            => return (true, "010", '0');  -- K.28.2
      when "000011" | "100011" => return (true, "011", '0');  -- D/K.x.3
      when "011100" | "111100" => return (true, "011", '0');  -- D/K.x.3
      when "010100" | "110100" => return (true, "100", '1');  -- D/K.x.4
      when "001011" | "101011" => return (true, "100", '1');  -- D/K.x.4
      when "010101"            => return (true, "101", '0');  -- D.x.5
      when "000101"            => return (true, "101", '0');  -- D.x.5
      when "111010"            => return (true, "010", '0');  -- K.28.2
      when "101010"            => return (true, "101", '0');  -- K.28.5
      when "010110"            => return (true, "110", '0');  -- D.x.6
      when "000110"            => return (true, "110", '0');  -- D.x.6
      when "111001"            => return (true, "001", '0');  -- K.28.1
      when "101001"            => return (true, "110", '0');  -- K.28.6
      when "000111"            => return (true, "111", '1');  -- D.x.7
      when "011000"            => return (true, "111", '1');  -- D.x.7
      when "001110" | "101110" => return (true, "111", '1');  -- D/K.x.7
      when "010001" | "110001" => return (true, "111", '1');  -- D/K.x.7
      when others              => return (false, "---", '1');
    end case;
  end function;

  function classify_6b5b(data_i : in std_ulogic_vector(5 downto 0);
                            k_i : in boolean) return classification_6b5b_t
  is
    variable tmp: std_ulogic_vector(6 downto 0);
  begin
    tmp := to_logic(k_i) & data_i;
    case tmp is
      when "0000110"             => return (true, "00000", '1');  -- D.0.y
      when "0111001"             => return (true, "00000", '1');  -- D.0.y
      when "0010001"             => return (true, "00001", '1');  -- D.1.y
      when "0101110"             => return (true, "00001", '1');  -- D.1.y
      when "0010010"             => return (true, "00010", '1');  -- D.2.y
      when "0101101"             => return (true, "00010", '1');  -- D.2.y
      when "0100011"             => return (true, "00011", '0');  -- D.3.y
      when "0010100"             => return (true, "00100", '1');  -- D.4.y
      when "0101011"             => return (true, "00100", '1');  -- D.4.y
      when "0100101"             => return (true, "00101", '0');  -- D.5.y
      when "0100110"             => return (true, "00110", '0');  -- D.6.y
      when "0000111"             => return (true, "00111", '0');  -- D.7.y
      when "0111000"             => return (true, "00111", '0');  -- D.7.y
      when "0011000"             => return (true, "01000", '1');  -- D.8.y
      when "0100111"             => return (true, "01000", '1');  -- D.8.y
      when "0101001"             => return (true, "01001", '0');  -- D.9.y
      when "0101010"             => return (true, "01010", '0');  -- D.10.y
      when "0001011"             => return (true, "01011", '0');  -- D.11.y
      when "0101100"             => return (true, "01100", '0');  -- D.12.y
      when "0001101"             => return (true, "01101", '0');  -- D.13.y
      when "0001110"             => return (true, "01110", '0');  -- D.14.y
      when "0000101"             => return (true, "01111", '1');  -- D.15.y
      when "0111010"             => return (true, "01111", '1');  -- D.15.y
      when "0110110"             => return (true, "10000", '1');  -- D.16.y
      when "0001001"             => return (true, "10000", '1');  -- D.16.y
      when "0110001"             => return (true, "10001", '0');  -- D.17.y
      when "0110010"             => return (true, "10010", '0');  -- D.18.y
      when "0010011"             => return (true, "10011", '0');  -- D.19.y
      when "0110100"             => return (true, "10100", '0');  -- D.20.y
      when "0010101"             => return (true, "10101", '0');  -- D.21.y
      when "0010110"             => return (true, "10110", '0');  -- D.22.y
      when "0010111" | "1010111" => return (true, "10111", '1');  -- D/K.23.y
      when "0101000" | "1101000" => return (true, "10111", '1');  -- D/K.23.y
      when "0001100"             => return (true, "11000", '1');  -- D.24.y
      when "0110011"             => return (true, "11000", '1');  -- D.24.y
      when "0011001"             => return (true, "11001", '0');  -- D.25.y
      when "0011010"             => return (true, "11010", '0');  -- D.26.y
      when "0011011" | "1011011" => return (true, "11011", '1');  -- D/K.27.y
      when "0100100" | "1100100" => return (true, "11011", '1');  -- D/K.27.y
      when "0011100"             => return (true, "11100", '0');  -- D.28.y
      when "1111100"             => return (true, "11100", '1');  -- K.28.y
      when "1000011"             => return (true, "11100", '1');  -- K.28.y
      when "0011101" | "1011101" => return (true, "11101", '1');  -- D/K.29.y
      when "0100010" | "1100010" => return (true, "11101", '1');  -- D/K.29.y
      when "0011110" | "1011110" => return (true, "11110", '1');  -- D/K.30.y
      when "0100001" | "1100001" => return (true, "11110", '1');  -- D/K.30.y
      when "0110101"             => return (true, "11111", '1');  -- D.31.y
      when "0001010"             => return (true, "11111", '1');  -- D.31.y

      when "0000000" | "1000000" => return (false, "-----", '1');
      when "0000001" | "1000001" => return (false, "-----", '1');
      when "0000010" | "1000010" => return (false, "-----", '1');
      when "0000100" | "1000100" => return (false, "-----", '1');
      when "0001000" | "1001000" => return (false, "-----", '1');
      when "0001111" | "1001111" => return (false, "-----", '1');
      when "0010000" | "1010000" => return (false, "-----", '1');
      when "0011111" | "1011111" => return (false, "-----", '1');
      when "0100000" | "1100000" => return (false, "-----", '1');
      when "0101111" | "1101111" => return (false, "-----", '1');
      when "0110000" | "1110000" => return (false, "-----", '1');
      when "0110111" | "1110111" => return (false, "-----", '1');
      when "0111011" | "1111011" => return (false, "-----", '1');
      when "0111101" | "1111101" => return (false, "-----", '1');
      when "0111110" | "1111110" => return (false, "-----", '1');
      when "0111111" | "1111111" => return (false, "-----", '1');

      when others                => return (false, "-----", '-');
    end case;
  end function;

  function classify_10b8b(data_i : in code_word_t)
    return classification_10b8b_t
  is
    variable ret : classification_10b8b_t;
  begin
    ret.p := popcnt(data_i(3 downto 0));
    ret.p6 := popcnt(data_i(5 downto 0));
    ret.p4 := popcnt(data_i(9 downto 6));
    ret.p3 := popcnt(data_i(2 downto 0));
    ret.p8 := popcnt(data_i(7 downto 0));

    ret.k := std_match(data_i, "----1111--") -- (c=d=e=i=1)
             or std_match(data_i, "----0000--") -- (c=d=e=i=0)
             or (ret.p = 1 and std_match(data_i, "111-10----")) -- P13.e'.i.g.h.j
             or (ret.p = 3 and std_match(data_i, "000-01----")); -- P31.e.i'.g'.h'.j'
    ret.k28 := std_match(data_i, "----111100") or std_match(data_i, "----000011");

    ret.c6_0 := classify_6b5b(data_i(5 downto 0), false);
    ret.c6_1 := classify_6b5b(data_i(5 downto 0), true);
    ret.c4_0_0 := classify_4b3b(data_i(9 downto 6), false, '0');
    ret.c4_0_1 := classify_4b3b(data_i(9 downto 6), false, '1');
    ret.c4_1_1 := classify_4b3b(data_i(9 downto 6), true, '1');
    ret.c4_1_0 := classify_4b3b(data_i(9 downto 6), true, '0');

    ret.is_y7_pri := data_i(9 downto 6) = "1000" or data_i(9 downto 6) = "0111";
    ret.is_y7_alt := data_i(9 downto 6) = "1110" or data_i(9 downto 6) = "0001";

    return ret;
  end function;

  function merge_10b8b(
    data_i : code_word_t;
    disparity_i : std_ulogic;
    classif_i : classification_10b8b_t;
    strict_c : boolean := true)
    return decoded_10b8b_t
  is
    variable ret : decoded_10b8b_t;
    variable c4b3b: classification_4b3b_t;
    variable c6b5b: classification_6b5b_t;
    variable disp_mid: std_ulogic;
    variable use_y7_alt: boolean;
  begin
    if classif_i.k then
      c6b5b := classif_i.c6_1;
    else
      c6b5b := classif_i.c6_0;
    end if;

    disp_mid := disparity_i xor c6b5b.d_changes;

    if disp_mid = '0' then
      if classif_i.k28 then
        c4b3b := classif_i.c4_1_0;
      else
        c4b3b := classif_i.c4_0_0;
      end if;
    else
      if classif_i.k28 then
        c4b3b := classif_i.c4_1_1;
      else
        c4b3b := classif_i.c4_0_1;
      end if;
    end if;

    use_y7_alt := ((disp_mid = '0' and data_i(5 downto 4) = "11")
                  or (disp_mid = '1' and data_i(5 downto 4) = "00")
                  or classif_i.k) and (classif_i.is_y7_alt or classif_i.is_y7_pri);
    
    ret.data.data := c4b3b.data & c6b5b.data;
    ret.disparity := disparity_i xor to_logic((c6b5b.d_changes xor c4b3b.d_changes) = '1');
    ret.data.control := to_logic(classif_i.k);

    if strict_c then
      ret.disparity_error := to_logic(
        (disparity_i = '1' and classif_i.p6 > 3)
        or (disparity_i = '0' and classif_i.p6 < 3)
        or classif_i.p6 = 0 or classif_i.p6 = 1 or classif_i.p6 = 5 or classif_i.p6 = 6
        or (disp_mid = '1' and classif_i.p4 > 2)
        or (disp_mid = '0' and classif_i.p4 < 2)
        or (disparity_i = '1' and classif_i.p3 = 3)
        or (disparity_i = '0' and classif_i.p3 = 0)
        or (disparity_i = '1' and classif_i.p8 = 5)
        or (disparity_i = '0' and classif_i.p8 = 6)
        or (disparity_i = '0' and classif_i.p8 = 3)
        or (disparity_i = '1' and classif_i.p8 = 2)
        or classif_i.p4 = 0 or classif_i.p4 = 4);
      ret.code_error := to_logic(
        (not c4b3b.valid or not c6b5b.valid)
        or (disparity_i = '1' and classif_i.p3 = 3)
        or (disparity_i = '0' and classif_i.p3 = 0)
        or (classif_i.is_y7_alt /= use_y7_alt)
        );
    else
      ret.disparity_error := to_logic(
        (disparity_i = '1' and classif_i.p6 > 3)
        or (disparity_i = '0' and classif_i.p6 < 3)
        or classif_i.p6 = 0 or classif_i.p6 = 1 or classif_i.p6 = 5 or classif_i.p6 = 6
        or (disp_mid = '1' and classif_i.p4 > 2)
        or (disp_mid = '0' and classif_i.p4 < 2)
        or classif_i.p4 = 0 or classif_i.p4 = 4);
      ret.code_error := to_logic(not c4b3b.valid or not c6b5b.valid);
    end if;

    if ret.disparity_error = '1' then
      ret.disparity := '0';
    end if;

    return ret;
  end function;
  
  procedure decode(
    data_i : in code_word_t;
    disparity_i : in std_ulogic;

    data_o            : out data_t;
    disparity_o       : out std_ulogic;
    code_error_o      : out std_ulogic;
    disparity_error_o : out std_ulogic;

    strict_c : boolean := true)
  is
    constant c : classification_10b8b_t := classify_10b8b(data_i);
    constant r : decoded_10b8b_t := merge_10b8b(data_i, disparity_i, c, strict_c);
  begin
    data_o := r.data;
    disparity_o := r.disparity;
    code_error_o := r.code_error;
    disparity_error_o := r.disparity_error;
  end procedure;

  function classify_3b4b(data_i: in std_ulogic_vector(7 downto 5);
                             control_i: in std_ulogic)
    return classification_3b4b_t
  is
    variable dc : std_ulogic_vector(3 downto 0);
    variable ret : classification_3b4b_t;
  begin
    dc := data_i & control_i;
    ret.is7 := false;
    case dc is
      when "0000" | "0001" | "1000" | "1001" =>
        ret.assumed_disp := '1';
        ret.has_alternate := true;
        ret.d_changes := true;
      when "0110" | "0111" =>
        ret.assumed_disp := '0';
        ret.has_alternate := true;
        ret.d_changes := false;
      when "1110" | "1111" =>
        ret.assumed_disp := '0';
        ret.has_alternate := true;
        ret.d_changes := true;
        ret.is7 := true;
      when "0011" | "0101" | "1011" | "1101" =>
        ret.assumed_disp := '1';
        ret.has_alternate := true;
        ret.d_changes := false;
      when others =>
        ret.assumed_disp := '-';
        ret.has_alternate := false;
        ret.d_changes := false;
    end case;
    
    ret.data(6) := data_i(5);
    ret.data(7) := data_i(6) or to_logic(data_i = "000");
    ret.data(8) := data_i(7);
    ret.data(9) := ((data_i(5) xor data_i(6)) and not data_i(7));

    return ret;
  end function;

  function classify_5b6b(data_i: in std_ulogic_vector(4 downto 0);
                             control_i: in std_ulogic)
    return classification_5b6b_t
  is
    variable l: integer range 0 to 4;
    variable has_alternate, assumed_disp, d24: std_ulogic;
    variable ret : classification_5b6b_t;
  begin
    l := popcnt(data_i(3 downto 0));
    d24 := to_logic(data_i = "11000");

    case data_i is
      when "00000" | "00001" | "00010" | "00100"
        | "01000" | "01111" | "11000" =>
        ret.assumed_disp := '1';
        ret.has_alternate := true;
      when "00111" | "10000" | "10111" | "11011"
        | "11101" | "11110" | "11111" =>
        ret.assumed_disp := '0';
        ret.has_alternate := true;
      when "11100" =>
        ret.assumed_disp := '0';
        ret.has_alternate := control_i = '1';
      when others =>
        ret.assumed_disp := '-';
        ret.has_alternate := false;
    end case;

    ret.d_changes := ret.has_alternate and data_i /= "00111";

    ret.data(0) := data_i(0);
    ret.data(1) := (data_i(1) and not to_logic(l = 4)) or to_logic(l = 0);
    ret.data(2) := data_i(2) or to_logic(l = 0) or (not data_i(0) and not data_i(1) and data_i(4));
    ret.data(3) := data_i(3) and not to_logic(l = 4);
    ret.data(4) := (data_i(4) or to_logic(l = 1)) and not d24;
    ret.data(5) := (control_i or (to_logic(l = 3) and data_i(4)))
               xor data_i(4) xor to_logic(l = 2) xor d24;

    return ret;
  end function;

  function merge_8b10b(disparity_i : in std_ulogic;
                           control_i    : in std_ulogic;
                           cl5 : classification_5b6b_t;
                           cl3 : classification_3b4b_t) return encoded_8b10b_t
  is
    variable d5: std_ulogic := disparity_i xor to_logic(cl5.d_changes);
    variable ret: encoded_8b10b_t;
  begin
    ret.rd := disparity_i xor to_logic(cl5.d_changes) xor to_logic(cl3.d_changes);
    ret.data(5 downto 0) := cl5.data;
    
    if cl5.has_alternate and (cl5.assumed_disp /= disparity_i) then
      ret.data(5 downto 0) := not ret.data(5 downto 0);
    end if;

    if cl3.is7 and ((ret.data(5) = ret.data(4) and ret.data(4) /= d5) or control_i = '1') then
      ret.data(9 downto 6) := "1110";
    else
      ret.data(9 downto 6) := cl3.data;
    end if;

    if cl3.has_alternate and (cl3.assumed_disp /= d5) then
      ret.data(9 downto 6) := not ret.data(9 downto 6);
    end if;

    return ret;
  end function;
  
  procedure encode(
    data_i : in data_t;
    disparity_i : in std_ulogic;

    data_o : out code_word_t;
    disparity_o : out std_ulogic)
  is
    constant cl5 : classification_5b6b_t := classify_5b6b(data_i.data(4 downto 0), data_i.control);
    constant cl3 : classification_3b4b_t := classify_3b4b(data_i.data(7 downto 5), data_i.control);
    constant ret : encoded_8b10b_t := merge_8b10b(disparity_i, data_i.control, cl5, cl3);
  begin
    disparity_o := ret.rd;
    data_o := ret.data;
  end procedure;

end package body;
