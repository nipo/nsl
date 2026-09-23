library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_io, nsl_logic, nsl_uart;
library nsl_usb, nsl_bnoc, nsl_amba;
library gatecap_generated;
use nsl_logic.bool.all;
use nsl_clocking.pll.all;

-- Looks at what the DDR3 part actually puts on the wire, running it at
-- a frequency it is specified for.
--
-- The earlier probe ran at 50MHz with the memory's DLL off, which the
-- specification does not allow to be reached from power-up: a part
-- must come up with its DLL enabled, and the only route to DLL-off
-- goes through self-refresh and a frequency change.  So this one runs
-- at DDR3-800, the slowest bin, and leaves the DLL on.
--
-- One fabric cycle at 100MHz spans four memory ticks.  Only the chip
-- select and the two clock pins need to move faster than that: every
-- command is masked while chip select is high, so address and control
-- can sit still for the whole cycle and a one-tick chip select pulse
-- picks out which tick carries the command.  The clock pattern places
-- its rising edge in the middle of that pulse, leaving the part a tick
-- and a half of setup and as much hold.
--
-- The multi purpose register is then read and the strobes and the two
-- data lines that carry it, DQ0 and DQ8, are captured raw at the data
-- rate.  Both go out over the UART as they were sampled, since the
-- question is where the burst lands and what shape it has, which no
-- reduction can answer.
entity boundary is
  port (
    clk_i: in std_ulogic;

    uart_tx_o: out std_ulogic;

    -- The fabric's own USB port, carrying the analyzer.
    usb_dxp_io: inout std_logic;
    usb_dxn_io: inout std_logic;
    usb_rxdp_i: in std_logic;
    usb_rxdn_i: in std_logic;
    usb_pullup_en_o: out std_logic;
    usb_term_dp_io: inout std_logic;
    usb_term_dn_io: inout std_logic;

    ddr3_ck_p_o: out std_ulogic;
    ddr3_ck_n_o: out std_ulogic;
    ddr3_cke_o: out std_ulogic;
    ddr3_cs_n_o: out std_ulogic;
    ddr3_ras_n_o: out std_ulogic;
    ddr3_cas_n_o: out std_ulogic;
    ddr3_we_n_o: out std_ulogic;
    ddr3_odt_o: out std_ulogic;
    ddr3_reset_o: out std_ulogic;
    ddr3_ba_o: out std_ulogic_vector(2 downto 0);
    ddr3_a_o: out std_ulogic_vector(15 downto 0);

    ddr3_0_dm_o: out std_ulogic_vector(1 downto 0);
    ddr3_0_dq_io: inout std_logic_vector(15 downto 0);
    ddr3_0_dqs_p_io: inout std_logic_vector(1 downto 0);
    ddr3_0_dqs_n_io: inout std_logic_vector(1 downto 0)
    );
end entity;

