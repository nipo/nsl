library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_data, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_transceiver.lane.all;

-- Pattern generator and checker for a lane in ENCODING_PRBS, in
-- fabric.
--
-- A transceiver that generates and checks the pattern itself is
-- handed the job instead; these are for the ones that cannot, the
-- same way nsl_line_coding.ibm_8b10b stands in for a primitive
-- without a codec. They work on the lane's parallel word, so one
-- instance serves whatever width the lane was built at.
--
-- The polynomials come from nsl_data.prbs, which is the only place
-- they are written down. What is needed here is not the polynomial
-- as a mask but the depths it taps, because the whole pattern is
-- "this bit is the exclusive or of the two bits that far back": a
-- polynomial's set bits, index 0 aside, are exactly those depths.
package prbs is

  -- Deepest tap any of the patterns reaches, which is how much
  -- history a generator or a checker has to keep.
  constant max_order_c : natural := 31;

  subtype history_t is std_ulogic_vector(0 to max_order_c-1);

  -- How a mode is carried by a control bus. Numbered by the
  -- pattern's order, which is the order the vendors' own selection
  -- tables use, so a register value reads the same as a datasheet
  -- selection.
  constant mode_width_c : natural := 3;

  function to_logic(mode : prbs_mode_t) return std_ulogic_vector;

  -- A value naming no pattern selects none rather than failing: this
  -- arrives from software, and a configuration bus is not a place to
  -- stop a simulation.
  function to_prbs_mode(value : std_ulogic_vector) return prbs_mode_t;

  -- Whether a mode asks for a pattern at all, as a logic level,
  -- which is what a backend has to hand its own lock counting.
  function is_active(mode : prbs_mode_t) return std_ulogic;

  -- The two depths the mode's polynomial taps, deepest first. A mode
  -- with no pattern taps nothing and reports zero.
  function deep_tap(mode : prbs_mode_t) return natural;
  function shallow_tap(mode : prbs_mode_t) return natural;

  -- Produces the pattern a mode names, one lane word per cycle.
  --
  -- Asking for PRBS_NONE leaves the generator idle and valid_o low,
  -- so a lane can be held quiet without being reset. Holding
  -- force_error_i inverts one bit of every word produced while it
  -- is held, which is what makes a far end's checker visibly
  -- notice.
  component prbs_generator is
    generic(
      byte_count_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      mode_i : in prbs_mode_t;
      force_error_i : in std_ulogic;
      ready_i : in std_ulogic;

      data_o : out byte_string(0 to byte_count_c-1);
      valid_o : out std_ulogic
      );
  end component;

  -- Finds the pattern a mode names in the words it is given, then
  -- predicts it and reports what did not match.
  --
  -- Hunting and checking are deliberately different: while hunting,
  -- the predictor is fed the bits that arrived, so it converges on
  -- whatever phase the line is at without being told; once locked
  -- it is fed its own predictions instead, so one wrong bit on the
  -- line is counted once rather than once again at each depth the
  -- polynomial taps.
  component prbs_checker is
    generic(
      byte_count_c : natural;
      -- Clean words before the pattern is called found, and errored
      -- words before it is called lost.
      lock_word_count_c : natural := 16;
      unlock_word_count_c : natural := 16
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      mode_i : in prbs_mode_t;
      -- Starts the hunt again, which is also how a statistics
      -- counter is told where its window begins.
      restart_i : in std_ulogic;

      data_i : in byte_string(0 to byte_count_c-1);
      valid_i : in std_ulogic;

      locked_o : out std_ulogic;
      -- This word did not match, and how many of its bits did not.
      -- The lane contract carries only the former, because a
      -- transceiver's own checker reports only the former.
      error_o : out std_ulogic;
      error_bit_count_o : out integer range 0 to byte_count_c*8
      );
  end component;

  -- Turns a stream of per-word error reports into the "the pattern
  -- is there" answer a lane's contract asks for.
  --
  -- A transceiver that checks the pattern itself does not
  -- necessarily say whether it found it: the UltraScale+ channel
  -- reports both, where the series 7 one reports only the errors.
  -- The same counting the fabric checker does internally is
  -- therefore needed on its own.
  component prbs_lock_detector is
    generic(
      lock_word_count_c : natural := 16;
      unlock_word_count_c : natural := 16
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Low when no pattern is being looked for at all, which is
      -- not the same as looking and failing.
      checking_i : in std_ulogic;
      restart_i : in std_ulogic;
      -- One per word the checker could not predict.
      error_i : in std_ulogic;

      locked_o : out std_ulogic
      );
  end component;

  -- Protocol-side end of a lane carrying a test pattern: it drives
  -- which pattern each direction uses and gathers what came back
  -- into counters a register bus can be read from, so the
  -- measurement reaches a person through whatever already reaches
  -- that bus.
  --
  -- Four 32-bit registers per lane, at a stride of four words:
  --
  --   +0  control  [2:0] pattern to transmit
  --                [10:8] pattern to expect
  --                [16] spoil one transmitted bit
  --                [17] make the checker hunt again
  --                The two requests act on the write and read back
  --                as zero.
  --   +1  status   [0] the checker has found the pattern
  --   +2  errors   words the checker could not predict
  --   +3  words    words the checker examined while it had the
  --                pattern
  --
  -- The counters run free and wrap: a reader takes a difference
  -- between two reads, which is what makes them safe to carry out of
  -- the lane's own clock domain at all. Resetting them on command
  -- would be a jump rather than a step, and a step at a time is the
  -- whole reason the crossing is sound.
  component prbs_adapter is
    generic(
      config_c : nsl_amba.apb.config_t;
      lane_count_c : natural
      );
    port(
      -- Register bus side, on the clock the cluster hands out for
      -- its own configuration bus.
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      apb_i : in nsl_amba.apb.master_t;
      apb_o : out nsl_amba.apb.slave_t;

      -- One clock per lane: the one that lane presents its receive
      -- status on, which is recovered and therefore neither the
      -- register bus's nor another lane's.
      lane_clock_i : in std_ulogic_vector(0 to lane_count_c-1);

      tx_m_o : out tx_master_vector(0 to lane_count_c-1);
      tx_s_i : in tx_slave_vector(0 to lane_count_c-1);
      rx_m_i : in rx_master_vector(0 to lane_count_c-1);
      rx_s_o : out rx_slave_vector(0 to lane_count_c-1)
      );
  end component;

