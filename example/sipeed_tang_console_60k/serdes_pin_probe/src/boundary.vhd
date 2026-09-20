library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

-- One pin carrying everything a DDR3 data pin of ddr3_phy_serdes
-- carries: an eight wide tristated output serialiser, a variable input
-- delay line, and an eight wide input serialiser behind it.  The four
-- clocks are ports so that the same block can be given the arrangement
-- of each pin under test; nothing else about the three differs.
--
-- The word driven out is a port and the word caught is another, so a
-- pin that builds can also be asked what it hears of itself: the pad
-- is driven the whole time and read the whole time, and a part that is
-- idle behind a pulled-down net leaves the pin to the fabric.
entity pin_probe is
  generic(
    -- Whether the pad is ever let go of.  A pin that is only a
    -- placement question keeps its serialiser and never takes the
    -- net, so whatever else is on that net is left alone.
    drive_c: boolean := true
    );
  port(
    out_fast_clock_i: in std_ulogic;
    out_parallel_clock_i: in std_ulogic;
    in_fast_clock_i: in std_ulogic;
    in_parallel_clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    -- Earliest bit on the wire first, in both directions.
    word_i: in std_ulogic_vector(0 to 7);
    caught_o: out std_ulogic_vector(0 to 7);

    -- The line's tap is a number the block holds and not a clocked
    -- path, so its counter keeps company with whoever moves it.
    tap_clock_i: in std_ulogic;
    tap_shift_i: in std_ulogic;
    tap_mark_o: out std_ulogic;

    pad_o: out nsl_io.io.tristated;
    pad_i: in std_ulogic
    );
end entity;

architecture beh of pin_probe is

  constant ratio_c: natural := 8;

  signal enable_s: std_ulogic_vector(0 to ratio_c / 2 - 1);
  signal delayed_s: std_ulogic;

begin

  drive: if drive_c
  generate
    enable_s <= (others => '1');
  end generate;

  quiet: if not drive_c
  generate
    enable_s <= (others => '0');
  end generate;

  driver: nsl_io.serdes.serdes_output_tristated
    generic map(
      left_first_c => true,
      ddr_mode_c => true,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => out_fast_clock_i,
      parallel_clock_i => out_parallel_clock_i,
      reset_n_i => reset_n_i,
      parallel_i => word_i,
      output_enable_i => enable_s,
      pad_o => pad_o
      );

  tap: nsl_io.delay.input_delay_variable
    port map(
      clock_i => tap_clock_i,
      reset_n_i => reset_n_i,
      mark_o => tap_mark_o,
      shift_i => tap_shift_i,
      data_i => pad_i,
      data_o => delayed_s
      );

  listener: nsl_io.serdes.serdes_input
    generic map(
      left_first_c => true,
      ddr_mode_c => true,
      from_delay_c => true,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => in_fast_clock_i,
      parallel_clock_i => in_parallel_clock_i,
      reset_n_i => reset_n_i,
      serial_i => delayed_s,
      parallel_o => caught_o,
      bitslip_i => '0',
      mark_o => open
      );

end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_io, nsl_uart, work;
use nsl_clocking.pll.all;