architecture arch of boundary is

  constant phase_c: natural := 4;
  constant ratio_c: natural := 8;

  constant pll_c: pll_config_t := pll_config(
    input_hz => 50_000_000,
    o0 => pll_output(400_000_000),
    -- The strobe has to do two things at once: sit in the middle of
    -- the data eye, and put its first rising edge on a clock edge,
    -- which tDQSS allows only a quarter cycle of slack on.  So the
    -- strobe keeps the clock's own phase and the data is moved back
    -- three quarters of a cycle instead.
    o1 => pll_output(400_000_000, phase => (num => 3, den => 4)));

  -- Fabric cycles, each one four memory ticks of 2.5ns.
  constant t_reset_c: natural := 20000;
  constant t_cke_c: natural := 50000;
  constant t_xpr_c: natural := 31;
  constant t_mrd_c: natural := 1;
  constant t_mod_c: natural := 8;
  constant t_lock_c: natural := 128;
  constant t_rp_c: natural := 2;
  constant t_rcd_c: natural := 2;
  constant t_wr_c: natural := 4;
  constant t_rfc_c: natural := 30;

  -- A serialiser holds its word for a couple of fabric cycles before
  -- it reaches the pin, while address and control go out through plain
  -- registers and arrive at once.  So a command is held still for
  -- several cycles and the chip select pulse, arriving late, still
  -- lands inside that window.
  constant command_hold_c: natural := 6;

  constant capture_c: natural := 16;
  constant record_c: natural := capture_c * ratio_c;
  constant lane_c: natural := 4;

  -- The data lines run through a delay line, and the whole of its
  -- range is walked one tap at a time.  At each tap the register is
  -- read once and the answer judged, which draws an eye.
  constant tap_count_c: natural := 256;
  -- Samples well inside the burst, found by watching the strobes.
  -- Judging away from its edges leaves room for the lanes to arrive at
  -- slightly different times, which they do.
  constant burst_first_c: natural := 6;
  constant burst_last_c: natural := 11;

  constant dq_c: natural := 16;
  constant write_cycle_c: natural := 6;
  constant slot_c: natural := write_cycle_c * ratio_c;
  -- Where in that window the burst starts is not known ahead of time:
  -- the command and the data take different paths to the pins.  So it
  -- is swept, as the read delay was.
  -- The strobe's edges land on slot boundaries and the clock's land on
  -- the odd ones, so only an odd start keeps the two together, which
  -- tDQSS allows a quarter cycle of slack on.  The sweep steps in twos.
  constant offset_count_c: natural := 24;
  -- The burst is recorded at one chosen offset rather than whichever
  -- happens to be last.  Write latency is five ticks and the command
  -- is taken on the odd slot boundary, so eleven slots along is where
  -- the burst belongs; that is offset index five.
  constant watch_offset_c: natural := 5;
  -- A toggling strobe cannot be sampled by the clock that clocks its
  -- own edges.  With this set it is driven at a steady level instead,
  -- which samples as cleanly as the data does and answers the only
  -- question left about it: whether it is driven at all.  It writes
  -- nothing while set.
  constant diagnose_strobe_c: boolean := false;
  -- With this set the burst is never written, leaving an activate
  -- followed by a read on its own: whether the strobes move then says
  -- if the pair works at all, apart from anything the write does.
  constant skip_write_c: boolean := false;
  -- With this set the second phase just repeats the register read that
  -- already works, in the place the array read would go: if that comes
  -- back, the loop and its capture are sound and the fault is in the
  -- activate and read pair alone.
  constant diagnose_mpr_c: boolean := false;
  -- With this set the array is activated and then closed again, and
  -- the read that follows goes to the register rather than the array.
  -- If that read comes back, the part lived through the activate.
  constant diagnose_activate_c: boolean := false;
  -- With this set the register is switched off and then read anyway,
  -- with no activate in between.  A part that has really left the
  -- register behind has an idle bank and answers nothing; one that is
  -- still in it hands back the pattern.
  constant diagnose_mpr_off_c: boolean := false;

  -- Write levelling.  In its levelling mode the part samples the
  -- memory clock on every strobe rising edge and answers with what it
  -- saw on its prime data line.  Walking the strobe against the clock
  -- and watching that answer turn from zero to one finds the edge
  -- tDQSS is measured from, which is the one thing moving the burst
  -- around cannot reach: a slot is 1.25ns and tDQSS is 0.625ns either
  -- side of the clock, so every whole-slot placement is a boundary
  -- case.  The strobe generator's step is finer than a slot.
  --
  -- The whole range of the step is walked rather than stopped at the
  -- first answer, so the report shows the shape of the transition
  -- rather than one number that might have come from noise.
  constant wstep_count_c: natural := tap_count_c;
  -- Forty ticks from the mode register write before a strobe may be
  -- sent, and twenty five more before it may be driven at all.
  constant t_wlmrd_c: natural := 20;
  -- The part answers within seven and a half nanoseconds of the edge.
  constant t_wlo_c: natural := 4;

  constant eye_c: natural := 2;
  constant line_c: natural := 3 + tap_count_c / 4 + 2;
  -- Two eyes, then a line saying where each lane was parked and
  -- whether it reads cleanly there.
  constant summary_c: natural := 3 + 2 * 7 + offset_count_c / 4 + 2;
  -- A levelling line a lane: where its strobe ended up, then what the
  -- part answered at every position of it.
  constant wl_line_c: natural := 3 + 3 + wstep_count_c / 4 + 2;
  constant report_length_c: natural :=
    eye_c * line_c + eye_c * wl_line_c + summary_c;
  constant uart_divisor_c: natural := 100_000_000 / 115200;

  type state_t is (
    ST_RESET,
    ST_CKE,
    ST_XPR,
    ST_MR2, ST_MR2_WAIT,
    ST_MR3, ST_MR3_WAIT,
    ST_MR1, ST_MR1_WAIT,
    ST_MR0, ST_MR0_WAIT,
    ST_LOCK,
    ST_ZQ, ST_ZQ_WAIT,
    ST_WL_ON, ST_WL_ON_WAIT,
    ST_WL_SEND, ST_WL_SETTLE, ST_WL_SAMPLE,
    ST_WL_OFF, ST_WL_OFF_WAIT,
    ST_PRECHARGE, ST_PRECHARGE_WAIT,
    ST_REFRESH, ST_REFRESH_WAIT,
    ST_MPR_ON, ST_MPR_ON_WAIT,
    ST_READ, ST_CAPTURE, ST_JUDGE, ST_STEP,
    ST_CHOOSE, ST_APPLY,
    ST_WACT, ST_WACT_WAIT, ST_WCMD, ST_WRECOVER,
    ST_WPRE, ST_WPRE_WAIT, ST_RACT, ST_RACT_WAIT,
    ST_RPRE, ST_RPRE_WAIT,
    ST_MPR_OFF, ST_MPR_OFF_WAIT,
    ST_SPEAK, ST_PAUSE
    );

  type record_vector is array (natural range <>)
    of std_ulogic_vector(0 to record_c - 1);

  type eye_vector is array (natural range <>)
    of std_ulogic_vector(0 to tap_count_c - 1);

  type tap_number_vector is array (natural range <>)
    of natural range 0 to tap_count_c;

  type wstep_number_vector is array (natural range <>)
    of natural range 0 to wstep_count_c - 1;

  type wstep_vector is array (natural range <>)
    of std_logic_vector(7 downto 0);

  type regs_t is
  record
    state: state_t;
    left: unsigned(15 downto 0);
    slot: natural range 0 to capture_c;
    taken: record_vector(0 to lane_c - 1);
    index: natural range 0 to report_length_c;
    pause: unsigned(26 downto 0);
    tap: natural range 0 to tap_count_c;
    eye: eye_vector(0 to eye_c - 1);
    shift: std_ulogic_vector(0 to eye_c - 1);

    -- Picking the middle of the widest run the sweep found, then
    -- walking each lane's delay line out to it.
    choose: natural range 0 to tap_count_c;
    run: tap_number_vector(0 to eye_c - 1);
    best_run: tap_number_vector(0 to eye_c - 1);
    best_end: tap_number_vector(0 to eye_c - 1);
    target: tap_number_vector(0 to eye_c - 1);
    apply_left: tap_number_vector(0 to eye_c - 1);
    probed: std_ulogic;
    verifying: std_ulogic;
    verified: std_ulogic_vector(0 to eye_c - 1);
    -- Sweeping where the burst is launched, and what came back for
    -- each of those.
    writing: std_ulogic;
    woffset: natural range 0 to offset_count_c;
    wcycle: natural range 0 to write_cycle_c;
    wrote: std_ulogic_vector(0 to offset_count_c - 1);
    -- The burst as it was driven, kept apart from the read that
    -- follows so the read does not paint over it.
    driven: record_vector(0 to lane_c - 1);
    wslot: natural range 0 to capture_c;

    -- Write levelling: whether the part is in its levelling mode,
    -- where the strobe sits against the clock, what the part sampled
    -- of the clock at each of those places, and where that answer
    -- first turned.
    levelling: std_ulogic;
    wstep: natural range 0 to wstep_count_c - 1;
    wl: eye_vector(0 to eye_c - 1);
    wl_at: wstep_number_vector(0 to eye_c - 1);
    wl_found: std_ulogic_vector(0 to eye_c - 1);
    wl_prev: std_ulogic_vector(0 to eye_c - 1);
  end record;

  signal r, rin: regs_t;

  -- Slots the written burst is laid out over, and where in them it
  -- starts.  Two fabric cycles is room enough for a burst of eight
  -- with a preamble in front and a postamble behind.

  signal clock_s, serial_clock_s, quarter_clock_s, board_clock_s: std_ulogic;
  signal pll_clock_s: std_ulogic_vector(0 to pll_c.output_count - 1);
  signal reset_n_s, pll_reset_n_s, locked_s: std_ulogic;

  -- Chip select is low for the tick that carries a command.
  signal select_s: std_ulogic;
  signal cs_word_s: std_ulogic_vector(0 to ratio_c - 1);

  signal sampled_s: record_vector(0 to lane_c - 1);
  signal capture_s: std_ulogic_vector(0 to lane_c - 1);
  signal lane_word_s: record_vector(0 to lane_c - 1);

  -- The serialisers want their fast and slow clocks in a fixed phase
  -- relationship, which two outputs of one PLL do not promise.  The
  -- pad logic has a divider for exactly this, so the fabric clock is
  -- made from the fast one rather than beside it.
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

  signal dq_in_s: std_ulogic_vector(dq_c - 1 downto 0);
  signal dqs_in_s: std_ulogic_vector(1 downto 0);
  signal write_word_s: std_ulogic_vector(0 to ratio_c - 1);
  signal strobe_word_s: std_ulogic_vector(0 to ratio_c - 1);
  signal write_enable_s: std_ulogic_vector(0 to ratio_c / 2 - 1);

  constant clock_usb_hz_c: integer := 60e6;
  constant max_txn_length_l2_c: integer := 5;

  signal clock_usb_s, usb_reset_n_s, app_reset_n_s, scope_reset_n_s: std_ulogic;
  signal utmi_s: nsl_usb.utmi.utmi8_bus;

  type pipe_io is
  record
    cmd, rsp: nsl_bnoc.pipe.pipe_bus_t;
  end record;
  signal scope_pipe_s: pipe_io;

  -- What the analyzer watches: a data line and both strobes as the
  -- input serialisers hand them over, eight slots at a time, and which
  -- part of the sequence the cycle belongs to.
  -- A double rate register takes one clock and no parallel clock, so a
  -- strobe built from it needs no divider of its own and no second
  -- parallel domain.  Fed constants it is simply a clock, which is
  -- what a strobe is; the quarter cycle its clock carries is what puts
  -- its edges in the middle of the data.
  component ODDR is
    generic(
      TXCLK_POL : bit := '0';
      CONSTANT INIT : std_logic := '0'
      );
    port(
      Q0 : out std_logic;
      Q1 : out std_logic;
      D0 : in std_logic;
      D1 : in std_logic;
      TX : in std_logic;
      CLK : in std_logic
      );
  end component;
  attribute syn_black_box of ODDR : component is true;

  -- The strobe generator.  It takes the same clock pair as everything
  -- else and hands back clocks of its own: DQSW0 for the strobe, and
  -- DQSW270 a quarter of a bit ahead of it for data, which is how a
  -- strobe gets to be both centred in the data eye and aligned with
  -- the memory clock at once.  WSTEP moves the pair against the clock
  -- by less than a slot, which is what write levelling walks.
  component DQS is
    generic(
      FIFO_MODE_SEL : bit := '0';
      RD_PNTR : bit_vector := "000";
      DQS_MODE : string := "X1";
      HWL : string := "false"
      );
    port(
      DQSIN, PCLK, FCLK, RESET : in std_logic;
      READ : in std_logic_vector(3 downto 0);
      RCLKSEL : in std_logic_vector(2 downto 0);
      DLLSTEP, WSTEP : in std_logic_vector(7 downto 0);
      RLOADN, RMOVE, RDIR, HOLD : in std_logic;
      WLOADN, WMOVE, WDIR : in std_logic;
      DQSR90, DQSW0, DQSW270 : out std_logic;
      RPOINT, WPOINT : out std_logic_vector(2 downto 0);
      RVALID, RBURST, RFLAG, WFLAG : out std_logic
      );
  end component;
  attribute syn_black_box of DQS : component is true;

  -- The strobe generator does not carry its own delay reference: the
  -- tap length it works in comes from a delay locked loop measuring
  -- the fast clock, and the tools refuse a DQS block whose step is
  -- driven by anything else.  One of these serves every lane.
  component DDRDLL is
    generic(
      DLL_FORCE : string := "FALSE";
      CODESCAL : string := "000";
      SCAL_EN : string := "TRUE";
      DIV_SEL : bit := '0'
      );
    port(
      STEP : out std_logic_vector(7 downto 0);
      LOCK : out std_logic;
      UPDNCNTL, STOP, CLKIN, RESET : in std_logic
      );
  end component;
  attribute syn_black_box of DDRDLL : component is true;

  -- A serialiser that takes its transmit clock from the strobe
  -- generator rather than from the fabric.
  component OSER8_MEM is
    generic(
      HWL : string := "false";
      TXCLK_POL : bit := '0';
      TCLK_SOURCE : string := "DQSW"
      );
    port(
      D0, D1, D2, D3, D4, D5, D6, D7 : in std_logic;
      TX0, TX1, TX2, TX3 : in std_logic;
      PCLK, RESET, FCLK, TCLK : in std_logic;
      Q0, Q1 : out std_logic
      );
  end component;
  attribute syn_black_box of OSER8_MEM : component is true;

  signal strobe_off_s: std_ulogic;
  signal reset_s: std_logic;
  signal wstep_s: wstep_vector(0 to eye_c - 1);
  signal dll_step_s: std_logic_vector(7 downto 0);

  signal la_dq0_s, la_dqs0_s, la_dqs1_s: std_ulogic_vector(7 downto 0);
  signal la_phase_s: std_ulogic_vector(3 downto 0);

  signal uart_data_s: std_ulogic_vector(7 downto 0);
  signal uart_valid_s, uart_ready_s: std_ulogic;

  -- The burst occupies slots write_offset_c to write_offset_c+7, with
  -- alternating levels, which is the same shape the multi purpose
  -- register answers with so the reader can judge it the same way.
  function write_data(cycle, offset: natural) return std_ulogic_vector is
    variable ret: std_ulogic_vector(0 to ratio_c - 1) := (others => '0');
    variable slot: natural;
  begin
    for s in 0 to ratio_c - 1
    loop
      slot := cycle * ratio_c + s;
      if slot >= offset and slot < offset + 8 then
        ret(s) := '1';
      end if;
    end loop;

    return ret;
  end function;

  -- The strobe comes out of a serialiser a quarter turn behind, so the
  -- same slot pattern puts its edges in the middle of the data.  It
  -- leads with a low preamble and trails with a low postamble.
  function write_strobe(cycle, offset: natural) return std_ulogic_vector is
    variable ret: std_ulogic_vector(0 to ratio_c - 1) := (others => '0');
    variable slot: natural;
  begin
    for s in 0 to ratio_c - 1
    loop
      slot := cycle * ratio_c + s;
      if slot >= offset and slot < offset + 8 then
        if diagnose_strobe_c or (slot - offset) mod 2 = 0 then
          ret(s) := '1';
        end if;
      end if;
    end loop;

    return ret;
  end function;

  -- Driven from a tick before the burst to a tick after it, rounded
  -- out to the pairs of slots the pad logic switches on.
  function write_enable(cycle, offset: natural) return std_ulogic_vector is
    variable ret: std_ulogic_vector(0 to ratio_c / 2 - 1) := (others => '0');
    variable slot: natural;
  begin
    for s in 0 to ratio_c / 2 - 1
    loop
      slot := cycle * ratio_c + s * 2;
      if slot + 2 >= offset and slot <= offset + 9 then
        ret(s) := '1';
      end if;
    end loop;

    return ret;
  end function;

  function hex(v: std_ulogic_vector(3 downto 0)) return std_ulogic_vector is
    variable n: natural;
  begin
    n := to_integer(unsigned(v));
    if n < 10 then
      return std_ulogic_vector(to_unsigned(character'pos('0') + n, 8));
    end if;

    return std_ulogic_vector(to_unsigned(character'pos('a') + n - 10, 8));
  end function;

begin

  clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => board_clock_s
      );

  startup: nsl_clocking.reset.reset_at_startup
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

  serial_clock_s <= pll_clock_s(0);
  reset_n_s <= locked_s;

  -- Every serialiser runs off the same fast clock, and the parallel
  -- clock is divided from that one: a serialiser wants a settled
  -- relationship between the two to latch a word, and feeding one a
  -- shifted fast clock against a parallel clock divided from another
  -- loses it.  The strobe is not centred in the data any more, so a
  -- write will not land, but what leaves the pins is now trustworthy.
  quarter_clock_s <= pll_clock_s(1);

  divider: CLKDIV
    generic map(
      DIV_MODE => "4"
      )
    port map(
      clkout => clock_s,
      calib => '0',
      hclkin => serial_clock_s,
      resetn => locked_s
      );

  -- The clock the part samples against, and its complement.  The
  -- pattern puts a rising edge in the middle of every memory tick's
  -- worth of command, rather than on its boundary.
  ck_p: nsl_io.serdes.serdes_output
    generic map(
      left_first_c => true,
      ddr_mode_c => true,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => serial_clock_s,
      parallel_clock_i => clock_s,
      reset_n_i => reset_n_s,
      parallel_i => "01010101",
      serial_o => ddr3_ck_p_o
      );

  ck_n: nsl_io.serdes.serdes_output
    generic map(
      left_first_c => true,
      ddr_mode_c => true,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => serial_clock_s,
      parallel_clock_i => clock_s,
      reset_n_i => reset_n_s,
      parallel_i => "10101010",
      serial_o => ddr3_ck_n_o
      );

  -- A command lands on the first tick of the cycle and the part sees
  -- nothing on the other three.
  cs_word_s <= "00111111" when select_s = '1' else "11111111";

  cs: nsl_io.serdes.serdes_output
    generic map(
      left_first_c => true,
      ddr_mode_c => true,
      ratio_c => ratio_c
      )
    port map(
      serial_clock_i => serial_clock_s,
      parallel_clock_i => clock_s,
      reset_n_i => reset_n_s,
      parallel_i => cs_word_s,
      serial_o => ddr3_cs_n_o
      );

  -- Strobes and the two data lines the multi purpose register is
  -- guaranteed to drive, captured at the data rate.
  -- Everything the design puts on the bus goes out through
  -- serialisers that can let go of their pin; what comes back is read
  -- off the same wire.
  bus_drive: for i in 0 to dq_c - 1
  generate
    signal pad_s: nsl_io.io.tristated;
  begin
    driver: nsl_io.serdes.serdes_output_tristated
      generic map(
        left_first_c => true,
        ddr_mode_c => true,
        ratio_c => ratio_c
        )
      port map(
        serial_clock_i => serial_clock_s,
        parallel_clock_i => clock_s,
        reset_n_i => reset_n_s,
        parallel_i => write_word_s,
        output_enable_i => write_enable_s,
        pad_o => pad_s
        );

    ddr3_0_dq_io(i) <= nsl_io.io.to_logic(pad_s);
    dq_in_s(i) <= to_x01(ddr3_0_dq_io(i));
  end generate;

  -- The strobe is driven for as long as the burst's enable window
  -- lasts; a tristate register takes it a quarter cycle at a time,
  -- which is close enough either side of a burst.
  strobe_off_s <= '0' when write_enable_s /= (write_enable_s'range => '0')
                  else '1';

  reset_s <= not reset_n_s;

  delay_reference: DDRDLL
    generic map(
      CODESCAL => "101",
      SCAL_EN => "false",
      DIV_SEL => '0'
      )
    port map(
      step => dll_step_s,
      lock => open,
      updncntl => '0',
      stop => reset_s,
      clkin => serial_clock_s,
      reset => reset_s
      );

  -- One strobe generator a lane, and the strobe itself out of a
  -- serialiser clocked from it rather than from the fabric.  A double
  -- rate register on a shifted clock could only place the strobe on a
  -- slot boundary, which at this rate is exactly the far edge of what
  -- tDQSS allows; this can place it between them.
  strobe_drive: for i in 0 to eye_c - 1
  generate
    signal dqsw0_s, dqsr90_s, dqsw270_s: std_logic;
    signal p_v_s, p_off_s, n_v_s, n_off_s: std_logic;
  begin
    generator: DQS
      generic map(
        DQS_MODE => "X4",
        -- A write latency of five selects this setting; the vendor
        -- picks between the two by that latency alone.
        HWL => "false"
        )
      port map(
        dqsin => ddr3_0_dqs_p_io(i),
        pclk => clock_s,
        fclk => serial_clock_s,
        reset => reset_s,
        read => "0000",
        rclksel => "000",
        dllstep => dll_step_s,
        wstep => wstep_s(i),
        rloadn => '0',
        rmove => '0',
        rdir => '0',
        wloadn => '0',
        wmove => '0',
        wdir => '0',
        hold => '0',
        dqsr90 => dqsr90_s,
        dqsw0 => dqsw0_s,
        dqsw270 => dqsw270_s,
        rpoint => open,
        wpoint => open,
        rvalid => open,
        rburst => open,
        rflag => open,
        wflag => open
        );

    positive_half: OSER8_MEM
      generic map(
        TCLK_SOURCE => "DQSW"
        )
      port map(
        d0 => strobe_word_s(0), d1 => strobe_word_s(1),
        d2 => strobe_word_s(2), d3 => strobe_word_s(3),
        d4 => strobe_word_s(4), d5 => strobe_word_s(5),
        d6 => strobe_word_s(6), d7 => strobe_word_s(7),
        tx0 => not write_enable_s(0),
        tx1 => not write_enable_s(1),
        tx2 => not write_enable_s(2),
        tx3 => not write_enable_s(3),
        pclk => clock_s,
        reset => reset_s,
        fclk => serial_clock_s,
        tclk => dqsw0_s,
        q0 => p_v_s,
        q1 => p_off_s
        );

    negative_half: OSER8_MEM
      generic map(
        TCLK_SOURCE => "DQSW"
        )
      port map(
        d0 => not strobe_word_s(0), d1 => not strobe_word_s(1),
        d2 => not strobe_word_s(2), d3 => not strobe_word_s(3),
        d4 => not strobe_word_s(4), d5 => not strobe_word_s(5),
        d6 => not strobe_word_s(6), d7 => not strobe_word_s(7),
        tx0 => not write_enable_s(0),
        tx1 => not write_enable_s(1),
        tx2 => not write_enable_s(2),
        tx3 => not write_enable_s(3),
        pclk => clock_s,
        reset => reset_s,
        fclk => serial_clock_s,
        tclk => dqsw0_s,
        q0 => n_v_s,
        q1 => n_off_s
        );

    ddr3_0_dqs_p_io(i) <= p_v_s when p_off_s = '0' else 'Z';
    ddr3_0_dqs_n_io(i) <= n_v_s when n_off_s = '0' else 'Z';
  end generate;

  delayed: for i in 0 to eye_c - 1
  generate
    constant pin_c: natural := i * 8;
  begin
    line: nsl_io.delay.input_delay_variable
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        mark_o => open,
        shift_i => r.shift(i),
        data_i => dq_in_s(pin_c),
        data_o => capture_s(i)
        );
  end generate;

  -- The strobes are no longer watched at all: their pins carry an
  -- output register on the shifted clock, and a pin's IO logic will
  -- not take an input serialiser on a different one.  Two more data
  -- lines go in their place, which is worth more now that the strobe
  -- has been seen driven.
  capture_s(2) <= dq_in_s(1);
  capture_s(3) <= dq_in_s(2);

  -- A strobe changes every slot, so sampling it on the same clock that
  -- clocks its own edges sees nothing.  Half a slot of delay on the way
  -- in puts the sampler in the middle of it instead.
  lane: for i in 0 to lane_c - 1
  generate
    signal word_s: std_ulogic_vector(0 to ratio_c - 1);
  begin
    listener: nsl_io.serdes.serdes_input
      generic map(
        left_first_c => true,
        ddr_mode_c => true,
        ratio_c => ratio_c
        )
      port map(
        serial_clock_i => serial_clock_s,
        parallel_clock_i => clock_s,
        reset_n_i => reset_n_s,
        serial_i => capture_s(i),
        parallel_o => word_s,
        bitslip_i => '0',
        mark_o => open
        );

    lane_word_s(i)(0 to ratio_c - 1) <= word_s;
  end generate;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.state <= ST_RESET;
      r.left <= to_unsigned(t_reset_c, 16);
      r.slot <= 0;
      r.index <= 0;
      r.pause <= (others => '0');
      r.tap <= 0;
      r.shift <= (others => '0');
      r.verifying <= '0';
      r.writing <= '0';
      r.probed <= '0';
      r.woffset <= 0;
      r.levelling <= '0';
      r.wstep <= 0;
      r.wl_found <= (others => '0');
      r.wl_prev <= (others => '1');
    end if;
  end process;

  transition: process(r, uart_ready_s, lane_word_s) is
    variable open_v, done_v: boolean;
    variable code_v: natural range 0 to tap_count_c - 1;
    variable verdict_v: std_ulogic_vector(0 to eye_c - 1);

    procedure hold(count: natural; next_state: state_t) is
    begin
      rin.left <= to_unsigned(count, 16);
      rin.state <= next_state;
    end procedure;

  begin
    rin <= r;
    rin.shift <= (others => '0');

    if r.left /= 0 then
      rin.left <= r.left - 1;
    end if;

    case r.state is
      when ST_RESET =>
        if r.left = 0 then
          hold(t_cke_c, ST_CKE);
        end if;

      when ST_CKE =>
        if r.left = 0 then
          hold(t_xpr_c, ST_XPR);
        end if;

      when ST_XPR =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_MR2;
        end if;

      when ST_MR2 =>
        if r.left = 0 then
          hold(t_mrd_c, ST_MR2_WAIT);
        end if;

      when ST_MR2_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_MR3;
        end if;

      when ST_MR3 =>
        if r.left = 0 then
          hold(t_mrd_c, ST_MR3_WAIT);
        end if;

      when ST_MR3_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_MR1;
        end if;

      when ST_MR1 =>
        if r.left = 0 then
          hold(t_mrd_c, ST_MR1_WAIT);
        end if;

      when ST_MR1_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_MR0;
        end if;

      when ST_MR0 =>
        if r.left = 0 then
          hold(t_mod_c, ST_MR0_WAIT);
        end if;

      when ST_MR0_WAIT =>
        if r.left = 0 then
          hold(t_lock_c, ST_LOCK);
        end if;

      when ST_LOCK =>
        -- The DLL was just reset and needs its lock time before a
        -- read is allowed to mean anything.
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_ZQ;
        end if;

      when ST_ZQ =>
        if r.left = 0 then
          hold(t_lock_c, ST_ZQ_WAIT);
        end if;

      when ST_ZQ_WAIT =>
        -- Levelling comes straight after initialisation and before
        -- anything is read, since where the strobe sits against the
        -- clock is what every write after it depends on.
        if r.left = 0 then
          rin.levelling <= '1';
          rin.wstep <= 0;
          rin.wl_found <= (others => '0');
          rin.wl_prev <= (others => '1');
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_WL_ON;
        end if;

      when ST_WL_ON =>
        if r.left = 0 then
          hold(t_wlmrd_c, ST_WL_ON_WAIT);
        end if;

      when ST_WL_ON_WAIT =>
        if r.left = 0 then
          rin.state <= ST_WL_SEND;
        end if;

      when ST_WL_SEND =>
        hold(t_wlo_c, ST_WL_SETTLE);

      when ST_WL_SETTLE =>
        if r.left = 0 then
          rin.state <= ST_WL_SAMPLE;
        end if;

      when ST_WL_SAMPLE =>
        -- What the part sampled of the clock at this position of the
        -- strobe.  The whole range is walked so the report shows the
        -- shape of the transition, and the first place the answer
        -- turns is where the strobe rises with the clock.
        for i in 0 to eye_c - 1
        loop
          rin.wl(i)(r.wstep) <= lane_word_s(i)(0);
          rin.wl_prev(i) <= lane_word_s(i)(0);
          -- The answer wanted is where the strobe crosses the clock,
          -- which is where it turns from zero to one.  Starting the
          -- walk somewhere the answer already reads one is ordinary:
          -- the strobe simply begins past the clock rather than
          -- before it, and the crossing turns up later in the walk.
          if lane_word_s(i)(0) = '1' and r.wl_prev(i) = '0'
            and r.wl_found(i) = '0' then
            rin.wl_found(i) <= '1';
            rin.wl_at(i) <= r.wstep;
          end if;
        end loop;

        if r.wstep = wstep_count_c - 1 then
          rin.levelling <= '0';
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_WL_OFF;
        else
          rin.wstep <= r.wstep + 1;
          rin.state <= ST_WL_SEND;
        end if;

      when ST_WL_OFF =>
        if r.left = 0 then
          hold(t_mod_c, ST_WL_OFF_WAIT);
        end if;

      when ST_WL_OFF_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_PRECHARGE;
        end if;

      when ST_PRECHARGE =>
        if r.left = 0 then
          hold(t_rp_c, ST_PRECHARGE_WAIT);
        end if;

      when ST_PRECHARGE_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_REFRESH;
        end if;

      when ST_REFRESH =>
        if r.left = 0 then
          hold(t_rfc_c, ST_REFRESH_WAIT);
        end if;

      when ST_REFRESH_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_MPR_ON;
        end if;

      when ST_MPR_ON =>
        if r.left = 0 then
          hold(t_mod_c, ST_MPR_ON_WAIT);
        end if;

      when ST_MPR_ON_WAIT =>
        if r.left = 0 then
          rin.slot <= 0;
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_READ;
        end if;

      when ST_READ =>
        if r.left = 0 then
          rin.slot <= 0;
          rin.state <= ST_CAPTURE;
        end if;

      when ST_CAPTURE =>
        -- Everything the input serialisers hand over from the cycle
        -- the read went out, kept as it came.
        for i in 0 to lane_c - 1
        loop
          rin.taken(i)(r.slot * ratio_c to r.slot * ratio_c + ratio_c - 1)
            <= lane_word_s(i)(0 to ratio_c - 1);
        end loop;

        if r.slot = capture_c - 1 then
          rin.slot <= 0;
          rin.state <= ST_JUDGE;
        else
          rin.slot <= r.slot + 1;
        end if;

      when ST_JUDGE =>
        -- An eye is open here when the burst came back as alternating
        -- levels, which is what the register drives.
        for i in 0 to eye_c - 1
        loop
          if r.writing = '1' then
            -- A landed write reads back as the steady level it wrote.
            open_v := true;
            for s in burst_first_c to burst_last_c
            loop
              if r.taken(i)(s) /= '1' then
                open_v := false;
              end if;
            end loop;
          else
            open_v := true;
            for s in burst_first_c to burst_last_c - 1
            loop
              if r.taken(i)(s) = r.taken(i)(s + 1) then
                open_v := false;
              end if;
            end loop;
          end if;

          verdict_v(i) := to_logic(open_v);
          if r.writing = '1' then
            null;
          elsif r.verifying = '1' then
            rin.verified(i) <= to_logic(open_v);
          else
            -- The delay line counts down, so a tap count of n sits at
            -- code 256 - n.
            if r.tap = 0 then
              code_v := 0;
            else
              code_v := tap_count_c - r.tap;
            end if;
            rin.eye(i)(code_v) <= to_logic(open_v);
          end if;
        end loop;

        if r.writing = '1' then
          -- Both lanes have to come back for the offset to count.
          rin.wrote(r.woffset) <= verdict_v(0) and verdict_v(1);
          rin.woffset <= r.woffset + 1;
          rin.probed <= '0';
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_RPRE;
        elsif r.verifying = '1' then
          -- Trained, so leave the register behind and try a real write.
          rin.writing <= '1';
          rin.woffset <= 0;
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_MPR_OFF;
        else
          rin.state <= ST_STEP;
        end if;

      when ST_STEP =>
        rin.shift <= (others => '1');
        rin.tap <= r.tap + 1;
        rin.left <= to_unsigned(command_hold_c - 1, 16);
        rin.state <= ST_MPR_OFF;

      when ST_MPR_OFF =>
        if r.left = 0 then
          hold(t_mod_c, ST_MPR_OFF_WAIT);
        end if;

      when ST_MPR_OFF_WAIT =>
        if r.left = 0 then
          if r.writing = '1' then
            -- Leaving the register behind, the array wants a refresh
            -- before anything is activated in it.
            rin.left <= to_unsigned(command_hold_c - 1, 16);
            if diagnose_mpr_off_c then
              rin.state <= ST_READ;
            else
              rin.state <= ST_REFRESH;
            end if;
          elsif r.tap = tap_count_c then
            rin.choose <= 0;
            rin.run <= (others => 0);
            rin.best_run <= (others => 0);
            rin.best_end <= (others => 0);
            rin.state <= ST_CHOOSE;
          else
            rin.left <= to_unsigned(command_hold_c - 1, 16);
            rin.state <= ST_REFRESH;
          end if;
        end if;

      when ST_SPEAK =>
        if uart_ready_s = '1' then
          if r.index = report_length_c - 1 then
            rin.pause <= (others => '1');
            rin.state <= ST_PAUSE;
          else
            rin.index <= r.index + 1;
          end if;
        end if;

      when ST_CHOOSE =>
        -- Walk the sweep once, keeping the longest unbroken run of
        -- open taps and where it ended.
        for i in 0 to eye_c - 1
        loop
          if r.eye(i)(r.choose) = '1' then
            rin.run(i) <= r.run(i) + 1;
            if r.run(i) + 1 > r.best_run(i) then
              rin.best_run(i) <= r.run(i) + 1;
              rin.best_end(i) <= r.choose;
            end if;
          else
            rin.run(i) <= 0;
          end if;
        end loop;

        if r.choose = tap_count_c - 1 then
          rin.state <= ST_APPLY;
          for i in 0 to eye_c - 1
          loop
            -- Middle of the best run, and the shifts needed to reach
            -- it from a delay line sitting back at zero.
            rin.target(i) <= r.best_end(i) - r.best_run(i) / 2;
            if r.best_end(i) - r.best_run(i) / 2 = 0 then
              rin.apply_left(i) <= 0;
            else
              rin.apply_left(i) <=
                tap_count_c - (r.best_end(i) - r.best_run(i) / 2);
            end if;
          end loop;
        else
          rin.choose <= r.choose + 1;
        end if;

      when ST_APPLY =>
        done_v := true;
        for i in 0 to eye_c - 1
        loop
          if r.apply_left(i) /= 0 then
            rin.shift(i) <= '1';
            rin.apply_left(i) <= r.apply_left(i) - 1;
            done_v := false;
          end if;
        end loop;

        if done_v then
          rin.verifying <= '1';
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_REFRESH;
        end if;

      when ST_WACT | ST_RACT =>
        if r.left = 0 then
          if r.state = ST_WACT then
            hold(t_rcd_c, ST_WACT_WAIT);
          else
            hold(t_rcd_c, ST_RACT_WAIT);
          end if;
        end if;

      when ST_WACT_WAIT =>
        if r.left = 0 then
          rin.wslot <= 0;
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          if diagnose_activate_c then
            rin.probed <= '1';
            rin.state <= ST_PRECHARGE;
          elsif skip_write_c then
            rin.state <= ST_READ;
          else
            rin.state <= ST_WCMD;
          end if;
        end if;

      when ST_WCMD | ST_WRECOVER =>
        if r.wslot /= capture_c - 1 and r.woffset = watch_offset_c then
          for i in 0 to lane_c - 1
          loop
            rin.driven(i)(r.wslot * ratio_c to r.wslot * ratio_c + ratio_c - 1)
              <= lane_word_s(i)(0 to ratio_c - 1);
          end loop;
          rin.wslot <= r.wslot + 1;
        end if;

        if r.state = ST_WCMD then
          if r.left = 0 then
            hold(t_wr_c, ST_WRECOVER);
          end if;
        elsif r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_WPRE;
        end if;

      when ST_WPRE =>
        if r.left = 0 then
          hold(t_rp_c, ST_WPRE_WAIT);
        end if;

      when ST_WPRE_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_RACT;
        end if;

      when ST_RACT_WAIT =>
        if r.left = 0 then
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_READ;
        end if;

      when ST_RPRE =>
        if r.left = 0 then
          hold(t_rp_c, ST_RPRE_WAIT);
        end if;

      when ST_RPRE_WAIT =>
        if r.left = 0 then
          if r.woffset = offset_count_c then
            rin.index <= 0;
            rin.state <= ST_SPEAK;
          else
            rin.left <= to_unsigned(command_hold_c - 1, 16);
            if diagnose_mpr_c or diagnose_mpr_off_c then
              rin.state <= ST_MPR_OFF;
            else
              rin.state <= ST_WACT;
            end if;
          end if;
        end if;

      when ST_PAUSE =>
        if r.pause = 0 then
          rin.tap <= 0;
          rin.verifying <= '0';
          rin.writing <= '0';
          rin.left <= to_unsigned(command_hold_c - 1, 16);
          rin.state <= ST_REFRESH;
        else
          rin.pause <= r.pause - 1;
        end if;
    end case;
  end process;

  moore: process(r) is
    variable mr: std_ulogic_vector(15 downto 0);
    variable line, column, nibble, lane_index: natural;
    variable elapsed: natural range 0 to write_cycle_c - 1;
    variable character_v: std_ulogic_vector(7 downto 0);
    constant label_c: string(1 to 8) := "D0D8S0S1";
  begin
    select_s <= '0';
    ddr3_ras_n_o <= '1';
    ddr3_cas_n_o <= '1';
    ddr3_we_n_o <= '1';
    ddr3_ba_o <= "000";
    ddr3_a_o <= (others => '0');
    ddr3_reset_o <= '1';
    ddr3_cke_o <= '1';
    -- The levelling procedure wants the part's termination on, which
    -- is what holds the strobe steady enough to be sampled.
    if r.levelling = '1' then
      ddr3_odt_o <= '1';
    else
      ddr3_odt_o <= '0';
    end if;

    -- While levelling, every lane's strobe moves together and the
    -- answers are recorded apart; afterwards each sits where its own
    -- answer turned.
    for i in 0 to eye_c - 1
    loop
      if r.levelling = '1' then
        wstep_s(i) <= std_logic_vector(to_unsigned(r.wstep, 8));
      else
        wstep_s(i) <= std_logic_vector(to_unsigned(r.wl_at(i), 8));
      end if;
    end loop;
    -- Nothing is masked while a burst is going out.
    if r.state = ST_WCMD then
      ddr3_0_dm_o <= (others => '0');
    else
      ddr3_0_dm_o <= (others => '1');
    end if;

    write_word_s <= (others => '0');
    strobe_word_s <= (others => '0');
    write_enable_s <= (others => '0');
    if r.state = ST_WCMD then
      elapsed := command_hold_c - 1 - to_integer(r.left(2 downto 0));
      write_word_s <= write_data(elapsed, 2 * r.woffset + 1);
      strobe_word_s <= write_strobe(elapsed, 2 * r.woffset + 1);
      write_enable_s <= write_enable(elapsed, 2 * r.woffset + 1);
    elsif r.state = ST_WL_SEND then
      -- A cycle of strobe and nothing else: the part samples the
      -- memory clock on each of its rising edges and answers on its
      -- prime data line with what it saw.  The data lines stay let go
      -- of, since the part is the one driving them here.
      strobe_word_s <= "01010101";
      write_enable_s <= (others => '1');
    end if;

    mr := (others => '0');

    case r.state is
      when ST_RESET =>
        ddr3_reset_o <= '0';
        ddr3_cke_o <= '0';

      when ST_CKE =>
        ddr3_cke_o <= '0';

      when ST_MR2 =>
        -- Write latency five, matching this bin.
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '0';
        ddr3_cas_n_o <= '0';
        ddr3_we_n_o <= '0';
        ddr3_ba_o <= "010";
        mr(5 downto 3) := "000";
        ddr3_a_o <= mr;

      when ST_MR3 | ST_MPR_OFF =>
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '0';
        ddr3_cas_n_o <= '0';
        ddr3_we_n_o <= '0';
        ddr3_ba_o <= "011";
        ddr3_a_o <= mr;

      when ST_MR1 | ST_WL_ON | ST_WL_OFF =>
        -- DLL on, no additive latency, termination off.  Entering
        -- levelling also asks for termination, which the procedure
        -- needs to hold the strobe, and leaving it puts both back.
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '0';
        ddr3_cas_n_o <= '0';
        ddr3_we_n_o <= '0';
        ddr3_ba_o <= "001";
        if r.state = ST_WL_ON then
          mr(7) := '1';
          mr(2) := '1';
        end if;
        ddr3_a_o <= mr;

      when ST_MR0 =>
        -- Burst of eight, CAS latency six, write recovery six, and a
        -- DLL reset on the way past.
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '0';
        ddr3_cas_n_o <= '0';
        ddr3_we_n_o <= '0';
        ddr3_ba_o <= "000";
        mr(1 downto 0) := "00";
        mr(6 downto 4) := "010";
        mr(8) := '1';
        mr(11 downto 9) := "010";
        ddr3_a_o <= mr;

      when ST_ZQ =>
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '1';
        ddr3_cas_n_o <= '1';
        ddr3_we_n_o <= '0';
        mr(10) := '1';
        ddr3_a_o <= mr;

      when ST_PRECHARGE =>
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '0';
        ddr3_cas_n_o <= '1';
        ddr3_we_n_o <= '0';
        mr(10) := '1';
        ddr3_a_o <= mr;

      when ST_REFRESH =>
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '0';
        ddr3_cas_n_o <= '0';
        ddr3_we_n_o <= '1';

      when ST_MPR_ON =>
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '0';
        ddr3_cas_n_o <= '0';
        ddr3_we_n_o <= '0';
        ddr3_ba_o <= "011";
        mr(2) := '1';
        ddr3_a_o <= mr;

      when ST_READ =>
        if r.left = command_hold_c - 1 then select_s <= '1'; end if;
        ddr3_ras_n_o <= '1';
        ddr3_cas_n_o <= '0';
        ddr3_we_n_o <= '1';
        ddr3_ba_o <= "000";
        ddr3_a_o <= (others => '0');

      when others =>
        null;
    end case;

    -- Two eyes, then the summary.
    if r.index < eye_c * line_c then
      line := r.index / line_c;
      column := r.index mod line_c;
      lane_index := line;

      if column = 0 then
        character_v := std_ulogic_vector(
          to_unsigned(character'pos(label_c(line * 2 + 1)), 8));
      elsif column = 1 then
        character_v := std_ulogic_vector(
          to_unsigned(character'pos(label_c(line * 2 + 2)), 8));
      elsif column = 2 then
        character_v := x"20";
      elsif column = line_c - 2 then
        character_v := x"0d";
      elsif column = line_c - 1 then
        character_v := x"0a";
      else
        nibble := column - 3;
        if lane_index = 0 then
          character_v := hex(r.driven(0)((nibble mod (record_c / 4)) * 4
                             to (nibble mod (record_c / 4)) * 4 + 3));
        else
          character_v := hex(r.driven(2)((nibble mod (record_c / 4)) * 4
                             to (nibble mod (record_c / 4)) * 4 + 3));
        end if;
      end if;
    elsif r.index < eye_c * line_c + eye_c * wl_line_c then
      -- "Wn ss <map>": where the strobe ended up for this lane, and
      -- what the part answered of the memory clock at every position
      -- the strobe was walked through.
      line := (r.index - eye_c * line_c) / wl_line_c;
      column := (r.index - eye_c * line_c) mod wl_line_c;

      if column = 0 then
        character_v := x"57";
      elsif column = 1 then
        character_v := hex(std_ulogic_vector(to_unsigned(line, 4)));
      elsif column = 2 or column = 5 then
        character_v := x"20";
      elsif column = 3 then
        character_v := hex(std_ulogic_vector(
                        to_unsigned(r.wl_at(line) / 16, 4)));
      elsif column = 4 then
        character_v := hex(std_ulogic_vector(
                        to_unsigned(r.wl_at(line) mod 16, 4)));
      elsif column = wl_line_c - 2 then
        character_v := x"0d";
      elsif column = wl_line_c - 1 then
        character_v := x"0a";
      else
        nibble := column - 6;
        character_v := hex(r.wl(line)(nibble * 4 to nibble * 4 + 3));
      end if;
    else
      -- "AT tt ww v tt ww v": where each lane parked, how wide its run
      -- was, and whether it reads cleanly there.
      column := r.index - eye_c * line_c - eye_c * wl_line_c;
      if column < 3 then
        case column is
          when 0 => character_v := x"41";
          when 1 => character_v := x"54";
          when others => character_v := x"20";
        end case;
      elsif column = summary_c - 2 then
        character_v := x"0d";
      elsif column = summary_c - 1 then
        character_v := x"0a";
      elsif column >= 3 + 2 * 7 then
        nibble := column - 3 - 2 * 7;
        character_v := hex(r.wrote(nibble * 4 to nibble * 4 + 3));
      else
        nibble := column - 3;
        lane_index := nibble / 7;
        if lane_index > eye_c - 1 then
          lane_index := eye_c - 1;
        end if;
        case nibble mod 7 is
          when 0 => character_v := hex(std_ulogic_vector(
                      to_unsigned(r.target(lane_index) / 16, 4)));
          when 1 => character_v := hex(std_ulogic_vector(
                      to_unsigned(r.target(lane_index) mod 16, 4)));
          when 2 => character_v := x"20";
          when 3 => character_v := hex(std_ulogic_vector(
                      to_unsigned(r.best_run(lane_index) / 16, 4)));
          when 4 => character_v := hex(std_ulogic_vector(
                      to_unsigned(r.best_run(lane_index) mod 16, 4)));
          when 5 => character_v := x"20";
          when others =>
            character_v := hex('0' & '0' & '0' & r.verified(lane_index));
        end case;
      end if;
    end if;

    uart_data_s <= character_v;
    if r.state = ST_SPEAK then
      uart_valid_s <= '1';
    else
      uart_valid_s <= '0';
    end if;
  end process;

  la_map: for i in 0 to ratio_c - 1
  generate
    la_dq0_s(i) <= lane_word_s(0)(i);
    la_dqs0_s(i) <= lane_word_s(2)(i);
    la_dqs1_s(i) <= lane_word_s(3)(i);
  end generate;

  -- One code per thing worth triggering on.
  with r.state select la_phase_s <=
    x"1" when ST_MPR_ON | ST_MPR_ON_WAIT,
    x"2" when ST_READ | ST_CAPTURE,
    x"3" when ST_WCMD | ST_WRECOVER,
    x"4" when ST_WACT | ST_WACT_WAIT | ST_RACT | ST_RACT_WAIT,
    x"0" when others;

  usb_pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => 50000000,
      output_hz_c => clock_usb_hz_c
      )
    port map(
      clock_i => board_clock_s,
      reset_n_i => pll_reset_n_s,
      clock_o => clock_usb_s,
      locked_o => usb_reset_n_s
      );

  hs_phy: work.softphy.gw_usb2_phy
    port map(
      clock_i => clock_usb_s,
      reset_n_i => usb_reset_n_s,
      usb_dxp_io => usb_dxp_io,
      usb_dxn_io => usb_dxn_io,
      usb_rxdp_i => usb_rxdp_i,
      usb_rxdn_i => usb_rxdn_i,
      usb_pullup_en_o => usb_pullup_en_o,
      usb_term_dp_io => usb_term_dp_io,
      usb_term_dn_io => usb_term_dn_io,
      utmi_i => utmi_s.sie2phy,
      utmi_o => utmi_s.phy2sie
      );

  func: nsl_usb.func.serial_port
    generic map(
      vendor_id_c => x"dead",
      product_id_c => x"beef",
      device_version_c => x"0100",
      manufacturer_c => "Nipo",
      product_c => "DDR3 scope",
      serial_c => "ddr3",
      hs_supported_c => true,
      phy_clock_rate_c => clock_usb_hz_c,
      self_powered_c => false
      )
    port map(
      phy_system_o => utmi_s.sie2phy.system,
      phy_system_i => utmi_s.phy2sie.system,
      phy_data_o => utmi_s.sie2phy.data,
      phy_data_i => utmi_s.phy2sie.data,
      reset_n_i => usb_reset_n_s,
      app_reset_n_o => app_reset_n_s,
      online_o => open,
      rx_o => scope_pipe_s.cmd.req,
      rx_i => scope_pipe_s.cmd.ack,
      tx_i => scope_pipe_s.rsp.req,
      tx_o => scope_pipe_s.rsp.ack
      );

  scope: block is
    use nsl_amba.axi4_stream.all;
    signal cmd_s, rsp_s: bus_t;

    type framed_io is
    record
      cmd, rsp: nsl_bnoc.framed.framed_bus_t;
    end record;
    signal framed_s: framed_io;
  begin

    unchunker: nsl_bnoc.chunked_link.framed_unchunker
      port map(
        reset_n_i => app_reset_n_s,
        clock_i => clock_usb_s,
        in_i => scope_pipe_s.cmd.req,
        in_o => scope_pipe_s.cmd.ack,
        reset_n_o => scope_reset_n_s,
        out_o => framed_s.cmd.req,
        out_i => framed_s.cmd.ack
        );

    chunker: nsl_bnoc.chunked_link.framed_chunker
      generic map(
        max_txn_length_l2_c => max_txn_length_l2_c
        )
      port map(
        reset_n_i => scope_reset_n_s,
        clock_i => clock_usb_s,
        in_i => framed_s.rsp.req,
        in_o => framed_s.rsp.ack,
        out_o => scope_pipe_s.rsp.req,
        out_i => scope_pipe_s.rsp.ack
        );

    to_stream: nsl_bnoc.axi_adapter.framed_to_axi4_stream
      port map(
        clock_i => clock_usb_s,
        reset_n_i => scope_reset_n_s,
        framed_i => framed_s.cmd.req,
        framed_o => framed_s.cmd.ack,
        axi_o => cmd_s.m,
        axi_i => cmd_s.s
        );

    from_stream: nsl_bnoc.axi_adapter.axi4_stream_to_framed
      port map(
        clock_i => clock_usb_s,
        reset_n_i => scope_reset_n_s,
        axi_i => rsp_s.m,
        axi_o => rsp_s.s,
        framed_o => framed_s.rsp.req,
        framed_i => framed_s.rsp.ack
        );

    rack: gatecap_generated.ddr3_scope.ddr3_scope_core
      generic map(
        stream_config_c => nsl_bnoc.axi_adapter.axi4_stream_framed_config_c,
        burst_length_l2_c => 10
        )
      port map(
        clock_i => clock_usb_s,
        reset_n_i => scope_reset_n_s,
        rx_i => cmd_s.m,
        rx_o => cmd_s.s,
        tx_o => rsp_s.m,
        tx_i => rsp_s.s,
        la_pins_clock_i => clock_s,
        la_pins_reset_n_i => reset_n_s,
        la_pins_dq0_i => la_dq0_s,
        la_pins_dqs0_i => la_dqs0_s,
        la_pins_dqs1_i => la_dqs1_s,
        la_pins_phase_i => la_phase_s
        );
  end block;

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
