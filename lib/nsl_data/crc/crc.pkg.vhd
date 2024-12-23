library ieee, nsl_data, nsl_logic;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_logic.bool.all;

-- Generic CRC implementation
--
-- CRC parameters and CRC state are stored in a record.  Maximum order
-- handled by the package is a constant, it can be enlarged ad libitum
-- with no synthesis penalty.
--
-- Parameters are intended to be stored as a constant, passed as
-- generics if needs be.
package crc is

  constant crc_max_order_c: natural := 128;
  subtype crc_word_t is std_ulogic_vector(0 to crc_max_order_c-1);

  type exp_order_t is (
    EXP_ORDER_DESCENDING,
    EXP_ORDER_ASCENDING
    );

  type bit_order_t is (
    BIT_ORDER_DESCENDING,
    BIT_ORDER_ASCENDING
    );

  function "not"(o: bit_order_t) return bit_order_t;
  function "not"(o: exp_order_t) return exp_order_t;
  
  -- All parameters for a CRC algorithm.  Generating this structure
  -- from a call to crc_params() below is the typical way to go.
  type crc_params_t is
  record
    -- Order of polynomial
    order : integer;
    -- Polynomial, without the high-order coefficient, in ascending
    -- order (i.e. X^0 is on the left of the vector). Bits above order
    -- should be '-' (don't cares)
    poly : crc_word_t;
    -- Initial value, in ascending order (i.e. X^0 is on the left of
    -- the vector). Bits above order should be '-' (don't cares)
    init : crc_word_t;
    -- Whether saved state is complemented at output. For crc_update()
    -- to be composable, this imples complementing state at input.
    --
    -- For some parameters that are documented with an initial value,
    -- no complement before iteration and complementing before
    -- spilling the CRC after the message, you should complement
    -- initial value constant above.
    complement_state : boolean;
    -- Whether input is complemented
    complement_input : boolean;
    -- Order in which bits are taken from bytes (or any other
    -- multi-bit words)
    byte_bit_order: bit_order_t;
    -- Order in which coefficients should be spilled to a bit vector.
    -- For usual representation with x^0 on the right, you should pass
    -- EXP_ORDER_DESCENDING here.
    spill_order : exp_order_t;
    -- For orders multiple of 8, result may be spilled to a byte
    -- string.  Once we have spilled a bit string, assuming it has
    -- lower order on the right, should we spill it from the right
    -- (increasing) or from the left (decreasing)
    byte_order : byte_order_t;
  end record;

  -- A CRC state.
  type crc_state_t is
  record
    -- Library will keep all bits above order to '-'.
    -- Refrain from dereferencing this field directly from code.
    remainder : crc_word_t;
  end record;

  -- Parameter stringifier
  function to_string(params : crc_params_t) return string;
  -- State stringifier
  function to_string(params : crc_params_t; state: crc_state_t) return string;

  -- CRC parameters facotry
  --
  -- Usually, you'll have spec with a polynom and an initial value
  -- expressed as an (hex) integer where LSB matches x^0.  In terms of
  -- bit vector, this means the order of exponents is decreasing when
  -- processing the vectors from left to right.
  --
  -- Polynom value passed here must have the higher-order coefficient
  -- present. It allows to compute the order.  Extra non-significant
  -- MSBs are ignored.
  --
  -- Initialization value may be shorter and will be extended with
  -- zeros.
  --
  -- If state complement is enabled, initial value is the complement
  -- of initial remainder.
  --
  -- Complement input and byte_bit_order refer to input bitstream
  -- processing.
  --
  -- Spill_order and byte_order refer to finalization.
  function crc_params(poly : std_ulogic_vector;
                      init : std_ulogic_vector := "";
                      exp_order : exp_order_t := EXP_ORDER_DESCENDING;
                      complement_state : boolean;
                      complement_input : boolean;
                      byte_bit_order : bit_order_t;
                      spill_order: exp_order_t;
                      byte_order : byte_order_t) return crc_params_t;
  
  -- Initial value, as state, for given parameters
  function crc_init(params : crc_params_t) return crc_state_t;

  -- Tells whether for any given blob with appended correct CRC
  -- spilled as defined, the CRC over the whole blob will be constant
  function crc_has_constant_check(params : crc_params_t) return boolean;
  -- Tells whether zeros can be prepended to message without any
  -- change in computed value
  function crc_is_pre_zero_transparent(params : crc_params_t) return boolean;
  -- Tells whether ones can be prepended to message without any change
  -- in computed value
  function crc_is_pre_ones_transparent(params : crc_params_t) return boolean;
  -- Tells whether zeros can be appended to message without any change
  -- in computed value
  function crc_is_post_zero_transparent(params : crc_params_t) return boolean;
  -- Tells whether ones can be appended to message without any change
  -- in computed value
  function crc_is_post_ones_transparent(params : crc_params_t) return boolean;

  -- Check value, as state, for given parameters.  This is the value
  -- you'll get for a message with its valid CRC appended to it.
  --
  -- For some set of parameters, it does not exist.
  function crc_check(params : crc_params_t) return crc_state_t;

  -- Update function for a bit
  function crc_update(params : crc_params_t;
                      state : crc_state_t;
                      v : std_ulogic) return crc_state_t;

  -- Update function for a bit string
  function crc_update(params : crc_params_t;
                      state : crc_state_t;
                      word : std_ulogic_vector) return crc_state_t;

  -- Update function for a byte string
  function crc_update(params : crc_params_t;
                      state : crc_state_t;
                      data : byte_string) return crc_state_t;

  -- Serialize current state as a bit vector, with returned vector
  -- having exponents in params.spill_order
  function crc_spill_vector(params : crc_params_t;
                            state : crc_state_t) return std_ulogic_vector;

  -- Serialize current state as a byte string
  function crc_spill(params : crc_params_t;
                     state : crc_state_t) return byte_string;

  -- Parse a bit string as state, abiding params.spill_order
  function crc_load(params : crc_params_t;
                    raw: std_ulogic_vector) return crc_state_t;

  -- Parse a byte string as state
  function crc_load(params : crc_params_t;
                    raw: byte_string) return crc_state_t;

  -- Verify CRC over a data stream
  function crc_is_valid(params : crc_params_t;
                        data : byte_string) return boolean;

  -- Verify CRC value WRT a current state
  function crc_is_valid(params : crc_params_t;
                        state : crc_state_t;
                        value : std_ulogic_vector) return boolean;

  -- Verify CRC value WRT a current state
  function crc_is_valid(params : crc_params_t;
                        state : crc_state_t;
                        value : byte_string) return boolean;

  -- Assert whether current state is for a valid checked data stream.
  function crc_is_valid(params : crc_params_t;
                        state : crc_state_t) return boolean;

  -- Length of check value
  function crc_byte_length(params : crc_params_t) return natural;
  
end package crc;

package body crc is

  function "not"(o: bit_order_t) return bit_order_t
  is
  begin
    if o = BIT_ORDER_ASCENDING then
      return BIT_ORDER_DESCENDING;
    else
      return BIT_ORDER_ASCENDING;
    end if;
  end function;

  function "not"(o: exp_order_t) return exp_order_t
  is
  begin
    if o = EXP_ORDER_ASCENDING then
      return EXP_ORDER_DESCENDING;
    else
      return EXP_ORDER_ASCENDING;
    end if;
  end function;
  
  function crc_params(poly : std_ulogic_vector;
                      init : std_ulogic_vector := "";
                      exp_order : exp_order_t := EXP_ORDER_DESCENDING;
                      complement_state : boolean;
                      complement_input : boolean;
                      byte_bit_order : bit_order_t;
                      spill_order: exp_order_t;
                      byte_order : byte_order_t) return crc_params_t
  is
    alias xp: std_ulogic_vector(0 to poly'length-1) is poly;
    alias rxp: std_ulogic_vector(poly'length-1 downto 0) is poly;
    alias xi: std_ulogic_vector(0 to init'length-1) is init;
    alias rxi: std_ulogic_vector(init'length-1 downto 0) is init;
    variable order: natural;
    variable p, i: crc_word_t;
    variable so: exp_order_t;
  begin
    p := (others => '0');
    i := (others => '0');

    if exp_order = EXP_ORDER_ASCENDING then
      for idx in 0 to xp'length-1
      loop
        p(idx) := xp(idx);
      end loop;

      for idx in 0 to xi'length-1
      loop
        i(idx) := xi(idx);
      end loop;

      so := spill_order;
    else
      for idx in 0 to rxp'length-1
      loop
        p(idx) := rxp(idx);
      end loop;

      for idx in 0 to rxi'length-1
      loop
        i(idx) := rxi(idx);
      end loop;

      so := not spill_order;
    end if;

    for idx in p'range
    loop
      if p(idx) = '1' then
        order := idx;
      end if;
    end loop;

    p(order to p'right) := (others => '-');
    i(order to p'right) := (others => '-');
    
    return crc_params_t'(
      order => order,
      poly => p,
      init => i,
      complement_state => complement_state,
      complement_input => complement_input,
      byte_bit_order => byte_bit_order,
      spill_order => so,
      byte_order => byte_order
      );
  end function;
  
  function crc_init(params : crc_params_t) return crc_state_t
  is
    constant s: std_ulogic_vector := params.init(0 to params.order-1);
    constant pad: std_ulogic_vector(params.order to crc_word_t'length-1) := (others => '-');
  begin
    return crc_state_t'(
      remainder => s & pad
      );
  end function;

  function crc_has_constant_check(params : crc_params_t) return boolean
  is
    constant ta: byte_string := from_hex("313233343536373839");
    constant ca: crc_state_t := crc_update(params, crc_init(params), ta);
    constant va: byte_string := crc_spill(params, ca);
    constant xa: crc_state_t := crc_update(params, ca, va);

    constant tb: byte_string := from_hex("deadbeef");
    constant cb: crc_state_t := crc_update(params, crc_init(params), tb);
    constant vb: byte_string := crc_spill(params, cb);
    constant xb: crc_state_t := crc_update(params, cb, vb);
  begin
    return crc_spill_vector(params, xa) = crc_spill_vector(params, xb);
  end function;

  function crc_is_pre_zero_transparent(params : crc_params_t) return boolean
  is
    constant i: std_ulogic_vector := params.init(0 to params.order-1);
  begin
    return ((i = (i'range => '0') and not params.complement_state)
            or (i = (i'range => '1') and params.complement_state))
      and not params.complement_input;
  end function;

  function crc_is_pre_ones_transparent(params : crc_params_t) return boolean
  is
    constant i: std_ulogic_vector := params.init(0 to params.order-1);
  begin
    return ((i = (i'range => '0') and not params.complement_state)
            or (i = (i'range => '1') and params.complement_state))
      and params.complement_input;
  end function;

  function crc_is_post_zero_transparent(params : crc_params_t) return boolean
  is
    constant c: std_ulogic_vector := crc_spill_vector(params, crc_check(params));
  begin
    return c = (c'range => '0') and not params.complement_input;
  end function;

  function crc_is_post_ones_transparent(params : crc_params_t) return boolean
  is
    constant c: std_ulogic_vector := crc_spill_vector(params, crc_check(params));
  begin
    return c = (c'range => '1') and params.complement_input;
  end function;

  function crc_check(params : crc_params_t) return crc_state_t
  is
  begin
    if params.order mod 8 = 0 then
      return crc_update(params, crc_init(params), crc_spill(params, crc_init(params)));
    else
        return crc_update(params, crc_init(params), crc_spill_vector(params, crc_init(params)));
    end if;
  end function;

  function update(poly: std_ulogic_vector;
                  state: std_ulogic_vector;
                  v: std_ulogic;
                  complement_v: boolean) return std_ulogic_vector
  is
    constant xv: std_ulogic := v xor to_logic(complement_v);
    alias xp: std_ulogic_vector(0 to poly'length-1) is poly;
    alias xs: std_ulogic_vector(0 to state'length-1) is state;
    variable one_out : std_ulogic := xs(xs'right);
    variable tmp : std_ulogic_vector(0 to state'length-1) := '0' & xs(0 to xs'right-1);
  begin
--    report "update " & to_string(poly)
--      & " " & to_string(state)
--      & " " & to_string(v)
--      & " " & to_string(complement_v);
    if one_out /= xv then
      return tmp xor xp;
    else
      return tmp;
    end if;
  end function;
  
  function crc_update(params : crc_params_t;
                      state : crc_state_t;
                      v : std_ulogic) return crc_state_t
  is
    constant p: std_ulogic_vector(0 to params.order-1) := params.poly(0 to params.order-1);
    variable s: std_ulogic_vector(0 to params.order-1) := state.remainder(0 to params.order-1);
    variable pad: std_ulogic_vector(params.order to crc_word_t'length-1) := (others => '-');
  begin
    if params.complement_state then
      s := not update(p, not s, v, params.complement_input);
    else    
      s := update(p, s, v, params.complement_input);
    end if;

    return crc_state_t'(
      remainder => s & pad
      );
  end function;

  function crc_update(params : crc_params_t;
                  state : crc_state_t;
                  word : std_ulogic_vector) return crc_state_t
  is
    constant p: std_ulogic_vector(0 to params.order-1) := params.poly(0 to params.order-1);
    variable s: std_ulogic_vector(0 to params.order-1) := state.remainder(0 to params.order-1);
    variable pad: std_ulogic_vector(params.order to crc_word_t'length-1) := (others => '-');
    alias wa: std_ulogic_vector(word'length-1 downto 0) is word;
  begin
    if params.complement_state then
      s := not s;
    end if;

    if params.byte_bit_order = BIT_ORDER_ASCENDING then
      for i in 0 to wa'length-1
      loop
        s := update(p, s, wa(i), params.complement_input);
      end loop;
    else
      for i in wa'length-1 downto 0
      loop
        s := update(p, s, wa(i), params.complement_input);
      end loop;
    end if;

    if params.complement_state then
      s := not s;
    end if;

    return crc_state_t'(
      remainder => s & pad
      );
  end function;
  
  function crc_update(params : crc_params_t;
                  state : crc_state_t;
                  data : byte_string) return crc_state_t
  is
    alias xd: byte_string(0 to data'length-1) is data;
    variable s : crc_state_t := state;
  begin
    for i in xd'range
    loop
      s := crc_update(params, s, xd(i));
    end loop;

    return s;
  end function;

  function crc_spill_vector(params : crc_params_t;
                            state : crc_state_t) return std_ulogic_vector
  is
    variable s: std_ulogic_vector(0 to params.order-1) := state.remainder(0 to params.order-1);
  begin
    if params.spill_order /= EXP_ORDER_ASCENDING then
      return bitswap(s);
    else
      return s;
    end if;
  end function;

  function crc_spill(params : crc_params_t;
                 state : crc_state_t) return byte_string
  is
    constant b: byte_string := to_le(unsigned(crc_spill_vector(params, state)));
  begin
    return reorder(b, params.byte_order);
  end function;

  function crc_load(params : crc_params_t;
                raw: std_ulogic_vector) return crc_state_t
  is
    variable s: std_ulogic_vector(0 to params.order-1) := raw;
    variable pad: std_ulogic_vector(params.order to crc_word_t'length-1) := (others => '-');
  begin
    if params.spill_order /= EXP_ORDER_ASCENDING then
      return crc_state_t'(
        remainder => bitswap(s) & pad
        );
    else
      return crc_state_t'(
        remainder => s & pad
        );
    end if;
  end function;

  function crc_load(params : crc_params_t;
                raw: byte_string) return crc_state_t
  is
    constant bv: std_ulogic_vector(0 to crc_byte_length(params)*8-1)
      := std_ulogic_vector(from_le(reorder(raw, params.byte_order)));
  begin
    return crc_load(params, bv(0 to params.order-1));
  end function;

  function crc_is_valid(params : crc_params_t;
                        data : byte_string) return boolean
  is
    constant state : crc_state_t := crc_check(params);
  begin
    return state = crc_update(params, crc_init(params), data);
  end function;

  function crc_is_valid(params : crc_params_t;
                        state : crc_state_t;
                        value : std_ulogic_vector) return boolean
  is
  begin
    return crc_spill_vector(params, state) = value;
  end function;

  function crc_is_valid(params : crc_params_t;
                        state : crc_state_t;
                        value : byte_string) return boolean
  is
  begin
    return crc_spill(params, state) = value;
  end function;

  function crc_is_valid(params : crc_params_t;
                        state : crc_state_t) return boolean
  is
    constant check : crc_state_t := crc_check(params);
    variable c: std_ulogic_vector(0 to params.order-1) := check.remainder(0 to params.order-1);
    variable s: std_ulogic_vector(0 to params.order-1) := state.remainder(0 to params.order-1);
  begin
    return c = s;
  end function;

  function crc_byte_length(params : crc_params_t) return natural
  is
  begin
    return (params.order + 7) / 8;
  end function;

  function to_string(params : crc_params_t) return string
  is
    constant p: unsigned(params.order downto 0) := '1' & unsigned(bitswap(params.poly(0 to params.order-1)));
    variable i: unsigned(params.order-1 downto 0) := unsigned(bitswap(params.init(0 to params.order-1)));
  begin
    return "<CRC poly "&to_string(p)
      &", init "&to_string(i)
      &if_else(params.complement_state, ", !state", "")
      &if_else(params.complement_input, ", !input", "")
      &if_else(params.spill_order = EXP_ORDER_ASCENDING, " ASC", " DES")
      &if_else(params.byte_order = BYTE_ORDER_INCREASING, " INC", " DEC")
      &">";
  end function;
  
  function to_string(params : crc_params_t; state: crc_state_t) return string
  is
    variable r: unsigned(params.order-1 downto 0)
      := unsigned(bitswap(state.remainder(0 to params.order-1)));
  begin
    return "<State for "&to_string(params)&" remainder "&to_string(r)&">";
  end function;

end package body crc;
