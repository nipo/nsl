library ieee, nsl_data;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use nsl_data.bytestream.all;

package crc is

  type crc_state is array(natural range <>) of std_ulogic;
  
  subtype crc16 is crc_state(15 downto 0);
  subtype crc32 is crc_state(31 downto 0);

  function "not"(x:crc_state) return crc_state;
  function "="(x, y:crc_state) return boolean;
  function "/="(x, y:crc_state) return boolean;
  function bitswap(x:crc_state) return crc_state;
  
  -- CRC update function when inserting 1 bit to feedback register.
  -- init and poly must match in vector size and direction.
  -- insert_msb tells whether feedback register is shifted towards low bit
  -- index (true) or towards high bit index (false)
  function crc_update(init, poly : crc_state;
                      insert_msb : boolean;
                      v : std_ulogic) return crc_state;

  -- CRC update function when inserting multiple bits.
  -- This is a repetition of crc_update() with 1 bit, taking bits LSB-first or
  -- MSB-first
  function crc_update(init, poly : crc_state;
                      insert_msb, pop_lsb : boolean;
                      word : std_ulogic_vector) return crc_state;

  -- CRC update function when inserting multiple bytes.
  -- This is a repetition of crc_update() with each byte, taking bits LSB-first or
  -- MSB-first. Bytestring is processed in order.
  function crc_update(init, poly : crc_state;
                      insert_msb, pop_lsb : boolean;
                      data : byte_string) return crc_state;

  -- Specialization of above functions for ISO-14443-3 (NFC-A)
  constant crc_iso_14443_3_a_init : crc16 := x"6363";
  constant crc_iso_14443_3_a_poly : crc16 := x"8408";
  constant crc_iso_14443_3_a_insert_msb : boolean := true;
  constant crc_iso_14443_3_a_pop_lsb : boolean := true;
  function crc_iso_14443_3_a_update(init : crc16;
                                    data : byte_string) return crc16;

  -- Specialization of above functions for IEEE-802.3 (Ethernet)
  constant crc_ieee_802_3_init : crc32 := x"00000000";
  constant crc_ieee_802_3_poly : crc32 := x"edb88320";
  constant crc_ieee_802_3_check : crc32 := x"2144df1c";
  constant crc_ieee_802_3_insert_msb : boolean := true;
  constant crc_ieee_802_3_pop_lsb : boolean := true;
  function crc_ieee_802_3_update(init : crc32;
                                 data : byte_string) return crc32;

end package crc;

package body crc is

  function "not"(x:crc_state) return crc_state is
    variable ret : crc_state(x'range) := x;
  begin
    for i in ret'range
    loop
      ret(i) := not ret(i);
    end loop;
    return ret;
  end function;

  function "="(x, y:crc_state) return boolean is
  begin
    return std_ulogic_vector(x) = std_ulogic_vector(y);
  end function;

  function "/="(x, y:crc_state) return boolean is
  begin
    return std_ulogic_vector(x) = std_ulogic_vector(y);
  end function;

  function bitswap(x:crc_state) return crc_state is
    alias xx: crc_state(0 to x'length - 1) is x;
    variable rx: crc_state(x'length - 1 downto 0);
  begin
    for i in xx'range
    loop
      rx(i) := xx(i);
    end loop;
    return rx;
  end function;

  function crc_update(init, poly : crc_state;
                      insert_msb : boolean;
                      v : std_ulogic) return crc_state is
    variable shifted : crc_state(init'range);
    variable one_out : std_ulogic;
  begin
    assert init'ascending = poly'ascending
      report "Init and polynom directions must match"
      severity failure;
    assert init'length = poly'length
      report "Init and polynom sizes must match"
      severity failure;

    if init'ascending then
      if insert_msb then
        shifted := init(init'low+1 to init'high) & "0";
        one_out := init(init'low);
      else
        shifted := "0" & init(init'low to init'high-1);
        one_out := init(init'high);
      end if;
    else
      if insert_msb then
        shifted := "0" & init(init'high downto init'low+1);
        one_out := init(init'low);
      else
        shifted := init(init'high-1 downto init'low) & "0";
        one_out := init(init'high);
      end if;
    end if;

    if one_out /= v then
      return crc_state(std_ulogic_vector(shifted) xor std_ulogic_vector(poly));
    else
      return shifted;
    end if;
  end function;

  function crc_update(init, poly : crc_state;
                      insert_msb, pop_lsb : boolean;
                      word : std_ulogic_vector) return crc_state is
    variable state : crc_state(init'range) := init;
  begin
    assert state'ascending = poly'ascending
      report "State and polynom directions must match"
      severity failure;
    assert state'length = poly'length
      report "State and polynom sizes must match"
      severity failure;

    if pop_lsb then
      for i in word'low to word'high
      loop
        state := crc_update(state, poly, insert_msb, word(i));
      end loop;
    else
      for i in word'high downto word'low
      loop
        state := crc_update(state, poly, insert_msb, word(i));
      end loop;
    end if;

    return state;
  end function;

  function crc_update(init, poly : crc_state;
                      insert_msb, pop_lsb : boolean;
                      data : byte_string) return crc_state is
    variable state : crc_state(init'range) := init;
  begin
    for i in data'range
    loop
      state := crc_update(state, poly, insert_msb, pop_lsb, data(i));
    end loop;

    return state;
  end function;

  function crc_iso_14443_3_a_update(init : crc16;
                                    data : byte_string) return crc16 is
  begin
    return crc_update(init,
                      crc_iso_14443_3_a_poly,
                      crc_iso_14443_3_a_insert_msb,
                      crc_iso_14443_3_a_pop_lsb,
                      data);
  end function;

  function crc_ieee_802_3_update(init : crc32;
                                 data : byte_string) return crc32 is
  begin
    return not crc_update(not init,
                          crc_ieee_802_3_poly,
                          crc_ieee_802_3_insert_msb,
                          crc_ieee_802_3_pop_lsb,
                          data);
  end function;

end package body crc;
