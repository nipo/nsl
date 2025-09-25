library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_logic;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.scrambler.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_logic.logic.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  function popcnt(v: byte_string) return integer
  is
    variable count: integer := 0;
  begin
    for i in v'range
    loop
      count := count + popcnt(v(i));
    end loop;
    return count;
  end function;

  function disparity(v: byte_string) return real
  is
  begin
    return real(popcnt(v)) / real(v'length*8);
  end function;
  
begin

  basic: process
    constant params_c : nsl_data.scrambler.scrambler_params_t
      := scrambler_params(x"0400_0080_0000_0001",
        word_bit_order => BIT_ORDER_ASCENDING);
    constant context: log_context := "basic";
    variable payload: byte_string(0 to 127) := prbs_byte_string(x"deadbee"&"111", prbs31, 128);
    constant ones: byte_string(0 to 511) := (others => x"ff");
    variable tmpz: byte_string(ones'range);
    variable scrambled, unscrambled: byte_string(payload'range);
    variable s_state : scrambler_state_t := scrambler_init(params_c);
    variable u_state : scrambler_state_t := scrambler_init(params_c);
  begin
    log_info("Initial state: "&to_string(params_c, u_state));

    payload := (others => x"00");
    
    -- Let the thing synchronize
    scramble(params_c, s_state, ones, s_state, tmpz);
    unscramble(params_c, u_state, tmpz, u_state, tmpz);

    -- Scramble some more data
    scramble(params_c, s_state, payload, s_state, scrambled);
    unscramble(params_c, u_state, scrambled, u_state, unscrambled);
    
    assert_equal(context, "synced",
                 payload,
                 unscrambled,
                 failure);

    -- Scramble some more data, inset error
    scramble(params_c, s_state, payload, s_state, scrambled);
    scrambled(60)(5) := not scrambled(60)(5);
    unscramble(params_c, u_state, scrambled, u_state, unscrambled);

    assert_different(context, "synced",
                     payload,
                     unscrambled,
                     failure);

    -- Scramble some more data, it has synced back
    scramble(params_c, s_state, payload, s_state, scrambled);
    unscramble(params_c, u_state, scrambled, u_state, unscrambled);
    
    assert_equal(context, "synced again",
                 payload,
                 unscrambled,
                 failure);
    wait;
  end process;
  
end;
