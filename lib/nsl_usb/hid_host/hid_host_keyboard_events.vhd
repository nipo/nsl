library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_usb;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;

entity hid_host_keyboard_events is
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    clear_i: in std_ulogic := '0';

    modifiers_i: in byte;
    keys_i: in byte_string(0 to 5);
    valid_i: in std_ulogic;

    event_o: out keyboard_event_t;
    valid_o: out std_ulogic;
    ready_i: in std_ulogic
    );
end entity;

architecture beh of hid_host_keyboard_events is

  constant slot_count_c: natural := 6;
  constant modifier_count_c: natural := 8;
  -- A scan pass walks the modifier bits first, then the scancode
  -- slots.
  constant scan_last_c: natural := modifier_count_c + slot_count_c - 1;
  -- Usage of modifier bit 0, the following bits are contiguous.
  constant modifier_usage_c: natural := 16#e0#;
  -- Lowest scancode that designates a key, below are no-event and
  -- error markers.
  constant key_first_c: natural := 4;

  subtype keys_t is byte_string(0 to slot_count_c - 1);

  type state_t is (
    ST_IDLE,
    ST_RELEASE,
    ST_PRESS
    );

  type regs_t is
  record
    state: state_t;
    index: natural range 0 to scan_last_c;

    -- Last report a scan pass completed on.
    prev_modifiers: byte;
    prev_keys: keys_t;
    -- Report the running scan pass compares to.
    cur_modifiers: byte;
    cur_keys: keys_t;
    -- Latest report or clear request not scanned yet.
    next_modifiers: byte;
    next_keys: keys_t;
    next_valid: std_ulogic;
    -- Set once the ongoing assertion of clear_i was taken into
    -- account.
    clear_taken: std_ulogic;

    event: keyboard_event_t;
    event_valid: std_ulogic;
  end record;

  signal r, rin: regs_t;

  function is_key(code: byte) return boolean is
  begin
    return to_integer(code) >= key_first_c;
  end function;

  function key_present(keys: keys_t; code: byte) return boolean is
  begin
    for i in keys'range loop
      if keys(i) = code then
        return true;
      end if;
    end loop;
    return false;
  end function;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.index <= 0;
      r.prev_modifiers <= x"00";
      r.prev_keys <= (others => x"00");
      r.next_valid <= '0';
      r.clear_taken <= '0';
      r.event <= keyboard_event_t'(release => false,
                                   code => x"00",
                                   modifiers => x"00");
      r.event_valid <= '0';
    end if;
  end process;

  transition: process(r, clear_i, modifiers_i, keys_i, valid_i, ready_i) is
  begin
    rin <= r;

    if r.event_valid = '1' and ready_i = '1' then
      rin.event_valid <= '0';
    end if;

    case r.state is
      when ST_IDLE =>
        if r.next_valid = '1' then
          rin.cur_modifiers <= r.next_modifiers;
          rin.cur_keys <= r.next_keys;
          rin.next_valid <= '0';
          rin.index <= 0;
          rin.state <= ST_RELEASE;
        end if;

      when ST_RELEASE =>
        if r.event_valid = '0' or ready_i = '1' then
          if r.index < modifier_count_c then
            if r.prev_modifiers(r.index) = '1'
              and r.cur_modifiers(r.index) = '0' then
              rin.event <= keyboard_event_t'(
                release => true,
                code => to_byte(modifier_usage_c + r.index),
                modifiers => r.cur_modifiers);
              rin.event_valid <= '1';
            end if;
          else
            if is_key(r.prev_keys(r.index - modifier_count_c))
              and not key_present(r.cur_keys,
                                  r.prev_keys(r.index - modifier_count_c)) then
              rin.event <= keyboard_event_t'(
                release => true,
                code => r.prev_keys(r.index - modifier_count_c),
                modifiers => r.cur_modifiers);
              rin.event_valid <= '1';
            end if;
          end if;

          if r.index = scan_last_c then
            rin.index <= 0;
            rin.state <= ST_PRESS;
          else
            rin.index <= r.index + 1;
          end if;
        end if;

      when ST_PRESS =>
        if r.event_valid = '0' or ready_i = '1' then
          if r.index < modifier_count_c then
            if r.cur_modifiers(r.index) = '1'
              and r.prev_modifiers(r.index) = '0' then
              rin.event <= keyboard_event_t'(
                release => false,
                code => to_byte(modifier_usage_c + r.index),
                modifiers => r.cur_modifiers);
              rin.event_valid <= '1';
            end if;
          else
            if is_key(r.cur_keys(r.index - modifier_count_c))
              and not key_present(r.prev_keys,
                                  r.cur_keys(r.index - modifier_count_c)) then
              rin.event <= keyboard_event_t'(
                release => false,
                code => r.cur_keys(r.index - modifier_count_c),
                modifiers => r.cur_modifiers);
              rin.event_valid <= '1';
            end if;
          end if;

          if r.index = scan_last_c then
            rin.prev_modifiers <= r.cur_modifiers;
            rin.prev_keys <= r.cur_keys;
            rin.index <= 0;
            rin.state <= ST_IDLE;
          else
            rin.index <= r.index + 1;
          end if;
        end if;
    end case;

    if clear_i = '1' then
      if r.clear_taken = '0' then
        rin.next_modifiers <= x"00";
        rin.next_keys <= (others => x"00");
        rin.next_valid <= '1';
        rin.clear_taken <= '1';
      end if;
    else
      rin.clear_taken <= '0';

      if valid_i = '1' then
        rin.next_modifiers <= modifiers_i;
        rin.next_keys <= keys_i;
        rin.next_valid <= '1';
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    event_o <= r.event;
    valid_o <= r.event_valid;
  end process;

end architecture;
