library ieee, nsl_data;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

-- Generic CRC implementation
package crc is

  -- A CRC state.
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

  -- All parameters for a CRC algorithm.
  -- State is a vector if bits. By convention for this helper, state is
  -- a descending vector. MSB is on the left, LSB is on the right.
  -- Likewise, with byte stream data, MSB is on the left of vector.
  type crc_params_t is
  record
    -- Length of state
    length : integer;
    -- Initial value, also output value for an empty vector.
    init : integer;
    -- Polynomial
    poly : integer;
    -- For every bit inserted in the CRC, whether polynomial rotation
    -- and bit insertion happens from MSB (left) or LSB (right).
    insert_msb : boolean;
    -- Whether input is complemented
    complement_input : boolean;
    -- For byte/logic_vector, whether we take bits one by one from MSB
    -- or LSB.
    pop_lsb : boolean;
    -- Whether saved state is complemented at output. For update() to
    -- be composable, this imples complementing state at input.
    --
    -- For some parameters that are documented with an initial value,
    -- no complement before iteration and complementing before
    -- spilling the CRC after the message, you should complement
    -- initial value constant above.
    complement_state : boolean;
    -- Whether to bitswap the CRC state before spilling it.
    spill_bitswap : boolean;
    -- Thether to spill multi-byte CRC state with LSB or MSB
    -- first. Note that bitswapping happens before endian selection.
    spill_lsb_first : boolean;
  end record;

  -- Initial value, as crc_state, for given parameters
  function crc_init(params : crc_params_t) return crc_state;
  -- Polynomial, as crc_state, for given parameters
  function crc_poly(params : crc_params_t) return crc_state;
  -- Check value, as crc_state, for given parameters.  This is the
  -- value you'll get for a message with its valid CRC appended to it.
  function crc_check(params : crc_params_t) return crc_state;

  -- Update function for a bit
  function crc_update(params : crc_params_t;
                      state : crc_state;
                      v : std_ulogic) return crc_state;

  -- Update function for a bit string
  function crc_update(params : crc_params_t;
                      state : crc_state;
                      word : std_ulogic_vector) return crc_state;

  -- Update function for a byte string
  function crc_update(params : crc_params_t;
                      state : crc_state;
                      data : byte_string) return crc_state;

  -- Serialize current state as a byte string
  function crc_spill(params : crc_params_t;
                     state : crc_state) return byte_string;

  -- Verify CRC over a data stream
  function crc_is_valid(params : crc_params_t;
                        data : byte_string) return boolean;
  
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
    return std_ulogic_vector(x) /= std_ulogic_vector(y);
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
    -- synthesis translate_off
    assert init'ascending = poly'ascending
      report "Init and polynom directions must match"
      severity failure;
    assert init'length = poly'length
      report "Init and polynom sizes must match"
      severity failure;
    -- synthesis translate_on

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
    -- synthesis translate_off
    assert state'ascending = poly'ascending
      report "State and polynom directions must match"
      severity failure;
    assert state'length = poly'length
      report "State and polynom sizes must match"
      severity failure;
    -- synthesis translate_on

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

  function to_crc_state(value: integer; length: natural) return crc_state
  is
    variable ret : crc_state(length-1 downto 0);
  begin
    if length = 32 then
      ret := crc_state(to_signed(value, length));
    else
      ret := crc_state(to_unsigned(value, length));
    end if;
    return ret;
  end function;
  
  function crc_init(params : crc_params_t) return crc_state
  is
  begin
    return to_crc_state(params.init, params.length);
  end function;
  
  function crc_poly(params : crc_params_t) return crc_state
  is
  begin
    return to_crc_state(params.poly, params.length);
  end function;
  
  function crc_update(params : crc_params_t;
                      state : crc_state;
                      v : std_ulogic) return crc_state
  is
    variable s: crc_state(state'length-1 downto 0) := state;
    variable x: std_ulogic := v;
  begin
    if params.complement_state then
      s := not s;
    end if;

    if params.complement_input then
      x := not x;
    end if;

    s := crc_update(init => s,
                    poly => crc_poly(params),
                    insert_msb => params.insert_msb,
                    v => x);

    if params.complement_state then
      s := not s;
    end if;

    return s;
  end function;

  function crc_update(params : crc_params_t;
                      state : crc_state;
                      word : std_ulogic_vector) return crc_state
  is
    variable s: crc_state(state'length-1 downto 0) := state;
    variable x: std_ulogic_vector(word'range) := word;
  begin
    if params.complement_state then
      s := not s;
    end if;

    if params.complement_input then
      x := not x;
    end if;

    s := crc_update(init => s,
                    poly => crc_poly(params),
                    insert_msb => params.insert_msb,
                    pop_lsb => params.pop_lsb,
                    word => x);

    if params.complement_state then
      s := not s;
    end if;

    return s;
  end function;

  function crc_update(params : crc_params_t;
                      state : crc_state;
                      data : byte_string) return crc_state
  is
    variable s: crc_state(state'length-1 downto 0) := state;
    variable item: byte;
  begin
    if params.complement_state then
      s := not s;
    end if;

    for i in data'range
    loop
      item := data(i);

      if params.complement_input then
        item := not item;
      end if;

      s := crc_update(init => s,
                      poly => crc_poly(params),
                      insert_msb => params.insert_msb,
                      pop_lsb => params.pop_lsb,
                      word => item);
    end loop;

    if params.complement_state then
      s := not s;
    end if;

    return s;
  end function;

  function crc_check(params : crc_params_t) return crc_state
  is
  begin
    return crc_update(params, crc_init(params), crc_spill(params, crc_init(params)));
  end function;

  function crc_spill(params : crc_params_t;
                     state : crc_state) return byte_string
  is
    variable ret : crc_state(state'length-1 downto 0);
  begin
    ret := state;
    if params.spill_bitswap then
      ret := bitswap(ret);
    end if;

    if params.spill_lsb_first then
      return to_le(unsigned(ret));
    else
      return to_be(unsigned(ret));
    end if;
  end function;

  function crc_is_valid(params : crc_params_t;
                        data : byte_string) return boolean
  is
  begin
    return crc_update(params, crc_init(params), data) = crc_check(params);
  end function;

end package body crc;
