library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;

entity hid_host_keyboard_chars is
  generic(
    keymap_c: keymap_t := keymap_us_c;
    sequences_c: sequence_map_t := sequences_vt_c;
    alt_sends_escape_c: boolean := true
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    event_i: in keyboard_event_t;
    valid_i: in std_ulogic;
    ready_o: out std_ulogic;

    data_o: out nsl_amba.axi4_stream.master_t;
    data_i: in nsl_amba.axi4_stream.slave_t
    );
end entity;

architecture beh of hid_host_keyboard_chars is

  type state_t is (
    ST_RESET,
    ST_TAKE,
    ST_PUT
    );

  type regs_t is
  record
    state: state_t;
    data: byte_string(0 to sequence_length_max_c - 1);
    length: natural range 0 to sequence_length_max_c;
    index: natural range 0 to sequence_length_max_c - 1;
  end record;

  signal r, rin: regs_t;

  -- Modifier byte bit assignment, matching the boot report.
  constant mod_lctrl_c: natural := 0;
  constant mod_lshift_c: natural := 1;
  constant mod_lalt_c: natural := 2;
  constant mod_rctrl_c: natural := 4;
  constant mod_rshift_c: natural := 5;
  constant mod_ralt_c: natural := 6;

  constant ctrl_low_c: natural := 16#40#;
  constant ctrl_high_c: natural := 16#7e#;

  constant esc_byte_c: byte := x"1b";

  constant empty_sequence_c: key_sequence_t :=
    (length => 0, data => (others => character'val(0)));

  -- Returns x"00" for keys the map leaves unassigned and for codes
  -- past the end of the map, the modifier usages 0xe0 to 0xe7 among
  -- them.
  function char_of(code: byte; modifiers: byte) return byte is
    variable km: keymap_entry_t;
    variable normal: natural;
  begin
    if to_integer(unsigned(code)) > keymap_t'high then
      return x"00";
    end if;

    km := keymap_c(to_integer(unsigned(code)));
    normal := character'pos(km.normal);

    if (modifiers(mod_lctrl_c) = '1' or modifiers(mod_rctrl_c) = '1')
      and normal >= ctrl_low_c and normal <= ctrl_high_c then
      return to_byte(normal mod 32);
    elsif modifiers(mod_lshift_c) = '1' or modifiers(mod_rshift_c) = '1' then
      return to_byte(km.shifted);
    else
      return to_byte(km.normal);
    end if;
  end function;

  -- Zero length for codes past the end of the map and for keys with
  -- no sequence assigned.
  function sequence_of(code: byte) return key_sequence_t is
  begin
    if to_integer(unsigned(code)) > sequence_map_t'high then
      return empty_sequence_c;
    end if;

    return sequences_c(to_integer(unsigned(code)));
  end function;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.data <= (others => x"00");
      r.length <= 0;
      r.index <= 0;
    end if;
  end process;

  transition: process(r, event_i, valid_i, data_i) is
    variable seq: key_sequence_t;
    variable char: byte;
    variable alt: boolean;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_TAKE;

      when ST_TAKE =>
        seq := sequence_of(event_i.code);
        char := char_of(event_i.code, event_i.modifiers);
        alt := alt_sends_escape_c
               and (event_i.modifiers(mod_lalt_c) = '1'
                    or event_i.modifiers(mod_ralt_c) = '1');

        if valid_i = '1' and not event_i.release then
          if seq.length /= 0 then
            for i in 0 to sequence_length_max_c - 1 loop
              if i < seq.length then
                rin.data(i) <= to_byte(seq.data(i + 1));
              end if;
            end loop;
            rin.length <= seq.length;
            rin.index <= 0;
            rin.state <= ST_PUT;
          elsif char /= x"00" then
            if alt then
              rin.data(0) <= esc_byte_c;
              rin.data(1) <= char;
              rin.length <= 2;
            else
              rin.data(0) <= char;
              rin.length <= 1;
            end if;
            rin.index <= 0;
            rin.state <= ST_PUT;
          end if;
        end if;

      when ST_PUT =>
        if is_ready(report_cfg_c, data_i) then
          if r.index + 1 = r.length then
            rin.state <= ST_TAKE;
          else
            rin.index <= r.index + 1;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    data_o <= transfer(report_cfg_c,
                       bytes => (0 => r.data(r.index)),
                       valid => r.state = ST_PUT);

    case r.state is
      when ST_TAKE =>
        ready_o <= '1';
      when others =>
        ready_o <= '0';
    end case;
  end process;

end architecture;
