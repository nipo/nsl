library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;

entity hid_host_keyboard_chars is
  generic(
    keymap_c: keymap_t := keymap_us_c
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
    data: byte;
  end record;

  signal r, rin: regs_t;

  -- Modifier byte bit assignment, matching the boot report.
  constant mod_lctrl_c: natural := 0;
  constant mod_lshift_c: natural := 1;
  constant mod_rctrl_c: natural := 4;
  constant mod_rshift_c: natural := 5;

  constant ctrl_low_c: natural := 16#40#;
  constant ctrl_high_c: natural := 16#7e#;

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

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.data <= x"00";
    end if;
  end process;

  transition: process(r, event_i, valid_i, data_i) is
    variable char: byte;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_TAKE;

      when ST_TAKE =>
        if valid_i = '1' then
          if event_i.release then
            char := x"00";
          else
            char := char_of(event_i.code, event_i.modifiers);
          end if;

          if char /= x"00" then
            rin.data <= char;
            rin.state <= ST_PUT;
          end if;
        end if;

      when ST_PUT =>
        if is_ready(report_cfg_c, data_i) then
          rin.state <= ST_TAKE;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    data_o <= transfer(report_cfg_c,
                       bytes => (0 => r.data),
                       valid => r.state = ST_PUT);

    case r.state is
      when ST_TAKE =>
        ready_o <= '1';
      when others =>
        ready_o <= '0';
    end case;
  end process;

end architecture;
