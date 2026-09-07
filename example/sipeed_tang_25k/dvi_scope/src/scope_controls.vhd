library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- User controls of the scope demo. All stepping happens on tick_i
-- (one pulse per frame): while run_i is set the phase origin drifts,
-- pan buttons add a manual offset, and the frequency buttons walk a
-- preset table with auto-repeat while held.
entity scope_controls is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;

    run_i : in std_ulogic;
    freq_down_i : in std_ulogic;
    freq_up_i : in std_ulogic;
    pan_left_i : in std_ulogic;
    pan_right_i : in std_ulogic;

    phase_increment_o : out unsigned(15 downto 0);
    phase_origin_o : out unsigned(15 downto 0);
    -- Periods across the screen, as displayable text
    periods_text_o : out string(1 to 5);
    -- Phase origin in degrees, 0 to 359
    phase_angle_o : out unsigned(8 downto 0)
    );
end entity;

architecture beh of scope_controls is

  -- Phase increment is periods * 2**16 / 1024 visible columns
  type preset_t is
  record
    increment : unsigned(15 downto 0);
    text : string(1 to 5);
  end record;
  type preset_vector is array(natural range <>) of preset_t;

  constant presets_c : preset_vector(0 to 11) := (
    (to_unsigned(16, 16), " 0.25"),
    (to_unsigned(32, 16), " 0.50"),
    (to_unsigned(64, 16), " 1.00"),
    (to_unsigned(96, 16), " 1.50"),
    (to_unsigned(128, 16), " 2.00"),
    (to_unsigned(192, 16), " 3.00"),
    (to_unsigned(256, 16), " 4.00"),
    (to_unsigned(384, 16), " 6.00"),
    (to_unsigned(512, 16), " 8.00"),
    (to_unsigned(768, 16), "12.00"),
    (to_unsigned(1024, 16), "16.00"),
    (to_unsigned(1536, 16), "24.00")
    );

  constant scroll_step_c : natural := 256;
  constant pan_step_c : natural := 512;
  -- Frames between two auto-repeated frequency steps
  constant repeat_period_c : natural := 16;

  type regs_t is
  record
    preset : natural range 0 to presets_c'length-1;
    offset : unsigned(15 downto 0);
    repeat_left : natural range 0 to repeat_period_c-1;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.preset <= 2;
      r.offset <= (others => '0');
      r.repeat_left <= 0;
    end if;
  end process;

  transition: process(r, tick_i, run_i,
                      freq_down_i, freq_up_i, pan_left_i, pan_right_i) is
    variable delta : unsigned(15 downto 0);
  begin
    rin <= r;

    -- Deltas are modulo 2**16, negative steps wrap
    if run_i = '1' and pan_right_i = '1' then
      delta := to_unsigned(scroll_step_c + pan_step_c, 16);
    elsif run_i = '1' and pan_left_i = '1' then
      delta := to_unsigned((2**16 + scroll_step_c - pan_step_c) mod 2**16, 16);
    elsif run_i = '1' then
      delta := to_unsigned(scroll_step_c, 16);
    elsif pan_right_i = '1' then
      delta := to_unsigned(pan_step_c, 16);
    elsif pan_left_i = '1' then
      delta := to_unsigned(2**16 - pan_step_c, 16);
    else
      delta := to_unsigned(0, 16);
    end if;

    if tick_i = '1' then
      rin.offset <= r.offset + delta;

      if freq_up_i = '1' and freq_down_i = '0' then
        if r.repeat_left = 0 then
          rin.repeat_left <= repeat_period_c - 1;
          if r.preset /= presets_c'length - 1 then
            rin.preset <= r.preset + 1;
          end if;
        else
          rin.repeat_left <= r.repeat_left - 1;
        end if;
      elsif freq_down_i = '1' and freq_up_i = '0' then
        if r.repeat_left = 0 then
          rin.repeat_left <= repeat_period_c - 1;
          if r.preset /= 0 then
            rin.preset <= r.preset - 1;
          end if;
        else
          rin.repeat_left <= r.repeat_left - 1;
        end if;
      else
        rin.repeat_left <= 0;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    phase_increment_o <= presets_c(r.preset).increment;
    periods_text_o <= presets_c(r.preset).text;
    phase_origin_o <= r.offset;
    phase_angle_o <= resize(shift_right(r.offset * to_unsigned(360, 9), 16), 9);
  end process;

end architecture;
