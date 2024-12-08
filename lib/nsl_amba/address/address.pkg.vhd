library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.text.all;

package address is

  -- Arbitrary
  constant max_address_width_c: natural := 64;
  subtype address_t is unsigned(max_address_width_c - 1 downto 0);
  type address_vector is array (natural range <>) of address_t;

  -- Parse an address. Address may contain don't care bits ('-').
  -- Moreover, a mask may be added after the address to ignore LSBs
  -- (by specifying count of useful bits).
  --
  -- Address may be either:
  -- - a binary string, it can be either a bit value (MSB first) or a
  --   VHDL hex value (e.g. x"1234", in such case, this helper will
  --   receive binary string). Bit literal may contain '-'.
  -- - a hex string, prefixed by x like "x1234". In such case, '-' in
  --   the string marks a full nibble as don't care.
  --
  -- After address, a mask in the form "/n" with n a number of bits
  -- can be added.
  --
  -- Examples:
  -- - x"dead0000" is x"dead0000"
  -- - "xdead0000" is x"dead0000"
  -- - "xdead00--" is x"dead00"&"--------"
  -- - "xdead0000/24" is x"dead00"&"--------"
  function address_parse(width: natural; addr:string) return address_t;

  -- Create an array of addresses from 1 to 16 items in length.
  -- First null string in arguments d1 to d15 marks the end of the
  -- array.
  function routing_table(width: natural;
                         d0:string;
                         d1, d2, d3, d4, d5, d6, d7,
                         d8, d9, d10, d11, d12, d13, d14, d15: string := "") return address_vector;
  function routing_table_lookup(width: natural;
                                rt: address_vector;
                                address: unsigned;
                                default: natural := 0) return natural;

  function routing_table_matches_entry(width: natural;
                                       rt: address_vector;
                                       address: unsigned;
                                       index: natural) return boolean;
  
end package;

package body address is

  function nibble_parse(nibble: character) return unsigned
  is
  begin
    case nibble is
      when '0' => return x"0";
      when '1' => return x"1";
      when '2' => return x"2";
      when '3' => return x"3";
      when '4' => return x"4";
      when '5' => return x"5";
      when '6' => return x"6";
      when '7' => return x"7";
      when '8' => return x"8";
      when '9' => return x"9";
      when 'a'|'A' => return x"a";
      when 'b'|'B' => return x"b";
      when 'c'|'C' => return x"c";
      when 'd'|'D' => return x"d";
      when 'e'|'E' => return x"e";
      when 'f'|'F' => return x"f";
      when '-' => return "----";
      when others => return "XXXX";
    end case;
  end function;

  function bin_address_parse(width: natural; addr:string) return address_t
  is
    alias bits: string(addr'length-1 downto 0) is addr;
    variable b: character;
    variable ret : address_t := (others => '0');
  begin
    for i in bits'left downto bits'right
    loop
      b := bits(i);

      case b is
        when '0' => ret := ret(ret'high-1 downto 0) & '0';
        when '1' => ret := ret(ret'high-1 downto 0) & '1';
        when '-' => ret := ret(ret'high-1 downto 0) & '-';
        when '_' | ' ' =>  next;
        when others =>
          assert false
            report "Bad character '"&b&"' in address, ignored"
            severity warning;
      end case;
    end loop;
    ret(ret'high downto width) := (others => '-');
    return ret;
  end function;

  function hex_address_parse(width: natural; addr:string) return address_t
  is
    alias nibbles: string(addr'length downto 1) is addr;
    variable nibble: character;
    variable ret : address_t := (others => '0');
  begin
    for i in nibbles'left downto nibbles'right
    loop
      nibble := nibbles(i);
      if nibble = '_' or nibble = ' ' then
        next;
      end if;
      ret := ret(ret'high-4 downto 0) & nibble_parse(nibble);
    end loop;
    ret(ret'high downto width) := (others => '-');
    return ret;
  end function;

  function address_parse(width: natural; addr:string) return address_t
  is
    variable ret : address_t := (others => '-');
    variable slash_index : integer := -1;
    variable start : integer := 0;
    variable stop : integer := addr'length;
    variable hex_mode : boolean := false;
    variable ignored_lsbs : integer := 0;
    alias a : string(1 to addr'length) is addr;
  begin
    slash_index := strchr(addr, '/');
    if slash_index >= 0 then
      stop := slash_index;
      ignored_lsbs := width - integer'value(a(slash_index+2 to a'right));
    end if;
    
    if a(1) = 'x' then
      ret := hex_address_parse(width, a(2 to stop));
    else
      ret := bin_address_parse(width, a(1 to stop));
    end if;

    if ignored_lsbs /= 0 then
      ret(ignored_lsbs-1 downto 0) := (others => '-');
    end if;

    ret(ret'high downto width) := (others => '-');

    return ret;
  end function;
  
  function routing_table(width: natural;
                         d0: string;
                         d1, d2, d3, d4, d5, d6, d7,
                         d8, d9, d10, d11, d12, d13, d14, d15: string := "") return address_vector
  is
    variable ret: address_vector(0 to 15) := (others => (others => '-'));
  begin
    ret(0) := address_parse(width, d0);
    if d1'length = 0 then return ret(0 to 0); end if;
    ret(1) := address_parse(width, d1);
    if d2'length = 0 then return ret(0 to 1); end if;
    ret(2) := address_parse(width, d2);
    if d3'length = 0 then return ret(0 to 2); end if;
    ret(3) := address_parse(width, d3);
    if d4'length = 0 then return ret(0 to 3); end if;
    ret(4) := address_parse(width, d4);
    if d5'length = 0 then return ret(0 to 4); end if;
    ret(5) := address_parse(width, d5);
    if d6'length = 0 then return ret(0 to 5); end if;
    ret(6) := address_parse(width, d6);
    if d7'length = 0 then return ret(0 to 6); end if;
    ret(7) := address_parse(width, d7);
    if d8'length = 0 then return ret(0 to 7); end if;
    ret(8) := address_parse(width, d8);
    if d9'length = 0 then return ret(0 to 8); end if;
    ret(9) := address_parse(width, d9);
    if d10'length = 0 then return ret(0 to 9); end if;
    ret(10) := address_parse(width, d10);
    if d11'length = 0 then return ret(0 to 10); end if;
    ret(11) := address_parse(width, d11);
    if d12'length = 0 then return ret(0 to 11); end if;
    ret(12) := address_parse(width, d12);
    if d13'length = 0 then return ret(0 to 12); end if;
    ret(13) := address_parse(width, d13);
    if d14'length = 0 then return ret(0 to 13); end if;
    ret(14) := address_parse(width, d14);
    if d15'length = 0 then return ret(0 to 14); end if;
    ret(15) := address_parse(width, d15);
    return ret(0 to 15);
  end function;

  function routing_table_lookup(width: natural;
                                rt: address_vector;
                                address: unsigned;
                                default: natural := 0) return natural
  is
    alias rtx: address_vector(0 to rt'length-1) is rt;
  begin
    for i in rtx'range
    loop
      if routing_table_matches_entry(width, rtx, address, i) then
        return i;
      end if;
    end loop;

    return default;
  end function;

  function routing_table_matches_entry(width: natural;
                                       rt: address_vector;
                                       address: unsigned;
                                       index: natural) return boolean
  is
    alias rtx: address_vector(0 to rt'length-1) is rt;
    constant a: unsigned(width-1 downto 0) := rtx(index)(width-1 downto 0);
    constant b: unsigned(width-1 downto 0) := resize(address, width);
  begin
    return std_match(a, b);
  end function;
  
end package body address;