-- Which arrangements of clocks a GW5A pin will carry at once, and what
-- a pin hears of its own driver.
--
-- ddr3_phy_serdes puts a data pin's output serialiser on a fast clock
-- shifted a quarter of a memory period and its capture on the
-- unshifted one, which is what a 7-series pin does without complaint.
-- The Tang Console bench found a Gowin pin refusing an input
-- serialiser beside an output stage on another clock, and the PHY has
-- a generic for taking the shift on the strobe side instead -- which
-- costs nothing if it is true that a data pin must keep one clock
-- pair, and is pointless if it is not.  This settles which.
--
-- Three pins, differing only in where each serialiser's clocks come
-- from:
--
--   pin 0: output and capture both on the unshifted pair.  What the
--          PHY builds with shift_strobe_c true.
--   pin 1: output on the shifted pair, capture on the unshifted one.
--          What the PHY builds with shift_strobe_c false, which is
--          what the 7-series carries today.
--   pin 2: output and capture both on the shifted fast clock, with the
--          parallel clock divided from the unshifted one.  The
--          arrangement the earlier bench saw hold a stale word; here to
--          say whether the tools accept it, since what it does on a
--          board is already known.
--
-- The clock plan is the one ddr3_phy_serdes asks of this board: 100MHz
-- of controller, 400MHz of memory rate, and a quarter of a memory
-- period of shift on both.
--
-- Pin 0 is also the loopback: the arrangement the PHY builds, driving
-- one word over and over and reading its own net back through the
-- whole delay line.  The DDR3 bench's ruler says a burst comes back
-- with every falling-edge beat replaced by a copy of an earlier one,
-- and that reading is taken through a controller, a PHY and a part.
-- Here there is a serialiser, a pad and a deserialiser and nothing
-- else, so whatever the line says is theirs.
--
-- The report goes out at 115200 8N1, one line a tap:
--
--   W<driven> T<tap> P<caught>/<unstable> Q<caught>/<unstable> <locked>
--
-- every byte two hex digits, every word printed earliest bit first.
-- A bit of U is set when that bit of the capture was not the same at
-- every sample of the tap's dwell, which is how the edges of the eye
-- say so rather than being read as a value.  Four words are swept in
-- turn, each over all two hundred and fifty-six taps, and then it
-- starts again.
entity boundary is
  port(
    clk_i: in std_ulogic;

    uart_tx_o: out std_ulogic;

    -- The loopback, on a pin with nothing on it.
    loop_io: inout std_logic;

    dq_io: inout std_logic_vector(2 downto 0);

    ready_led_o: out std_ulogic
    );
end entity;

