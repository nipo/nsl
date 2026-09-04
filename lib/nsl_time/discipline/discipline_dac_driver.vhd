library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, work;
use work.discipline.all;
use nsl_math.fixed.all;

entity discipline_dac_driver is
  generic(
    dac_width_c : natural;
    full_scale_ppb_c : natural;
    invert_c : boolean := false
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    freq_offset_ppb_i : in frequency_ppb_t;

    dac_o : out unsigned(dac_width_c-1 downto 0);
    changed_o : out std_ulogic
    );
end entity;

architecture beh of discipline_dac_driver is

  -- Codes per part per billion.
  constant scale_ppb_c : real := 2.0 ** dac_width_c / real(full_scale_ppb_c);
  constant scale_left_c : integer := sfixed_left(scale_ppb_c);
  constant scale_c : sfixed(scale_left_c downto scale_left_c-25)
    := to_sfixed(scale_ppb_c, scale_left_c, scale_left_c-25);

  -- One bit above the code for the sign, one for the overshoot the
  -- rail clamp takes back, fractional bits so the code is truncated
  -- once.
  subtype code_t is sfixed(dac_width_c+1 downto -3);

  function power_of_two(constant left, right, index : integer) return sfixed
  is
    variable ret : sfixed(left downto right);
  begin
    ret := (others => '0');
    ret(index) := '1';
    return ret;
  end function;

  constant midscale_c : code_t
    := power_of_two(code_t'left, code_t'right, dac_width_c-1);
  constant dac_midscale_c : unsigned(dac_width_c-1 downto 0)
    := shift_left(to_unsigned(1, dac_width_c), dac_width_c-1);

  subtype ppb_t is sfixed(freq_offset_ppb_i'length downto 0);

  type regs_t is
  record
    dac : unsigned(dac_width_c-1 downto 0);
    changed : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  assert dac_width_c >= 2
    report "DAC is too narrow"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.dac <= dac_midscale_c;
      r.changed <= '0';
    end if;
  end process;

  transition: process(r, freq_offset_ppb_i) is
    variable ppb : ppb_t;
    variable code : code_t;
    variable dac : unsigned(dac_width_c-1 downto 0);
  begin
    rin <= r;

    ppb := resize(to_sfixed(freq_offset_ppb_i), ppb_t'left, ppb_t'right);
    if invert_c then
      ppb := -ppb;
    end if;

    code := add_saturate(midscale_c,
                         mul(ppb, scale_c, code_t'left, code_t'right));
    dac := to_unsigned(to_ufixed_saturate(code, dac_width_c-1, 0));

    rin.dac <= dac;
    if dac /= r.dac then
      rin.changed <= '1';
    else
      rin.changed <= '0';
    end if;
  end process;

  moore: process(r) is
  begin
    dac_o <= r.dac;
    changed_o <= r.changed;
  end process;

end architecture;
