library ieee, nsl_data;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

package scrambler is

  constant scrambler_max_order_c: natural := 128;
  subtype scrambler_word_t is std_ulogic_vector(0 to scrambler_max_order_c-1);

  type exp_order_t is (
    EXP_ORDER_DESCENDING,
    EXP_ORDER_ASCENDING
    );

  type bit_order_t is (
    BIT_ORDER_DESCENDING,
    BIT_ORDER_ASCENDING
    );

  type scrambler_params_t is
  record
    -- Order of polynomial
    order : integer;
    -- Polynomial, without the high-order coefficient, in ascending
    -- order (i.e. X^0 is on the left of the vector). Bits above order
    -- should be '-' (don't cares)
    poly : scrambler_word_t;
    word_bit_order: bit_order_t;
  end record;

  type scrambler_state_t is
  record
    -- Library will keep all bits above order to '-'.
    -- Refrain from dereferencing this field directly from code.
    value : scrambler_word_t;
  end record;

  -- Parameter stringifier
  function to_string(params : scrambler_params_t) return string;
  -- State stringifier
  function to_string(params : scrambler_params_t;
                     state: scrambler_state_t) return string;

  function scrambler_init(
    constant params : scrambler_params_t)
    return scrambler_state_t;

  function scrambler_params(
    poly : std_ulogic_vector;
    exp_order : exp_order_t := EXP_ORDER_DESCENDING;
    word_bit_order : bit_order_t)
    return scrambler_params_t;

  procedure scramble(constant params : scrambler_params_t;
                     constant state : scrambler_state_t;
                     constant v : std_ulogic;
                     variable state_out : out scrambler_state_t;
                     variable v_out : out std_ulogic);

  procedure scramble(constant params : scrambler_params_t;
                     constant state : scrambler_state_t;
                     constant v : std_ulogic_vector;
                     variable state_out : out scrambler_state_t;
                     variable v_out : out std_ulogic_vector);

  procedure scramble(constant params : scrambler_params_t;
                     constant state : scrambler_state_t;
                     constant v : byte_string;
                     variable state_out : out scrambler_state_t;
                     variable v_out : out byte_string);

  procedure unscramble(constant params : scrambler_params_t;
                       constant state : scrambler_state_t;
                       constant v : std_ulogic;
                       variable state_out : out scrambler_state_t;
                       variable v_out : out std_ulogic);

  procedure unscramble(constant params : scrambler_params_t;
                       constant state : scrambler_state_t;
                       constant v : std_ulogic_vector;
                       variable state_out : out scrambler_state_t;
                       variable v_out : out std_ulogic_vector);

  procedure unscramble(constant params : scrambler_params_t;
                       constant state : scrambler_state_t;
                       constant v : byte_string;
                       variable state_out : out scrambler_state_t;
                       variable v_out : out byte_string);
  
end package scrambler;

package body scrambler is
  
  function to_string(params : scrambler_params_t) return string
  is
    constant poly: std_ulogic_vector := std_ulogic_vector(params.poly(0 to params.order-1)) & '1';
  begin
    return "<scrambler 0x"&to_hex_string(bitswap(poly))&"/"&to_string(params.order)&">";
  end function;

  function to_string(params : scrambler_params_t;
                     state: scrambler_state_t) return string
  is
  begin
    return "<state of "&to_string(params)&": 0x"&to_hex_string(bitswap(std_ulogic_vector(state.value(0 to params.order-1))))&">";
  end function;

  function scrambler_params(
    poly : std_ulogic_vector;
    exp_order : exp_order_t := EXP_ORDER_DESCENDING;
    word_bit_order : bit_order_t)
    return scrambler_params_t
  is
    alias xp: std_ulogic_vector(0 to poly'length-1) is poly;
    alias rxp: std_ulogic_vector(poly'length-1 downto 0) is poly;
    variable order: natural;
    variable p, i: scrambler_word_t;
  begin
    p := (others => '0');

    if exp_order = EXP_ORDER_ASCENDING then
      for idx in 0 to xp'length-1
      loop
        p(idx) := xp(idx);
      end loop;
    else
      for idx in 0 to rxp'length-1
      loop
        p(idx) := rxp(idx);
      end loop;
    end if;

    for idx in p'range
    loop
      if p(idx) = '1' then
        order := idx;
      end if;
    end loop;

    p(order to p'right) := (others => '-');
    
    return scrambler_params_t'(
      order => order,
      poly => p,
      word_bit_order => word_bit_order
      );
  end function;

  function scrambler_init(
    constant params : scrambler_params_t)
    return scrambler_state_t
  is
    variable ret: scrambler_state_t := (value => (others => '-'));
  begin
    for i in 0 to params.order-1
    loop
      if i mod 2 = 0 then
        ret.value(i) := '0';
      else
        ret.value(i) := '1';
      end if;
    end loop;
    return ret;
  end function;

  procedure scramble(constant params : scrambler_params_t;
                     constant state : scrambler_state_t;
                     constant v : std_ulogic;
                     variable state_out : out scrambler_state_t;
                     variable v_out : out std_ulogic)
  is
    variable st : scrambler_state_t := state;
    variable o : std_ulogic := v xor state.value(params.order-1);
  begin
    for i in 1 to params.order-1
    loop
      if params.poly(i) = '1' then
        o := o xor st.value(i-1);
      end if;
    end loop;

    st.value(0 to params.order-1) := o & st.value(0 to params.order-2);

    state_out := st;
    v_out := o;
  end procedure;

  procedure scramble(constant params : scrambler_params_t;
                     constant state : scrambler_state_t;
                     constant v : std_ulogic_vector;
                     variable state_out : out scrambler_state_t;
                     variable v_out : out std_ulogic_vector)
  is
    variable st : scrambler_state_t := state;
    variable ret: std_ulogic_vector(0 to v'length-1) := v;
  begin
    if params.word_bit_order = BIT_ORDER_ASCENDING then
      for i in 0 to v'length-1
      loop
        scramble(params, st, ret(i), st, ret(i));
      end loop;
    else
      for i in v'length-1 downto 0
      loop
        scramble(params, st, ret(i), st, ret(i));
      end loop;
    end if;

    state_out := st;
    v_out := ret;
  end procedure;

  procedure scramble(constant params : scrambler_params_t;
                     constant state : scrambler_state_t;
                     constant v : byte_string;
                     variable state_out : out scrambler_state_t;
                     variable v_out : out byte_string)
  is
    variable st : scrambler_state_t := state;
    variable ret: byte_string(0 to v'length-1) := v;
  begin
    for i in 0 to v'length-1
    loop
      scramble(params, st, ret(i), st, ret(i));
    end loop;

    state_out := st;
    v_out := ret;
  end procedure;

  procedure unscramble(constant params : scrambler_params_t;
                       constant state : scrambler_state_t;
                       constant v : std_ulogic;
                       variable state_out : out scrambler_state_t;
                       variable v_out : out std_ulogic)
  is
    variable st : scrambler_state_t := state;
    variable o : std_ulogic := v xor state.value(params.order-1);
  begin
    for i in 1 to params.order-1
    loop
      if params.poly(i) = '1' then
        o := o xor st.value(i-1);
      end if;
    end loop;

    st.value(0 to params.order-1) := v & st.value(0 to params.order-2);

    state_out := st;
    v_out := o;
  end procedure;

  procedure unscramble(constant params : scrambler_params_t;
                       constant state : scrambler_state_t;
                       constant v : std_ulogic_vector;
                       variable state_out : out scrambler_state_t;
                       variable v_out : out std_ulogic_vector)
  is
    variable st : scrambler_state_t := state;
    variable sto : scrambler_state_t;
    alias xv : std_ulogic_vector(0 to v'length-1) is v;
    variable ret: std_ulogic_vector(0 to v'length-1) := (others => '0');
  begin
    if params.word_bit_order = BIT_ORDER_ASCENDING then
      for i in 0 to v'length-1
      loop
        unscramble(params, st, xv(i), sto, ret(i));
        st := sto;
      end loop;
    else
      for i in v'length-1 downto 0
      loop
        unscramble(params, st, xv(i), sto, ret(i));
        st := sto;
      end loop;
    end if;

    state_out := st;
    v_out := ret;
  end procedure;

  procedure unscramble(constant params : scrambler_params_t;
                       constant state : scrambler_state_t;
                       constant v : byte_string;
                       variable state_out : out scrambler_state_t;
                       variable v_out : out byte_string)
  is
    variable st : scrambler_state_t := state;
    variable sto : scrambler_state_t;
    alias xv : byte_string(0 to v'length-1) is v;
    variable ret: byte_string(0 to v'length-1);
  begin
    for i in 0 to v'length-1
    loop
      unscramble(params, st, xv(i), sto, ret(i));
      st := sto;
    end loop;

    state_out := st;
    v_out := ret;
  end procedure;

end package body scrambler;
