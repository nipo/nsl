library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_usb;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;

entity hid_host_keyboard_repeat is
  generic(
    clock_rate_c: natural := 12_000_000;
    delay_ms_c: natural := 400;
    period_ms_c: natural := 60
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    event_i: in keyboard_event_t;
    valid_i: in std_ulogic;
    ready_o: out std_ulogic;

    event_o: out keyboard_event_t;
    valid_o: out std_ulogic;
    ready_i: in std_ulogic
    );
end entity;

architecture beh of hid_host_keyboard_repeat is

  constant cycles_per_ms_c: natural := clock_rate_c / 1000;
  constant ms_max_c: natural := nsl_math.arith.max(delay_ms_c, period_ms_c);

  -- Lowest scancode that designates a key, below are no-event and
  -- error markers.
  constant key_first_c: natural := 4;
  -- Usage of modifier bit 0, the seven others follow.
  constant modifier_first_c: natural := 16#e0#;

  type regs_t is
  record
    -- Output slot, holding either a forwarded input event or a
    -- synthetic one.
    out_event: keyboard_event_t;
    out_valid: std_ulogic;
    out_synth: boolean;

    armed: boolean;
    armed_code: byte;
    -- Modifier byte of the last event that left this block.
    modifiers: byte;

    ms_div: natural range 0 to cycles_per_ms_c - 1;
    ms_left: natural range 0 to ms_max_c - 1;
  end record;

  signal r, rin: regs_t;

  function is_repeatable(code: byte) return boolean is
  begin
    return to_integer(code) >= key_first_c
      and to_integer(code) < modifier_first_c;
  end function;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.out_event <= keyboard_event_t'(release => false,
                                       code => x"00",
                                       modifiers => x"00");
      r.out_valid <= '0';
      r.out_synth <= false;
      r.armed <= false;
      r.armed_code <= x"00";
      r.modifiers <= x"00";
      r.ms_div <= 0;
      r.ms_left <= 0;
    end if;
  end process;

  transition: process(r, event_i, valid_i, ready_i) is
    variable ms_tick: boolean;
    variable slot_free: boolean;
  begin
    rin <= r;

    ms_tick := r.ms_div = 0;
    -- A slot holding a synthetic event may be reused: dropping a
    -- repeat tick only postpones it to the next period.
    slot_free := r.out_valid = '0' or ready_i = '1' or r.out_synth;

    if r.out_valid = '1' and ready_i = '1' then
      rin.out_valid <= '0';
    end if;

    if ms_tick then
      rin.ms_div <= cycles_per_ms_c - 1;
    else
      rin.ms_div <= r.ms_div - 1;
    end if;

    if r.armed and ms_tick then
      if r.ms_left = 0 then
        rin.ms_left <= period_ms_c - 1;
        if slot_free then
          rin.out_event <= keyboard_event_t'(release => false,
                                             code => r.armed_code,
                                             modifiers => r.modifiers);
          rin.out_valid <= '1';
          rin.out_synth <= true;
        end if;
      else
        rin.ms_left <= r.ms_left - 1;
      end if;
    end if;

    -- Takes the slot over any synthetic event decided above.
    if valid_i = '1' and (r.out_valid = '0' or r.out_synth) then
      rin.out_event <= event_i;
      rin.out_valid <= '1';
      rin.out_synth <= false;
      rin.modifiers <= event_i.modifiers;

      if is_repeatable(event_i.code) then
        if event_i.release then
          if r.armed and event_i.code = r.armed_code then
            rin.armed <= false;
          end if;
        else
          rin.armed <= true;
          rin.armed_code <= event_i.code;
          rin.ms_left <= delay_ms_c - 1;
        end if;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    event_o <= r.out_event;
    valid_o <= r.out_valid;

    if r.out_valid = '0' or r.out_synth then
      ready_o <= '1';
    else
      ready_o <= '0';
    end if;
  end process;

end architecture;