architecture arch of boundary is

  -- Which pins this build carries.  The three questions are asked one
  -- build at a time because the first refusal stops the tools: a pin
  -- the fabric will not build takes the whole design with it, and what
  -- is wanted here is an answer per pin.  The defaults are the
  -- arrangements that pass; turn the middle one on to see the refusal.
  constant one_pair_c: boolean := true;
  constant shifted_output_c: boolean := false;
  constant divided_parallel_c: boolean := true;

  -- 50MHz in, and out: the controller rate, the memory rate, and each
  -- of them again a quarter of a memory period late.  A quarter of
  -- 2.5ns is 625ps, which is a sixteenth of the controller period and
  -- a quarter of the memory one, so the two shifts are the same
  -- distance stated in each clock's own turns.
  --
  -- Both shifts land on the solver's grid, which is eighths of a VCO
  -- cycle: whatever VCO the solver picks, an output cycle is a whole
  -- number of VCO cycles and these shifts are whole eighths of one.  An
  -- output whose rate or phase does not come out exact is left disabled
  -- rather than approximated, so all four being enabled in the report
  -- is what says the plan is buildable.
  constant pll_c: pll_config_t := pll_config(
    input_hz => 50_000_000,
    o0 => pll_output(100_000_000),
    o1 => pll_output(400_000_000),
    o2 => pll_output(400_000_000, phase => (num => 1, den => 4)),
    o3 => pll_output(100_000_000, phase => (num => 1, den => 16)));

  -- The report runs on the PLL's controller clock, which is the only
  -- clock here a global network will carry: the board's oscillator
  -- arrives on the configuration clock pin, which reaches the PLL and
  -- nothing else, so logic clocked from it sits on long wire.
  constant uart_divisor_c: natural := 100_000_000 / 115200;

  -- A ladder of periods, each stated earliest bit first: every beat,
  -- every second beat, every fourth, and one whose eight rotations are
  -- all different so that a capture which is merely turned can be told
  -- from one that has lost something.
  type word_table_t is array(natural range <>) of std_ulogic_vector(0 to 7);
  constant words_c: word_table_t(0 to 3) := (
    0 => "01010101",
    1 => "00110011",
    2 => "00001111",
    3 => "00010111");

  -- Long enough that a tap's dwell covers many turns of the word, so a
  -- bit sitting on an edge is caught being both.
  constant dwell_c: natural := 255;
  constant settle_c: natural := 15;
  constant line_c: natural := 26;

  component CLKDIV is
    generic(
      DIV_MODE : string := "2"
      );
    port(
      CLKOUT : out std_logic;
      CALIB : in std_logic;
      HCLKIN : in std_logic;
      RESETN : in std_logic
      );
  end component;
  attribute syn_black_box: boolean;
  attribute syn_black_box of CLKDIV : component is true;

  signal board_clock_s: std_ulogic;
  signal pll_clock_s: std_ulogic_vector(0 to pll_c.output_count - 1);
  signal pll_reset_n_s, locked_s, reset_n_s: std_ulogic;

  signal clock_s, fast_clock_s: std_ulogic;
  signal shifted_clock_s, shifted_fast_clock_s: std_ulogic;
  -- The parallel clock of pin 2, made by the pad logic's own divider
  -- from the unshifted fast clock rather than by the PLL.
  signal divided_clock_s: std_ulogic;

  signal loop_pad_s: nsl_io.io.tristated;
  signal loop_in_s: std_ulogic;
  signal pad_s: nsl_io.io.tristated_vector(0 to 2);
  signal pad_in_s: std_ulogic_vector(0 to 2);
  signal caught_s: std_ulogic_vector(0 to 7);
  signal caught_0_s, caught_1_s, caught_2_s: std_ulogic_vector(0 to 7);
  signal word_s, other_word_s: std_ulogic_vector(0 to 7);
  signal shift_s: std_ulogic;
  signal other_count_s: unsigned(9 downto 0);
  signal seen_s: std_ulogic;

  signal uart_data_s: std_ulogic_vector(7 downto 0);
  signal uart_valid_s, uart_ready_s: std_ulogic;

  type state_t is (
    ST_RESET,
    ST_SETTLE,
    ST_DWELL,
    ST_SPEAK,
    ST_STEP
    );

  type regs_t is
  record
    state: state_t;
    -- Which of the four words is being driven, and where the line sits.
    word: natural range 0 to words_c'length-1;
    tap: unsigned(7 downto 0);
    -- What the capture ever showed during this tap's dwell.
    ever_one: std_ulogic_vector(0 to 7);
    ever_zero: std_ulogic_vector(0 to 7);
    dq_ever_one: std_ulogic_vector(0 to 7);
    dq_ever_zero: std_ulogic_vector(0 to 7);
    left: natural range 0 to dwell_c;
    -- What is being said, and how far through the line it is.
    caught: std_ulogic_vector(0 to 7);
    unstable: std_ulogic_vector(0 to 7);
    dq_caught: std_ulogic_vector(0 to 7);
    dq_unstable: std_ulogic_vector(0 to 7);
    column: natural range 0 to line_c-1;
    shift: std_ulogic;
  end record;

  signal r, rin: regs_t;

  function hex(v: std_ulogic_vector(3 downto 0)) return std_ulogic_vector is
    variable n: natural;
  begin
    n := to_integer(unsigned(v));
    if n < 10 then
      return std_ulogic_vector(to_unsigned(character'pos('0') + n, 8));
    end if;
    return std_ulogic_vector(to_unsigned(character'pos('a') + n - 10, 8));
  end function;

  -- The bit that goes out first is the one printed first.
  function nibble(v: std_ulogic_vector(0 to 7); high: boolean)
    return std_ulogic_vector is
  begin
    if high then
      return v(0 to 3);
    end if;
    return v(4 to 7);
  end function;

begin

  clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => board_clock_s
      );

  startup: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => board_clock_s,
      reset_n_o => pll_reset_n_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_c
      )
    port map(
      clock_i => board_clock_s,
      clock_o => pll_clock_s,
      reset_n_i => pll_reset_n_s,
      locked_o => locked_s
      );

  clock_s <= pll_clock_s(0);
  fast_clock_s <= pll_clock_s(1);
  shifted_fast_clock_s <= pll_clock_s(2);
  shifted_clock_s <= pll_clock_s(3);
  reset_n_s <= locked_s;

  divider: CLKDIV
    generic map(
      DIV_MODE => "4"
      )
    port map(
      clkout => divided_clock_s,
      calib => '0',
      hclkin => fast_clock_s,
      resetn => locked_s
      );

  word_s <= words_c(r.word);

  -- The measured pin: a serialiser, a pad, a delay line and a
  -- deserialiser, all on the unshifted pair, which is the arrangement
  -- the PHY builds.  It sits on a header pin with nothing on it, so
  -- what the capture says is the pad's and not a net's.
  loopback: entity work.pin_probe
    port map(
      out_fast_clock_i => fast_clock_s,
      out_parallel_clock_i => clock_s,
      in_fast_clock_i => fast_clock_s,
      in_parallel_clock_i => clock_s,
      reset_n_i => reset_n_s,
      word_i => word_s,
      caught_o => caught_s,
      tap_clock_i => clock_s,
      tap_shift_i => r.shift,
      tap_mark_o => open,
      pad_o => loop_pad_s,
      pad_i => loop_in_s
      );

  loop_io <= nsl_io.io.to_logic(loop_pad_s);
  loop_in_s <= to_x01(loop_io);

  one_pair: if one_pair_c
  generate
    probe: entity work.pin_probe
      port map(
        out_fast_clock_i => fast_clock_s,
        out_parallel_clock_i => clock_s,
        in_fast_clock_i => fast_clock_s,
        in_parallel_clock_i => clock_s,
        reset_n_i => reset_n_s,
        word_i => word_s,
        caught_o => caught_0_s,
        tap_clock_i => clock_s,
        tap_shift_i => r.shift,
        tap_mark_o => open,
        pad_o => pad_s(0),
        pad_i => pad_in_s(0)
        );
  end generate;

  one_pair_off: if not one_pair_c
  generate
    pad_s(0) <= nsl_io.io.tristated_z;
    caught_0_s <= (others => '0');
  end generate;

  -- The three DDR3 pins are placement questions and nothing else, so
  -- what they hold only has to be real logic: a counter in and a fold
  -- out, which is enough that nothing between them is optimised away
  -- before it reaches a pad.  None of them ever takes its net -- the
  -- part on the other end is left to itself.
  other_regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      other_count_s <= other_count_s + 1;
    end if;

    if reset_n_s = '0' then
      other_count_s <= (others => '0');
    end if;
  end process;

  other_word_gen: for i in 0 to 7
  generate
    other_word_s(i) <= other_count_s(i) xor other_count_s(9);
  end generate;

  shifted_output: if shifted_output_c
  generate
    probe: entity work.pin_probe
      generic map(drive_c => false)
      port map(
        out_fast_clock_i => shifted_fast_clock_s,
        out_parallel_clock_i => shifted_clock_s,
        in_fast_clock_i => fast_clock_s,
        in_parallel_clock_i => clock_s,
        reset_n_i => reset_n_s,
        word_i => other_word_s,
        caught_o => caught_1_s,
        tap_clock_i => clock_s,
        tap_shift_i => other_count_s(9),
        tap_mark_o => open,
        pad_o => pad_s(1),
        pad_i => pad_in_s(1)
        );
  end generate;

  shifted_output_off: if not shifted_output_c
  generate
    pad_s(1) <= nsl_io.io.tristated_z;
    caught_1_s <= (others => '0');
  end generate;

  divided_parallel: if divided_parallel_c
  generate
    probe: entity work.pin_probe
      generic map(drive_c => false)
      port map(
        out_fast_clock_i => shifted_fast_clock_s,
        out_parallel_clock_i => divided_clock_s,
        in_fast_clock_i => shifted_fast_clock_s,
        in_parallel_clock_i => divided_clock_s,
        reset_n_i => reset_n_s,
        word_i => other_word_s,
        caught_o => caught_2_s,
        tap_clock_i => clock_s,
        tap_shift_i => other_count_s(9),
        tap_mark_o => open,
        pad_o => pad_s(2),
        pad_i => pad_in_s(2)
        );
  end generate;

  divided_parallel_off: if not divided_parallel_c
  generate
    pad_s(2) <= nsl_io.io.tristated_z;
    caught_2_s <= (others => '0');
  end generate;

  pads: for i in 0 to 2
  generate
    dq_io(i) <= nsl_io.io.to_logic(pad_s(i));
    pad_in_s(i) <= to_x01(dq_io(i));
  end generate;

  fold: process(clock_s, reset_n_s) is
    variable v: std_ulogic;
  begin
    if rising_edge(clock_s) then
      v := '0';
      for i in 0 to 7
      loop
        v := v xor caught_0_s(i) xor caught_1_s(i) xor caught_2_s(i);
      end loop;
      seen_s <= v;
    end if;

    if reset_n_s = '0' then
      seen_s <= '0';
    end if;
  end process;

  ready_led_o <= seen_s;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, caught_s, locked_s, uart_ready_s) is
  begin
    rin <= r;
    rin.shift <= '0';


    case r.state is
      when ST_RESET =>
        rin.word <= 0;
        rin.tap <= (others => '0');
        rin.left <= settle_c;
        rin.state <= ST_SETTLE;

      -- The line takes its new tap on the edge after the pulse, and
      -- the capture is a few cycles behind the pad, so the dwell only
      -- starts once what is being read is the tap being reported.
      when ST_SETTLE =>
        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.left <= dwell_c;
          rin.ever_one <= (others => '0');
          rin.ever_zero <= (others => '0');
          rin.dq_ever_one <= (others => '0');
          rin.dq_ever_zero <= (others => '0');
          rin.state <= ST_DWELL;
        end if;

      when ST_DWELL =>
        rin.ever_one <= r.ever_one or caught_s;
        rin.ever_zero <= r.ever_zero or not caught_s;
        rin.dq_ever_one <= r.dq_ever_one or caught_0_s;
        rin.dq_ever_zero <= r.dq_ever_zero or not caught_0_s;

        if r.left /= 0 then
          rin.left <= r.left - 1;
        else
          rin.caught <= r.ever_one;
          rin.unstable <= r.ever_one and r.ever_zero;
          rin.dq_caught <= r.dq_ever_one;
          rin.dq_unstable <= r.dq_ever_one and r.dq_ever_zero;
          rin.column <= 0;
          rin.state <= ST_SPEAK;
        end if;

      when ST_SPEAK =>
        if uart_ready_s = '1' then
          if r.column = line_c-1 then
            rin.state <= ST_STEP;
          else
            rin.column <= r.column + 1;
          end if;
        end if;

      when ST_STEP =>
        rin.shift <= '1';
        rin.tap <= r.tap + 1;
        if r.tap = 255 then
          if r.word = words_c'length-1 then
            rin.word <= 0;
          else
            rin.word <= r.word + 1;
          end if;
        end if;
        rin.left <= settle_c;
        rin.state <= ST_SETTLE;
    end case;
  end process;

  talk: process(r, word_s, locked_s) is
    variable c: std_ulogic_vector(7 downto 0);
  begin
    case r.column is
      when 0 => c := x"57";
      when 1 => c := hex(nibble(word_s, true));
      when 2 => c := hex(nibble(word_s, false));
      when 3 => c := x"20";
      when 4 => c := x"54";
      when 5 => c := hex(std_ulogic_vector(r.tap(7 downto 4)));
      when 6 => c := hex(std_ulogic_vector(r.tap(3 downto 0)));
      when 7 => c := x"20";
      when 8 => c := x"50";
      when 9 => c := hex(nibble(r.caught, true));
      when 10 => c := hex(nibble(r.caught, false));
      when 11 => c := x"2f";
      when 12 => c := hex(nibble(r.unstable, true));
      when 13 => c := hex(nibble(r.unstable, false));
      when 14 => c := x"20";
      when 15 => c := x"51";
      when 16 => c := hex(nibble(r.dq_caught, true));
      when 17 => c := hex(nibble(r.dq_caught, false));
      when 18 => c := x"2f";
      when 19 => c := hex(nibble(r.dq_unstable, true));
      when 20 => c := hex(nibble(r.dq_unstable, false));
      when 21 => c := x"20";
      when 22 => c := hex("000" & locked_s);
      when 23 => c := x"20";
      when 24 => c := x"0d";
      when others => c := x"0a";
    end case;

    uart_data_s <= c;

    if r.state = ST_SPEAK then
      uart_valid_s <= '1';
    else
      uart_valid_s <= '0';
    end if;
  end process;

  talker: nsl_uart.serdes.uart_tx
    generic map(
      bit_count_c => 8,
      stop_count_c => 1,
      parity_c => nsl_uart.serdes.PARITY_NONE
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      divisor_i => to_unsigned(uart_divisor_c, 16),
      uart_o => uart_tx_o,
      data_i => uart_data_s,
      valid_i => uart_valid_s,
      ready_o => uart_ready_s
      );

end architecture;
