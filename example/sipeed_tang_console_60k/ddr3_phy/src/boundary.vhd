library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_data, nsl_ext_ram, nsl_hwdep, nsl_io, nsl_uart;
use nsl_clocking.pll.all;
use nsl_data.bytestream.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.timing.all;

-- Brings the SOM's DDR3 part up through nsl_ext_ram's Gowin PHY,
-- rather than by driving the pins from here.
--
-- The bench owns the protocol -- the reset and mode register sequence,
-- write levelling, gate training, a write and a read of the array --
-- and the PHY owns the pins: where a command lands inside a cycle,
-- where the strobe sits against the memory clock, and where capture
-- sits in the incoming eye.  What is left here is a state machine
-- placing one command a cycle and a report going out over the UART.
--
-- The two things training has to find:
--
--  * where the strobe rises with the memory clock.  The part is put in
--    its levelling mode, where it samples the clock on each strobe
--    rising edge and answers with what it saw, and the PHY's write
--    step is walked until that answer turns from zero to one.
--
--  * where the capture gate sits.  A read only comes back if the gate
--    is open over it, so the gate's quarter-tick select is walked
--    until the PHY says a burst landed inside it.
--
-- The report goes out at 115200 8N1 as
--
--   WL <step0> <step1>
--   GT <select> <ok>
--   RD <sixteen hex digits of what came back>
entity boundary is
  port (
    clk_i: in std_ulogic;

    uart_tx_o: out std_ulogic;

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

  -- The slowest bin the part is specified for.  A controller cycle is
  -- four memory ticks, so the fabric runs at a quarter of the memory
  -- rate and every command the bench places lands on the first tick.
  constant tck_ps_c: natural := 2500;
  constant part_c: dram_part_t := h5tq4g63efr_c;
  constant timing_c: dram_timing_t := timings(part_c, tck_ps_c);
  constant dfi_config_c: config_t := config(
    phase_count => 4,
    edge_count => 2,
    dq_width => 16,
    bank_width => 3,
    address_width => 16,
    odt => true,
    reset => true);

  constant lane_c: natural := dfi_config_c.dq_byte_count;
  constant slot_c: natural := slot_count(dfi_config_c);

  constant pll_c: pll_config_t := pll_config(
    input_hz => 50_000_000,
    o0 => pll_output(400_000_000));

  -- Cycles, each one four memory ticks.  The reset and clock-enable
  -- waits are the specification's microseconds turned into cycles.
  constant t_reset_c: natural := 20000;
  constant t_cke_c: natural := 50000;
  constant t_xpr_c: natural := controller_ticks(timing_c.xpr, dfi_config_c.phase_count) + 2;
  constant t_mrd_c: natural := controller_ticks(timing_c.mrd, dfi_config_c.phase_count) + 2;
  constant t_mod_c: natural := controller_ticks(timing_c.mod_update, dfi_config_c.phase_count) + 2;
  constant t_lock_c: natural := controller_ticks(timing_c.dll_lock, dfi_config_c.phase_count) + 2;
  constant t_zq_c: natural := controller_ticks(timing_c.zqinit, dfi_config_c.phase_count) + 2;
  constant t_rp_c: natural := controller_ticks(timing_c.rp, dfi_config_c.phase_count) + 2;
  constant t_rcd_c: natural := controller_ticks(timing_c.rcd, dfi_config_c.phase_count) + 2;
  constant t_rfc_c: natural := controller_ticks(timing_c.rfc, dfi_config_c.phase_count) + 2;
  constant t_wr_c: natural := controller_ticks(timing_c.wr, dfi_config_c.phase_count) + 4;
  -- Forty ticks from the levelling mode register write to the first
  -- strobe, and twenty five more before it may be driven at all.
  constant t_wlmrd_c: natural := 20;
  -- The part answers within seven and a half nanoseconds of the edge.
  constant t_wlo_c: natural := 4;
  -- A read is back well inside this, whatever the gate is doing.
  constant t_rl_c: natural := 8;

  constant wstep_count_c: natural := 256;
  constant gate_count_c: natural := 8;
  -- The gate is a pulse one cycle wide, and which cycle after the read
  -- command it falls on is the coarse half of where it sits; the
  -- quarter-tick select is the fine half.  Both are walked.
  constant gate_cycle_count_c: natural := 4;

  -- What a read of the array is checked against.
  constant pattern_c: byte_string(0 to 15) := from_hex("00112233445566778899aabbccddeeff");

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
    ST_GATE_ACT, ST_GATE_ACT_WAIT,
    ST_GATE_READ, ST_GATE_WAIT, ST_GATE_JUDGE,
    ST_GATE_PRE, ST_GATE_PRE_WAIT,
    ST_WACT, ST_WACT_WAIT, ST_WRITE, ST_WRECOVER,
    ST_READ, ST_READ_WAIT, ST_TAKE,
    ST_SPEAK, ST_PAUSE
    );

  -- "WL ss ss", "GT s v", "RD " and sixteen bytes of it.
  constant wl_line_c: natural := 3 + 2 + 1 + 2 + 2;
  constant gate_line_c: natural := 3 + 1 + 1 + 1 + 2;
  constant read_line_c: natural := 3 + 32 + 2;
  constant report_length_c: natural := wl_line_c + gate_line_c + read_line_c;

  type regs_t is
  record
    state: state_t;
    left: unsigned(19 downto 0);

    -- Write levelling: where the strobe sits, what came back there,
    -- and where the answer first turned.
    levelling: std_ulogic;
    wstep: natural range 0 to wstep_count_c - 1;
    wl_prev: std_ulogic_vector(0 to lane_c - 1);
    wl_found: std_ulogic_vector(0 to lane_c - 1);
    wl_at: natural range 0 to wstep_count_c - 1;
    wl_at1: natural range 0 to wstep_count_c - 1;

    -- Gate training: which quarter tick the capture window sits on.
    gate: natural range 0 to gate_count_c - 1;
    gate_cycle: natural range 0 to gate_cycle_count_c - 1;
    gate_found: std_ulogic;
    gate_at: natural range 0 to gate_count_c - 1;
    gate_cycle_at: natural range 0 to gate_cycle_count_c - 1;

    -- What a read of the array handed back.
    taken: byte_string(0 to 15);
    index: natural range 0 to report_length_c;
    pause: unsigned(26 downto 0);
  end record;

  signal r, rin: regs_t;

  signal clock_s, fast_clock_s, board_clock_s: std_ulogic;
  signal reset_n_s, locked_s, pll_reset_n_s: std_ulogic;

  signal dfi_s: master_t;
  signal dfi_answer_s: slave_t;

  signal write_step_s: std_ulogic_vector(7 downto 0);
  signal read_gate_s: std_ulogic_vector(3 downto 0);
  signal read_gate_select_s: std_ulogic_vector(2 downto 0);
  signal read_gate_ok_s: std_ulogic;
  signal write_level_s: std_ulogic;
  signal write_level_answer_s: std_ulogic_vector(0 to lane_c - 1);

  signal ck_s: nsl_io.diff.diff_pair;
  signal ba_s: unsigned(2 downto 0);
  signal a_s: unsigned(15 downto 0);
  signal dm_s: std_ulogic_vector(lane_c - 1 downto 0);
  signal dqs_s, dqs_n_s, dq_s: nsl_io.io.tristated_vector(0 to 15);
  signal dqs_in_s: std_ulogic_vector(0 to lane_c - 1);
  signal dq_in_s: std_ulogic_vector(0 to 15);

  signal uart_data_s: std_ulogic_vector(7 downto 0);
  signal uart_valid_s, uart_ready_s: std_ulogic;

  -- The fabric clock is divided from the memory rate clock rather
  -- than taken from a second PLL output: the two have to keep a fixed
  -- phase relationship, which separate outputs do not promise.
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

  -- The PLL wants a reset of its own out of configuration before it
  -- will lock.
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
      reset_n_i => pll_reset_n_s,
      clock_o(0) => fast_clock_s,
      locked_o => locked_s
      );

  reset_n_s <= locked_s;

  divider: CLKDIV
    generic map(
      DIV_MODE => "4"
      )
    port map(
      clkout => clock_s,
      calib => '0',
      hclkin => fast_clock_s,
      resetn => locked_s
      );

  phy: nsl_ext_ram.ddr3_io.ddr3_phy_gowin
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c
      )
    port map(
      clock_i => clock_s,
      fast_clock_i => fast_clock_s,
      reset_n_i => reset_n_s,

      dfi_i => dfi_s,
      dfi_o => dfi_answer_s,

      write_step_i => write_step_s,
      write_level_i => write_level_s,
      write_level_answer_o => write_level_answer_s,

      read_gate_i => read_gate_s,
      read_gate_select_i => read_gate_select_s,
      read_gate_ok_o => read_gate_ok_s,

      ck_o => ck_s,
      cke_o => ddr3_cke_o,
      cs_n_o => ddr3_cs_n_o,
      ras_n_o => ddr3_ras_n_o,
      cas_n_o => ddr3_cas_n_o,
      we_n_o => ddr3_we_n_o,
      ba_o => ba_s,
      a_o => a_s,
      odt_o => ddr3_odt_o,
      ram_reset_n_o => ddr3_reset_o,

      dm_o => dm_s,
      dqs_o => dqs_s(0 to lane_c - 1),
      dqs_n_o => dqs_n_s(0 to lane_c - 1),
      dqs_i => dqs_in_s,
      dq_o => dq_s,
      dq_i => dq_in_s
      );

  ddr3_ck_p_o <= ck_s.p;
  ddr3_ck_n_o <= ck_s.n;
  ddr3_ba_o <= std_ulogic_vector(ba_s(2 downto 0));
  ddr3_a_o <= std_ulogic_vector(a_s);
  ddr3_0_dm_o <= dm_s;

  pads: for i in 0 to 15
  generate
    ddr3_0_dq_io(i) <= nsl_io.io.to_logic(dq_s(i));
    dq_in_s(i) <= to_x01(ddr3_0_dq_io(i));
  end generate;

  strobe_pads: for i in 0 to lane_c - 1
  generate
    ddr3_0_dqs_p_io(i) <= nsl_io.io.to_logic(dqs_s(i));
    ddr3_0_dqs_n_io(i) <= nsl_io.io.to_logic(dqs_n_s(i));
    dqs_in_s(i) <= to_x01(ddr3_0_dqs_p_io(i));
  end generate;

  regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;

    if reset_n_s = '0' then
      r.state <= ST_RESET;
      r.left <= to_unsigned(t_reset_c, 20);
      r.levelling <= '0';
      r.wstep <= 0;
      r.wl_prev <= (others => '1');
      r.wl_found <= (others => '0');
      r.wl_at <= 0;
      r.wl_at1 <= 0;
      r.gate <= 0;
      r.gate_cycle <= 0;
      r.gate_found <= '0';
      r.gate_at <= 0;
      r.gate_cycle_at <= 0;
      r.index <= 0;
      r.pause <= (others => '0');
    end if;
  end process;

  transition: process(r, uart_ready_s, dfi_answer_s, read_gate_ok_s,
                      write_level_answer_s) is
    procedure hold(count: natural; next_state: state_t) is
    begin
      rin.left <= to_unsigned(count, 20);
      rin.state <= next_state;
    end procedure;
  begin
    rin <= r;

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
          rin.state <= ST_MR2;
        end if;

      when ST_MR2 =>
        hold(t_mrd_c, ST_MR2_WAIT);

      when ST_MR2_WAIT =>
        if r.left = 0 then
          rin.state <= ST_MR3;
        end if;

      when ST_MR3 =>
        hold(t_mrd_c, ST_MR3_WAIT);

      when ST_MR3_WAIT =>
        if r.left = 0 then
          rin.state <= ST_MR1;
        end if;

      when ST_MR1 =>
        hold(t_mrd_c, ST_MR1_WAIT);

      when ST_MR1_WAIT =>
        if r.left = 0 then
          rin.state <= ST_MR0;
        end if;

      when ST_MR0 =>
        hold(t_mod_c, ST_MR0_WAIT);

      when ST_MR0_WAIT =>
        if r.left = 0 then
          hold(t_lock_c, ST_LOCK);
        end if;

      when ST_LOCK =>
        if r.left = 0 then
          rin.state <= ST_ZQ;
        end if;

      when ST_ZQ =>
        hold(t_zq_c, ST_ZQ_WAIT);

      when ST_ZQ_WAIT =>
        -- Levelling comes before anything is read: where the strobe
        -- sits is what every write after it depends on.
        if r.left = 0 then
          rin.levelling <= '1';
          rin.wstep <= 0;
          rin.wl_prev <= (others => '1');
          rin.wl_found <= (others => '0');
          rin.state <= ST_WL_ON;
        end if;

      when ST_WL_ON =>
        hold(t_wlmrd_c, ST_WL_ON_WAIT);

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
        -- The answer wanted is where the strobe crosses the clock,
        -- which is where it turns from zero to one.  Starting the
        -- walk where it already reads one is ordinary: the strobe
        -- begins past the clock and the crossing turns up later.
        for i in 0 to lane_c - 1
        loop
          rin.wl_prev(i) <= write_level_answer_s(i);
          if write_level_answer_s(i) = '1' and r.wl_prev(i) = '0'
            and r.wl_found(i) = '0' then
            rin.wl_found(i) <= '1';
            if i = 0 then
              rin.wl_at <= r.wstep;
            else
              rin.wl_at1 <= r.wstep;
            end if;
          end if;
        end loop;

        if r.wstep = wstep_count_c - 1 then
          rin.levelling <= '0';
          rin.state <= ST_WL_OFF;
        else
          rin.wstep <= r.wstep + 1;
          rin.state <= ST_WL_SEND;
        end if;

      when ST_WL_OFF =>
        hold(t_mod_c, ST_WL_OFF_WAIT);

      when ST_WL_OFF_WAIT =>
        if r.left = 0 then
          rin.state <= ST_PRECHARGE;
        end if;

      when ST_PRECHARGE =>
        hold(t_rp_c, ST_PRECHARGE_WAIT);

      when ST_PRECHARGE_WAIT =>
        if r.left = 0 then
          rin.state <= ST_REFRESH;
        end if;

      when ST_REFRESH =>
        hold(t_rfc_c, ST_REFRESH_WAIT);

      when ST_REFRESH_WAIT =>
        if r.left = 0 then
          rin.gate <= 0;
          rin.gate_cycle <= 0;
          rin.gate_found <= '0';
          rin.state <= ST_GATE_ACT;
        end if;

      when ST_GATE_ACT =>
        hold(t_rcd_c, ST_GATE_ACT_WAIT);

      when ST_GATE_ACT_WAIT =>
        if r.left = 0 then
          rin.state <= ST_GATE_READ;
        end if;

      when ST_GATE_READ =>
        hold(t_rl_c, ST_GATE_WAIT);

      when ST_GATE_WAIT =>
        -- A burst landing inside the window is what says the gate is
        -- where it should be; the PHY reports it off the lane.
        if read_gate_ok_s = '1' and r.gate_found = '0' then
          rin.gate_found <= '1';
          rin.gate_at <= r.gate;
          rin.gate_cycle_at <= r.gate_cycle;
        end if;

        if r.left = 0 then
          rin.state <= ST_GATE_JUDGE;
        end if;

      when ST_GATE_JUDGE =>
        -- The fine select is walked first; when it runs out the pulse
        -- moves to the next cycle and the walk starts again.
        if r.gate_found = '1'
          or (r.gate = gate_count_c - 1
              and r.gate_cycle = gate_cycle_count_c - 1) then
          rin.state <= ST_GATE_PRE;
        elsif r.gate = gate_count_c - 1 then
          rin.gate <= 0;
          rin.gate_cycle <= r.gate_cycle + 1;
          rin.state <= ST_GATE_READ;
        else
          rin.gate <= r.gate + 1;
          rin.state <= ST_GATE_READ;
        end if;

      when ST_GATE_PRE =>
        hold(t_rp_c, ST_GATE_PRE_WAIT);

      when ST_GATE_PRE_WAIT =>
        if r.left = 0 then
          rin.state <= ST_WACT;
        end if;

      when ST_WACT =>
        hold(t_rcd_c, ST_WACT_WAIT);

      when ST_WACT_WAIT =>
        if r.left = 0 then
          rin.state <= ST_WRITE;
        end if;

      when ST_WRITE =>
        hold(t_wr_c, ST_WRECOVER);

      when ST_WRECOVER =>
        if r.left = 0 then
          rin.state <= ST_READ;
        end if;

      when ST_READ =>
        hold(t_rl_c, ST_READ_WAIT);

      when ST_READ_WAIT =>
        if dfi_answer_s.rddata_valid = '1' then
          for s in 0 to slot_c - 1
          loop
            rin.taken(s * lane_c to s * lane_c + lane_c - 1)
              <= value(dfi_config_c, dfi_answer_s.rddata(s));
          end loop;
        end if;

        if r.left = 0 then
          rin.index <= 0;
          rin.state <= ST_SPEAK;
        end if;

      when ST_TAKE =>
        rin.state <= ST_SPEAK;

      when ST_SPEAK =>
        if uart_ready_s = '1' then
          if r.index = report_length_c - 1 then
            rin.pause <= (others => '1');
            rin.state <= ST_PAUSE;
          else
            rin.index <= r.index + 1;
          end if;
        end if;

      when ST_PAUSE =>
        rin.pause <= r.pause - 1;
        if r.pause = 0 then
          rin.index <= 0;
          rin.state <= ST_SPEAK;
        end if;
    end case;
  end process;

  -- One command a cycle, on the first phase; the PHY puts it on that
  -- phase's tick and leaves the rest of the cycle alone.
  commands: process(r) is
    variable cmd: command_t;
    variable mr: unsigned(15 downto 0);
    variable gate_cycle_now: natural range 0 to gate_cycle_count_c - 1;
  begin
    if r.gate_found = '1' then
      gate_cycle_now := r.gate_cycle_at;
    else
      gate_cycle_now := r.gate_cycle;
    end if;

    dfi_s <= master_idle(dfi_config_c);
    dfi_s.reset_n <= '1';
    write_level_s <= r.levelling;

    mr := (others => '0');
    cmd := command(dfi_config_c, CMD_NOP);

    case r.state is
      when ST_RESET =>
        dfi_s.reset_n <= '0';
        cmd := command(dfi_config_c, CMD_NOP, cke => '0');

      when ST_CKE =>
        cmd := command(dfi_config_c, CMD_NOP, cke => '0');

      when ST_MR2 =>
        -- Write latency five, matching this bin.
        cmd := command(dfi_config_c, CMD_MODE_REGISTER_SET,
                       bank => "010", address => mr);

      when ST_MR3 =>
        cmd := command(dfi_config_c, CMD_MODE_REGISTER_SET,
                       bank => "011", address => mr);

      when ST_MR1 | ST_WL_OFF =>
        -- DLL on, no additive latency, termination off.
        cmd := command(dfi_config_c, CMD_MODE_REGISTER_SET,
                       bank => "001", address => mr);

      when ST_WL_ON =>
        -- Levelling mode, and the termination the procedure needs to
        -- hold the strobe.
        mr(7) := '1';
        mr(2) := '1';
        cmd := command(dfi_config_c, CMD_MODE_REGISTER_SET,
                       bank => "001", address => mr, odt => '1');

      when ST_MR0 =>
        -- Burst of eight, CAS latency six, write recovery six, and a
        -- DLL reset on the way past.
        mr(6 downto 4) := "010";
        mr(8) := '1';
        mr(11 downto 9) := "010";
        cmd := command(dfi_config_c, CMD_MODE_REGISTER_SET,
                       bank => "000", address => mr);

      when ST_ZQ =>
        mr(10) := '1';
        cmd := command(dfi_config_c, CMD_ZQ_CALIBRATION, address => mr);

      when ST_PRECHARGE | ST_GATE_PRE =>
        mr(10) := '1';
        cmd := command(dfi_config_c, CMD_PRECHARGE, address => mr);

      when ST_REFRESH =>
        cmd := command(dfi_config_c, CMD_REFRESH);

      when ST_GATE_ACT | ST_WACT =>
        cmd := command(dfi_config_c, CMD_ACTIVATE,
                       bank => "000", address => (15 downto 0 => '0'));

      when ST_GATE_READ | ST_READ =>
        cmd := command(dfi_config_c, CMD_READ,
                       bank => "000", address => (15 downto 0 => '0'));

      when ST_WRITE =>
        cmd := command(dfi_config_c, CMD_WRITE,
                       bank => "000", address => (15 downto 0 => '0'));

      when others =>
        null;
    end case;

    dfi_s.command(0) <= cmd;

    -- The strobe goes out on a write enable, whether that is a burst
    -- of data or the bare strobe levelling asks for.
    if r.state = ST_WRITE or r.state = ST_WL_SEND then
      dfi_s.wrdata_en <= (others => '1');
    end if;

    if r.state = ST_WRITE then
      for s in 0 to slot_c - 1
      loop
        dfi_s.wrdata(s) <= data(dfi_config_c,
                                pattern_c(s * lane_c to s * lane_c + lane_c - 1));
      end loop;
    end if;

    if r.state = ST_GATE_READ or r.state = ST_GATE_WAIT
      or r.state = ST_READ or r.state = ST_READ_WAIT then
      dfi_s.rddata_en <= (others => '1');
    end if;

    -- One cycle of gate, as many cycles after the read command as the
    -- coarse half of the training says.
    read_gate_s <= (others => '0');
    if (r.state = ST_GATE_WAIT or r.state = ST_READ_WAIT)
      and r.left = t_rl_c - 1 - gate_cycle_now then
      read_gate_s <= (others => '1');
    end if;

    -- Each lane sits where its own answer turned once levelling is
    -- done; while it runs they move together.
    if r.levelling = '1' then
      write_step_s <= std_ulogic_vector(to_unsigned(r.wstep, 8));
    else
      write_step_s <= std_ulogic_vector(to_unsigned(r.wl_at, 8));
    end if;

    if r.gate_found = '1' then
      read_gate_select_s <= std_ulogic_vector(to_unsigned(r.gate_at, 3));
    else
      read_gate_select_s <= std_ulogic_vector(to_unsigned(r.gate, 3));
    end if;
  end process;

  speak: process(r) is
    variable c: std_ulogic_vector(7 downto 0);
    variable column, nibble: natural;
  begin
    c := x"20";

    if r.index < wl_line_c then
      column := r.index;
      case column is
        when 0 => c := x"57";
        when 1 => c := x"4c";
        when 2 => c := x"20";
        when 3 => c := hex(std_ulogic_vector(to_unsigned(r.wl_at / 16, 4)));
        when 4 => c := hex(std_ulogic_vector(to_unsigned(r.wl_at mod 16, 4)));
        when 5 => c := x"20";
        when 6 => c := hex(std_ulogic_vector(to_unsigned(r.wl_at1 / 16, 4)));
        when 7 => c := hex(std_ulogic_vector(to_unsigned(r.wl_at1 mod 16, 4)));
        when 8 => c := x"0d";
        when others => c := x"0a";
      end case;
    elsif r.index < wl_line_c + gate_line_c then
      column := r.index - wl_line_c;
      case column is
        when 0 => c := x"47";
        when 1 => c := x"54";
        when 2 => c := x"20";
        when 3 => c := hex(std_ulogic_vector(
                       to_unsigned(r.gate_cycle_at * 8 + r.gate_at, 5)(3 downto 0)));
        when 4 => c := x"20";
        when 5 => c := hex('0' & '0' & '0' & r.gate_found);
        when 6 => c := x"0d";
        when others => c := x"0a";
      end case;
    else
      column := r.index - wl_line_c - gate_line_c;
      case column is
        when 0 => c := x"52";
        when 1 => c := x"44";
        when 2 => c := x"20";
        when others =>
          if column = read_line_c - 2 then
            c := x"0d";
          elsif column = read_line_c - 1 then
            c := x"0a";
          else
            nibble := column - 3;
            if nibble mod 2 = 0 then
              c := hex(std_ulogic_vector(r.taken(nibble / 2)(7 downto 4)));
            else
              c := hex(std_ulogic_vector(r.taken(nibble / 2)(3 downto 0)));
            end if;
          end if;
      end case;
    end if;

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

end arch;
