--------------------------------------------------------------------------------
-- gearbox_c2c
--
-- Generic width converter ("gearbox"). Exactly one of the following must
-- hold, checked at elaboration time:
--   input_width_c is an integer multiple of output_width_c  (downsize)
--   output_width_c is an integer multiple of input_width_c  (upsize)
--   input_width_c = output_width_c                          (passthrough)
--
-- Downsize : the wide input word is already fully present every cycle, so
--            we just latch it once and rotate a slice out each cycle --
--            no accumulation needed.
-- Upsize   : the narrow input arrives piecemeal, so we shift/accumulate
--            input_width_c-wide chunks into a register until a full
--            output_width_c-wide word is assembled, then present it.
--
-- Latency note: downsize has 1 cycle of latency (input registered once),
-- upsize has ratio_c cycles of latency (must wait for the word to fill),
-- passthrough is combinational (0 cycles). 
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity gearbox_c2c is
  generic(
    input_width_c  : positive;
    output_width_c : positive;
    msb_first_c : boolean := false
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;
    in_i      : in  std_ulogic_vector(0 to input_width_c - 1);
    out_o     : out std_ulogic_vector(0 to output_width_c - 1)
    );
end entity gearbox_c2c;

architecture rtl of gearbox_c2c is

  ------------------------------------------------------------------------
  -- Ratio calculation 
  ------------------------------------------------------------------------
  function calc_ratio(a, b : positive) return positive is
  begin
    if a > b then
      return a / b;
    else
      return b / a;
    end if;
  end function calc_ratio;

  constant ratio_c : positive := calc_ratio(input_width_c, output_width_c);

begin

  ------------------------------------------------------------------------
  -- Elaboration-time contract check: one width must be an integer
  -- multiple of the other. Covers downsize, upsize, and equal-width
  -- (both mod results are trivially 0 when the widths are equal).
  ------------------------------------------------------------------------
  assert (input_width_c mod output_width_c = 0) or
         (output_width_c mod input_width_c = 0)
    report "gearbox_c2c: input_width_c and output_width_c must be integer " &
           "multiples of one another (got input_width_c=" &
           integer'image(input_width_c) & ", output_width_c=" &
           integer'image(output_width_c) & ")"
    severity failure;

  ------------------------------------------------------------------------
  -- Downsize: input_width_c > output_width_c
  -- Shift register mirroring the upsize side: load the full wide word,
  -- then shift left by output_width_c bits each cycle so the chunk to
  -- output is always sitting in the same fixed slot (0 to
  -- output_width_c - 1). 
  ------------------------------------------------------------------------
  gen_downsize : if input_width_c > output_width_c generate
    signal shift_reg : std_ulogic_vector(0 to input_width_c - 1);
    signal count     : natural range 0 to ratio_c - 1;
    constant zeros   : std_ulogic_vector(output_width_c - 1 downto 0) := (others => '0');
  begin

    process(clock_i, reset_n_i)
    begin
      if reset_n_i = '0' then
        shift_reg <= (others => '0');
        count     <= ratio_c - 1;
      elsif rising_edge(clock_i) then
        if count = ratio_c - 1 then
          shift_reg <= in_i;
          count     <= 0;
        else
          if msb_first_c then
            shift_reg <= shift_reg(output_width_c to input_width_c - 1) & zeros;
          else
            shift_reg <= zeros & shift_reg(0 to output_width_c - 1);
          end if;
          count     <= count + 1;
        end if;
      end if;
    end process;

    process(shift_reg)
    begin
      if msb_first_c then
        out_o <= shift_reg(0 to output_width_c - 1);
      else
        out_o <= shift_reg(output_width_c to input_width_c - 1);
      end if;
    end process;

  end generate gen_downsize;

  ------------------------------------------------------------------------
  -- Upsize: input_width_c < output_width_c
  -- Shift in one input_width_c-wide chunk per cycle; once ratio_c chunks
  -- have arrived, latch the completed word into out_reg and hold it
  -- stable while the next word accumulates underneath.
  ------------------------------------------------------------------------
  gen_upsize : if input_width_c < output_width_c generate
    signal shift_reg : std_ulogic_vector(0 to output_width_c - 1);
    signal out_reg   : std_ulogic_vector(0 to output_width_c - 1);
    signal count     : natural range 0 to ratio_c - 1;
  begin

    process(clock_i, reset_n_i)
    begin
      if reset_n_i = '0' then
        shift_reg <= (others => '0');
        out_reg   <= (others => '0');
        count     <= 0;
      elsif rising_edge(clock_i) then
        if msb_first_c then
          shift_reg <= shift_reg(input_width_c to output_width_c - 1) & in_i;
        else
          shift_reg <= in_i & shift_reg(0 to input_width_c - 1);
        end if;

        if count = ratio_c - 1 then
          count   <= 0;
          if msb_first_c then
            out_reg <= shift_reg(input_width_c to output_width_c - 1) & in_i;
          else
            out_reg <= in_i & shift_reg(0 to input_width_c - 1);
          end if;
        else
          count <= count + 1;
        end if;
      end if;
    end process;

    out_o <= out_reg;

  end generate gen_upsize;

  ------------------------------------------------------------------------
  -- Equal width: ratio_c = 1, trivial passthrough.
  ------------------------------------------------------------------------
  gen_equal : if input_width_c = output_width_c generate
    out_o <= in_i;
  end generate gen_equal;

end architecture rtl;
