library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity hdmi_audio_clock_recovery is
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    valid_i : in std_ulogic;
    cts_i : in unsigned(19 downto 0);
    n_i : in unsigned(19 downto 0);

    ready_o : out std_ulogic;

    mclk_tick_o : out std_ulogic;
    sample_tick_o : out std_ulogic
    );
end entity;

architecture beh of hdmi_audio_clock_recovery is

  -- The accumulator never passes CTS by more than N, and both are
  -- twenty bits, so one more bit holds every sum that can arise.
  subtype acc_t is unsigned(20 downto 0);

  -- Ticks of 128 * fs to one of fs
  constant mclk_per_sample_c : natural := 128;

  type regs_t is
  record
    ready: std_ulogic;
    cts: acc_t;
    -- What to add: N while below CTS, and N less CTS when stepping
    -- over it.  Holding both means one adder does the work of an add
    -- and a subtract.
    step_up, step_wrap: acc_t;

    acc: acc_t;
    mclk: std_ulogic;

    divider: natural range 0 to mclk_per_sample_c-1;
    sample: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.ready <= '0';
      r.acc <= (others => '0');
      r.mclk <= '0';
      r.sample <= '0';
      r.divider <= 0;
    end if;
  end process;

  transition: process(r, valid_i, cts_i, n_i) is
  begin
    rin <= r;
    rin.mclk <= '0';
    rin.sample <= '0';

    if valid_i = '1' then
      rin.ready <= '1';
      rin.cts <= resize(cts_i, acc_t'length);
      rin.step_up <= resize(n_i, acc_t'length);
      -- N is smaller than CTS by a long way, so this wraps.  Adding it
      -- back on is what takes CTS off again.
      rin.step_wrap <= resize(n_i, acc_t'length) - resize(cts_i, acc_t'length);
    end if;

    if r.ready = '1' then
      -- The accumulator is allowed past CTS and taken back the cycle
      -- after, which costs a cycle of phase and no accuracy: every
      -- tick still removes exactly CTS.
      if r.acc >= r.cts then
        rin.acc <= r.acc + r.step_wrap;
        rin.mclk <= '1';

        if r.divider = mclk_per_sample_c-1 then
          rin.divider <= 0;
          rin.sample <= '1';
        else
          rin.divider <= r.divider + 1;
        end if;
      else
        rin.acc <= r.acc + r.step_up;
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    ready_o <= r.ready;
    mclk_tick_o <= r.mclk;
    sample_tick_o <= r.sample;
  end process;

end architecture;