end package prbs;

package body prbs is

  -- The mode's polynomial as a mask over every depth a pattern here
  -- can tap, so its set bits can be read off without an attribute
  -- on a function's result, which VHDL-93 does not allow. Private:
  -- padded like this it is no longer the shape nsl_data.prbs takes,
  -- which expects a polynomial exactly one bit wider than its
  -- state.
  function polynomial_mask(mode : prbs_mode_t) return prbs_state
  is
    variable ret : prbs_state(max_order_c downto 0);
  begin
    ret := (others => '0');

    case mode is
      when PRBS_7 =>
        ret(prbs7'range) := prbs7;
      when PRBS_9 =>
        ret(prbs9'range) := prbs9;
      when PRBS_15 =>
        ret(prbs15'range) := prbs15;
      when PRBS_23 =>
        ret(prbs23'range) := prbs23;
      when PRBS_31 =>
        ret(prbs31'range) := prbs31;
      when PRBS_NONE =>
        null;
    end case;

    return ret;
  end function;

  function to_logic(mode : prbs_mode_t) return std_ulogic_vector
  is
  begin
    case mode is
      when PRBS_NONE =>
        return "000";
      when PRBS_7 =>
        return "001";
      when PRBS_9 =>
        return "010";
      when PRBS_15 =>
        return "011";
      when PRBS_23 =>
        return "100";
      when PRBS_31 =>
        return "101";
    end case;
  end function;

  function to_prbs_mode(value : std_ulogic_vector) return prbs_mode_t
  is
    variable v : std_ulogic_vector(mode_width_c-1 downto 0);
  begin
    v := value(value'right + mode_width_c - 1 downto value'right);

    if v = "001" then
      return PRBS_7;
    elsif v = "010" then
      return PRBS_9;
    elsif v = "011" then
      return PRBS_15;
    elsif v = "100" then
      return PRBS_23;
    elsif v = "101" then
      return PRBS_31;
    else
      return PRBS_NONE;
    end if;
  end function;

  function is_active(mode : prbs_mode_t) return std_ulogic
  is
  begin
    if mode = PRBS_NONE then
      return '0';
    end if;
    return '1';
  end function;

  function deep_tap(mode : prbs_mode_t) return natural
  is
    variable mask_v : prbs_state(max_order_c downto 0);
  begin
    if mode = PRBS_NONE then
      return 0;
    end if;

    mask_v := polynomial_mask(mode);

    -- nsl_data.prbs requires the top set bit of a polynomial to be
    -- its order, and that is the deepest tap.
    for i in max_order_c downto 1 loop
      if mask_v(i) = '1' then
        return i;
      end if;
    end loop;

    assert false
      report "nsl_transceiver.prbs: " & prbs_mode_t'image(mode)
      & " has an empty polynomial"
      severity failure;
    return 0;
  end function;

  function shallow_tap(mode : prbs_mode_t) return natural
  is
    variable mask_v : prbs_state(max_order_c downto 0);
  begin
    if mode = PRBS_NONE then
      return 0;
    end if;

    mask_v := polynomial_mask(mode);

    for i in 1 to deep_tap(mode) - 1 loop
      if mask_v(i) = '1' then
        return i;
      end if;
    end loop;

    assert false
      report "nsl_transceiver.prbs: " & prbs_mode_t'image(mode)
      & " has no tap between its order and its output term, so it is"
      & " not a pattern this generator can produce"
      severity failure;
    return 0;
  end function;

end package body prbs;
