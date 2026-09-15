library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_synthesis;

entity hdmi_audio_clock_recovery is
  generic(
    -- Ticks to make for every audio frame.
    --
    -- A source states N and CTS against 128, which is what IEC 60958
    -- clocks a subframe with, and that is the least this can be asked
    -- for.  A converter usually wants more: 256 frames' worth of
    -- master clock is the slowest most of them take, and a clock needs
    -- a tick for each of its edges, so driving one costs 512.
    --
    -- What changes with this is the step, not the rate: every ratio
    -- comes out at exactly the rate the source stated, because it is
    -- the same N and CTS scaled.
    mclk_ratio_c : natural := 128
    );
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

  -- What the stated N has to be multiplied by to tick this often.  A
  -- ratio the standard's 128 does not divide has no such number and is
  -- not a thing to ask for.
  constant scale_c : natural := mclk_ratio_c / 128;

  -- The accumulator never passes CTS by more than the scaled N, and
  -- CTS is twenty bits, so twenty bits plus what the scale adds plus
  -- one holds every sum that can arise.
  subtype acc_t is unsigned(20 + nsl_math.arith.log2(scale_c) downto 0);

  type regs_t is
  record
    ready: std_ulogic;
    cts: acc_t;
    -- What to add: the scaled N while below CTS, and that less CTS
    -- when stepping over it.  Holding both means one adder does the
    -- work of an add and a subtract.
    step_up, step_wrap: acc_t;

    acc: acc_t;
    mclk: std_ulogic;

    divider: natural range 0 to mclk_ratio_c-1;
    sample: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  shape: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "A tick ratio has to be a whole number of the 128 "
      & "a source states N and CTS against",
      condition_c => scale_c * 128 = mclk_ratio_c
      )
    port map(
      unused_i => '0'
      );

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
      rin.step_up <= resize(n_i * scale_c, acc_t'length);
      -- N is smaller than CTS by a long way, so this wraps.  Adding it
      -- back on is what takes CTS off again.
      rin.step_wrap <= resize(n_i * scale_c, acc_t'length)
                       - resize(cts_i, acc_t'length);
    end if;

    if r.ready = '1' then
      -- The accumulator is allowed past CTS and taken back the cycle
      -- after, which costs a cycle of phase and no accuracy: every
      -- tick still removes exactly CTS.
      if r.acc >= r.cts then
        rin.acc <= r.acc + r.step_wrap;
        rin.mclk <= '1';

        if r.divider = mclk_ratio_c-1 then
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
