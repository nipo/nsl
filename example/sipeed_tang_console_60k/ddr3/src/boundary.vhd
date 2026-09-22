library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_hwdep, nsl_io, nsl_amba, nsl_data, nsl_logic,
  nsl_ext_ram, nsl_usb, nsl_bnoc, gatecap_generated;
use nsl_clocking.pll.all;
use nsl_amba.axi4_mm.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.ddr3.all;

-- Walks an H5TQ4G63EFR through the serialiser DDR3 PHY on a GW5AT-60B.
--
-- The same bench as example/xc7a50t/ddr3, on a family whose pins hold
-- one clock pair each.  Three things follow from that and nothing else
-- differs:
--
--  * the PHY takes shift_strobe_c => true, so the quarter period a
--    write needs leaves on the strobe, the clock and the command pins
--    while both directions of every data pin stay on the unshifted
--    pair.  A GW5A pin refuses two pairs at once (CK0012), which
--    example/sipeed_tang_console_60k/serdes_pin_probe established with
--    the tools rather than with a board;
--  * the strobe readback rides the shifted pair with the driver it
--    shares its pin with, and crosses back to the controller clock on
--    the way to the instruments;
--  * the part is two byte lanes wide, so every word the panel carries
--    of the data bus is twice what the Artix bench carries.
--
-- The numbers the PHY needs are board_c below.  On the Artix they were
-- measured once with the instruments this panel exposes; here the two
-- read figures are placeholders until the same instruments have been
-- run, and the panel's manual bit is what a host sweeps them behind.
entity boundary is
  port(
    clk_i: in std_ulogic;

    -- The fabric's own USB2 port, carrying the rack.
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
    ddr3_reset_n_o: out std_ulogic;
    ddr3_ba_o: out std_ulogic_vector(2 downto 0);
    ddr3_a_o: out std_ulogic_vector(15 downto 0);

    ddr3_0_dm_o: out std_ulogic_vector(1 downto 0);
    ddr3_0_dq_io: inout std_logic_vector(15 downto 0);
    ddr3_0_dqs_p_io: inout std_logic_vector(1 downto 0);
    ddr3_0_dqs_n_io: inout std_logic_vector(1 downto 0)
    );
end entity;

architecture beh of boundary is

  constant board_hz_c: natural := 50000000;
  -- DDR3-800.  The controller sees a quarter of the memory rate
  -- because a burst of eight fills one of its cycles, which is what
  -- puts a 400 MHz part behind a 100 MHz fabric.
  constant tck_ps_c: natural := 2500;
  constant fast_hz_c: natural := 400000000;
  constant ram_hz_c: natural := fast_hz_c / 4;

  -- The plan serdes_pin_probe elaborated: a 1200 MHz VCO with
  -- divisors 12, 3, 3 and 12, and PE_FINE six on both shifted
  -- outputs.  Six eighths of a VCO cycle is 625 ps, which is a quarter
  -- of a memory period said once per clock -- a quarter of the fast
  -- clock's turn and a sixteenth of the controller clock's.  The two
  -- shifts landing on the same number is the check that matters: the
  -- pair has to move together, or the strobe leaves the data behind.
  --
  -- An output whose rate or phase misses the solver's grid is left
  -- disabled rather than approximated, so four enabled outputs is what
  -- says the plan is buildable and not merely asked for.
  constant ram_config_c: pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(ram_hz_c),
    o1 => pll_output(fast_hz_c),
    o2 => pll_output(fast_hz_c, phase => (num => 1, den => 4)),
    o3 => pll_output(ram_hz_c, phase => (num => 1, den => 16)));

  -- What this board measured of the PHY, with the instruments the
  -- panel below carries.
  --
  -- The constant lives here and not in nsl_ext_ram because it is a
  -- property of this board, the way its pinout is: the library carries
  -- the shape, a design carries the numbers.
  --
  -- Four of the six are what the family says rather than what the
  -- board says, and are known before a measurement:
  --
  --  * write_slip is measured, and a slot short of nominal.  The
  --    strobe's group is the one that crosses to the shifted clock
  --    here and a real OSER8 takes its parallel word on a parallel
  --    edge, so there is no whole-word transfer for the data to lose
  --    -- unlike the 7-series, whose data serialiser hands its word a
  --    cycle early and wants slip 0.  The remaining slot is the
  --    strobe's crossing arriving a beat ahead of the data it clocks:
  --    at eight the part drops the first beat of every burst and
  --    stores the other seven, at six it drops the last, at seven the
  --    burst comes back whole.
  --  * both enable leads are zero.  A GW5A pad's tristate is per pair
  --    and travels with the word its own serialiser presents.
  --  * strobe_invert is false, which is the sense the schedule holds.
  --
  -- The two read figures are the measurement.  The offset is past what
  -- a six bit port could say -- this design's own write burst is 67
  -- slots from its own command where the Artix's is at 33, and a read
  -- answer sits a few slots past it -- so read_offset_i carries seven
  -- bits and the PHY's announcement queue reaches the far end of them.
  -- A line of 256 taps of about 12.5 ps spans some three slots, so the
  -- offset either side of this one answers over a run of its own,
  -- which is the same window reached a beat earlier and a beat later.
  --
  -- The tap is the middle of the run the *array* answers over and not
  -- of the run the part's own training pattern answers over, and the
  -- two are not the same: the training pattern alternates every beat,
  -- which is the easiest traffic there is, and it reads back over 73
  -- taps centred on 52 where a walk of 1024 beats is clean over 41
  -- taps, 27 to 67.  ``dataeye.py`` is what maps the second one.
  constant board_c: nsl_ext_ram.ddr3_io.serdes_board_t := (
    read_offset => 70,
    read_tap => 47,
    write_slip => 7,
    dq_enable_lead => 0,
    dqs_enable_lead => 0,
    strobe_invert => false
    );

  constant part_c: dram_part_t := h5tq4g63efr_c;
  constant timing_c: dram_timing_t := timings(part_c, tck_ps_c);
  constant dfi_config_c: nsl_ext_ram.dfi.config_t := dfi_config(part_c);
  -- On-die termination at RZQ/4, sixty ohms.  The part's own receivers
  -- are what a write drives into, and this is the only thing that
  -- terminates them: nothing on the board does.  A command pin is held
  -- for a whole memory period and survives an open line; a data pin is
  -- held for half of one and does not.
  constant script_c: nsl_ext_ram.dram.init_script_t
    := nsl_ext_ram.dram.ddr3_init_script(part_c, timing_c,
                                         dfi_config_c.phase_count,
                                         rtt_nom_divisor => 4);

  constant axi_config_c: config_t := axi_config(part_c);
  constant lane_c: natural := part_c.dq_width / 8;
  constant beat_byte_c: natural := cycle_byte_count(part_c);

  -- The core's own address map for this part, so that the regions
  -- below are read off it rather than picked.  An access carries
  -- sixteen bytes, so address bits 4 to 10 are the column, 11 to 13
  -- the bank and 14 up the row: a page is two kilobytes, the bank
  -- turns over every two of them and the row every sixteen.  A
  -- contiguous region therefore cannot reach a second row without
  -- having crossed every bank boundary first, and the ladder between
  -- the probe and the whole part is banks, then banks and rows.
  constant layout_c: nsl_ext_ram.dram.layout_t
    := nsl_ext_ram.dram.layout(part_c, dfi_config_c, part_c.prefetch_l2);

  -- The whole part: eight banks of thirty-two thousand rows of two
  -- kilobytes, half a gigabyte.
  constant region_byte_l2_c: natural := layout_c.byte_address_width;
  -- Sixteen accesses, which crosses a burst boundary and costs nothing
  -- at a point of the training sweep.
  constant probe_byte_l2_c: natural := layout_c.access_byte_count_l2 + 4;
  -- Every bank at row zero: seven bank crossings, no row change, every
  -- row left open and nothing precharged.  It is also the first size
  -- that asks for four activates inside a window.
  constant bank_byte_l2_c: natural := layout_c.row_low;
  -- The first row crossing on top of that, which is the first
  -- precharge and reactivate a walk meets.
  constant row_byte_l2_c: natural := layout_c.row_low + 1;
  -- Half the part each, which is the top row bit either way.  A14 is
  -- the highest address pin this density uses, so the lower half is
  -- every place A14 addresses with it low and the upper half is every
  -- place it addresses with it high.  Neither half ever changes that
  -- pin, so a half that walks clean says the fault of the whole part
  -- is not anything the other thirteen row bits, the three bank bits
  -- or the column do.
  constant half_byte_l2_c: natural := layout_c.byte_address_width - 1;
  constant half_base_c: natural := 2 ** half_byte_l2_c;

  signal board_s: std_ulogic;
  signal raw_s: std_ulogic_vector(0 to ram_config_c.output_count - 1);
  signal ram_s, fast_s, data_s, shifted_s: std_ulogic;
  signal startup_reset_n_s, locked_s, ram_reset_n_s: std_ulogic;
  signal probe_reset_n_s, walk_reset_n_s: std_ulogic;
  signal bank_reset_n_s, row_reset_n_s: std_ulogic;
  signal low_reset_n_s, high_reset_n_s: std_ulogic;
  signal bus_reset_n_s, ctrl_reset_n_s, part_up_s: std_ulogic;

  -- The bus as the walkers see it, and the bus as the controller
  -- sees it.  They are the same on every channel but the read data,
  -- where a register slice sits between them.
  signal axi_s, mem_s: bus_t;
  signal probe_axi_s, walk_axi_s, bank_axi_s, row_axi_s: master_t;
  signal low_axi_s, high_axi_s: master_t;
  signal ready_s: std_ulogic;

  signal cmd_s: nsl_ext_ram.burst.cmd_t;
  signal cmd_ack_s: nsl_ext_ram.burst.cmd_ack_t;
  signal wdata_s: nsl_ext_ram.burst.wdata_t;
  signal wdata_ack_s: nsl_ext_ram.burst.wdata_ack_t;
  signal rdata_s: nsl_ext_ram.burst.rdata_t;
  signal rdata_ack_s: nsl_ext_ram.burst.rdata_ack_t;

  signal dfi_master_s, dfi_phy_s: nsl_ext_ram.dfi.master_t;
  signal dfi_slave_s: nsl_ext_ram.dfi.slave_t;

  -- Cycles to hold after each step of the levelling sequence.  Every
  -- delay it stands in for -- tRP, tMOD, tWLMRD, tWLDQSEN -- is tens
  -- of memory ticks at most, and nothing here is in a hurry.
  constant level_wait_c: natural := 256;
  -- Cycles between strobe bursts while levelling, long enough that the
  -- answer has settled before a host reads it.
  constant level_period_c: natural := 64;

  type level_state_t is (
    LEVEL_OFF,
    LEVEL_PRECHARGE,
    LEVEL_ENTER,
    LEVEL_PULSE,
    LEVEL_EXIT,
    -- The part's own test pattern, which is the way out of a circle:
    -- read training checks a payload the walker wrote, and a write
    -- cannot be checked until reads are trained.  In multi purpose
    -- register mode every read answers with a pattern the part holds
    -- rather than with the array, so the read path can be trained
    -- against something known before a single write is trusted.
    MPR_PRECHARGE,
    MPR_ENTER,
    MPR_READ,
    MPR_SETTLE,
    MPR_EXIT,
    -- One burst, written and read back with every field under a
    -- host's hand.  Nothing between the panel and the pins belongs to
    -- the controller here: no core scheduling the write, no adapter
    -- cutting a transaction up, no walker deciding what the payload
    -- should have been.  What comes back is what this PHY put on the
    -- wire and what the part made of it, and nothing else.
    POKE_PRECHARGE,
    -- Mode register 1 rewritten on the way past, for the one bit of
    -- the data group nothing else can reach: bit A11 enables TDQS, and
    -- a part with TDQS enabled supports no data mask.  An MRS wants
    -- every bank precharged, which the step before just did.
    POKE_MRS,
    POKE_ACTIVATE,
    POKE_WRITE,
    POKE_SETTLE,
    POKE_READ,
    POKE_PRECHARGE_AGAIN,
    POKE_REFRESH,
    POKE_GAP
    );

  signal level_state_s: level_state_t;
  signal level_wait_s: natural range 0 to level_wait_c;
  signal level_tick_s: natural range 0 to level_period_c;
  signal level_active_s, write_level_s: std_ulogic;
  -- What the sequence is doing and how many strobe bursts it has
  -- asked for.  A panel that cannot see this cannot tell a sequence
  -- that never started from one whose bursts go nowhere.
  signal level_step_s: unsigned(4 downto 0);
  signal level_burst_s: unsigned(7 downto 0);

  -- Mode register 3: the multi purpose register, and which of its
  -- patterns.  Zero on both is the predefined one, which reads as
  -- alternating bits on every data line.
  function mr3_value(mpr: boolean) return unsigned
  is
    variable v: unsigned(nsl_ext_ram.dfi.max_address_width_c - 1 downto 0)
      := (others => '0');
  begin
    if mpr then
      v(2) := '1';
    end if;

    return v;
  end function;

  -- Mode register 1 as the init script wrote it: DLL on, no additive
  -- latency, drive strength RZQ/6, termination RZQ/4.  Bit seven is
  -- what this function exists for.
  function mr1_value(level: boolean; tdqs: std_ulogic := '0')
    return unsigned
  is
    variable v: unsigned(nsl_ext_ram.dfi.max_address_width_c - 1 downto 0)
      := (others => '0');
  begin
    v(2) := '1';
    if level then
      v(7) := '1';
    end if;
    v(11) := tdqs;

    return v;
  end function;

  -- A write command with auto precharge closes the row behind it.
  -- That is the one thing a write does which needs no data path at
  -- all, so a read on the row afterwards says whether the part acted
  -- on the command -- and a write that is never decoded cannot be
  -- told from one whose burst goes astray, without it.
  function write_address(auto_precharge: std_ulogic) return unsigned
  is
    variable v: unsigned(nsl_ext_ram.dfi.max_address_width_c - 1 downto 0)
      := (others => '0');
  begin
    v(10) := auto_precharge;

    return v;
  end function;

  function all_banks return unsigned
  is
    variable v: unsigned(nsl_ext_ram.dfi.max_address_width_c - 1 downto 0)
      := (others => '0');
  begin
    v(10) := '1';

    return v;
  end function;

  signal probe_busy_s, probe_done_s: std_ulogic;
  signal probe_errors_s: unsigned(31 downto 0);
  signal probe_first_s: unsigned(axi_config_c.address_width - 1 downto 0);
  signal walk_busy_s, walk_done_s: std_ulogic;
  signal walk_errors_s: unsigned(31 downto 0);
  signal walk_first_s: unsigned(axi_config_c.address_width - 1 downto 0);
  signal bank_busy_s, bank_done_s: std_ulogic;
  signal bank_errors_s: unsigned(31 downto 0);
  signal bank_first_s: unsigned(axi_config_c.address_width - 1 downto 0);
  signal row_busy_s, row_done_s: std_ulogic;
  signal row_errors_s: unsigned(31 downto 0);
  signal row_first_s: unsigned(axi_config_c.address_width - 1 downto 0);
  signal low_busy_s, low_done_s: std_ulogic;
  signal low_errors_s: unsigned(31 downto 0);
  signal low_first_s: unsigned(axi_config_c.address_width - 1 downto 0);
  signal high_busy_s, high_done_s: std_ulogic;
  signal high_errors_s: unsigned(31 downto 0);
  signal high_first_s: unsigned(axi_config_c.address_width - 1 downto 0);
  signal busy_s, done_s: std_ulogic;
  signal error_count_s: unsigned(31 downto 0);
  signal first_error_s: unsigned(axi_config_c.address_width - 1 downto 0);

  -- Panel controls
  signal run_s, level_s, tick_s: std_ulogic;
  signal full_s: unsigned(2 downto 0);

  -- The same selector, registered in the memory domain.  The panel's
  -- own copy comes out of a resynchroniser that lives with the rack,
  -- and every use of it here is half the die away: it releases one
  -- walker's reset and it picks one of four masters for the adapter.
  -- Registered here, the rack's distance and the mux each get a cycle
  -- of their own.  Which walker runs changes only between runs, so a
  -- cycle of lag on it is nothing the bus can see.
  signal full_r_s: unsigned(2 downto 0);
  signal offset_s: unsigned(6 downto 0);
  signal slip_s: unsigned(3 downto 0);
  signal odt_s: std_ulogic;
  signal force_s: unsigned(1 downto 0);
  signal dq_lead_s, dqs_lead_s: unsigned(3 downto 0);
  signal dqs_invert_s: std_ulogic;
  signal manual_s: std_ulogic;
  signal mpr_s: std_ulogic;
  signal poke_s: std_ulogic;
  signal poke_value_s: unsigned(7 downto 0);
  signal poke_ap_s: std_ulogic;
  signal snoop_s, tdqs_s: std_ulogic;

  -- What the PHY is actually given: the panel's copy while an
  -- instrument is sweeping, the board record otherwise.
  signal phy_offset_s: unsigned(6 downto 0);
  signal phy_slip_s: unsigned(3 downto 0);
  signal phy_dq_lead_s, phy_dqs_lead_s: unsigned(3 downto 0);
  signal phy_invert_s: std_ulogic;
  signal mpr_data_s: std_ulogic_vector(beat_byte_c * 8 - 1 downto 0);
  signal mpr_count_s: unsigned(7 downto 0);

  signal tick_seen_s: std_ulogic;
  signal delay_step_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);
  signal delay_mark_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);
  signal level_answer_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  signal ram_ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0);
  signal ram_a_s: unsigned(nsl_ext_ram.ddr3.address_width(part_c) - 1 downto 0);
  signal ck_s: nsl_io.diff.diff_pair;
  signal dm_s: std_ulogic_vector(lane_c - 1 downto 0);

  signal dqs_out_s, dqs_n_out_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);
  signal dqs_in_s, dqs_delayed_s: std_ulogic_vector(lane_c - 1 downto 0);
  signal dq_out_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal dq_in_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  -- The strobe pin as the input serialiser it shares its pad with
  -- hands it over, a lane at a time.  Eight slots a cycle, in the
  -- shifted domain the pad's driver runs in.
  type lane_word_t is array (natural range <>) of std_ulogic_vector(0 to 7);
  signal dqs_shifted_s: lane_word_t(0 to lane_c - 1);
  signal dqs_caught_s: lane_word_t(0 to lane_c - 1);
  signal strobe_high_s, strobe_low_s: lane_word_t(0 to lane_c - 1);
  -- The strobe pin as the two most recent cycles caught it, oldest
  -- slot of the older cycle first, and the eight slots of it the read
  -- offset points at.
  type lane_window_t is array (natural range <>) of std_ulogic_vector(0 to 15);
  signal dqs_window_s: lane_window_t(0 to lane_c - 1);
  signal strobe_pick_s, strobe_word_s: lane_word_t(0 to lane_c - 1);
  -- The slot the window is read out at, taken off the panel's offset a
  -- cycle before the read.
  signal pick_slot_s: unsigned(2 downto 0);

  -- The first beat a walk reads back, whole, and the count of beats
  -- that have come back at all.  Between them they separate a bus
  -- nobody is driving from one driven at the wrong moment, which no
  -- error count can.
  signal first_read_s: std_ulogic_vector(beat_byte_c * 8 - 1 downto 0);
  signal got_read_s: std_ulogic;
  signal read_count_s: unsigned(31 downto 0);

  -- Every channel of the bus the selected walker drives, counted on
  -- its own handshake.  A walker that raises busy and returns nothing
  -- says no more than that through an error count; which of these
  -- stopped moving says which side of which transfer it is waiting on,
  -- and the last address accepted each way says where in the region it
  -- got to.
  signal aw_count_s, w_count_s, b_count_s, ar_count_s: unsigned(31 downto 0);
  signal last_aw_s, last_ar_s:
    unsigned(axi_config_c.address_width - 1 downto 0);

  -- What the core asked the part for, by kind.  A bus that stops
  -- advancing is either a controller that has stopped issuing or a
  -- controller issuing into a part that is not answering, and these
  -- tell the two apart.
  signal act_count_s, pre_count_s, wr_count_s: unsigned(31 downto 0);
  signal rd_count_s, ref_count_s, mrs_count_s: unsigned(31 downto 0);

  -- Which of the six a cycle carried, one bit each, registered beside
  -- the controller.  The counters themselves are read by the rack and
  -- so sit with the rest of the panel's instruments, half the die away
  -- from the controller that feeds them; what crossed that distance
  -- used to be the decode of the command the core had just issued, and
  -- it arrived as the enable of a thirty-two bit counter.  Registered
  -- here the decode is short and the crossing has a whole cycle, at
  -- the cost of the totals standing a cycle behind the bus.
  signal count_step_s: std_ulogic_vector(5 downto 0);
  constant count_act_c: natural := 0;
  constant count_pre_c: natural := 1;
  constant count_wr_c: natural := 2;
  constant count_rd_c: natural := 3;
  constant count_ref_c: natural := 4;
  constant count_mrs_c: natural := 5;

  -- Both sides of every handshake as they stand, rather than counted.
  -- A bus where nothing moves at all has one side of one channel
  -- waiting on the other, and no count of transfers that did not
  -- happen says which side it is.
  signal handshake_s: unsigned(9 downto 0);

  -- The whole word the capture records, a cycle after the cycle it
  -- describes.  Every field of it is registered together, the two
  -- trigger sources with the rest, so nothing in a window moves
  -- against anything else in it.
  --
  -- One controller cycle of the data bus each way, flattened with slot
  -- zero -- the earliest on the wire -- in the low byte.  The write
  -- side is taken on the PHY side of the sequencer mux, so a burst the
  -- sequencer laid down is caught alongside the ones the core does.
  signal cap_wrdata_s, cap_rddata_s:
    std_ulogic_vector(beat_byte_c * 8 - 1 downto 0);
  -- Phase zero of the command slot as the pins carry it, undecoded.
  signal cap_cs_n_s, cap_ras_n_s, cap_cas_n_s, cap_we_n_s: std_ulogic;
  signal cap_bank_s: std_ulogic_vector(2 downto 0);
  signal cap_address_s: std_ulogic_vector(14 downto 0);
  signal cap_wrdata_en_s, cap_rddata_valid_s: std_ulogic;
  -- A pass that has gone wrong, enough of the count to say which beat
  -- of it did, and a beat the walker took off the read channel.  All
  -- three are the selected walker's, as everything else the panel
  -- reports is.
  signal cap_error_s, cap_r_beat_s: std_ulogic;
  signal cap_error_count_s: std_ulogic_vector(7 downto 0);
  -- The cycle a pass begins on, for the capture to be armed on.
  signal cap_run_s: std_ulogic;

  -- The rack and its transport, on the soft USB2 PHY's own clock.
  constant clock_usb_hz_c: natural := 60000000;
  constant max_txn_length_l2_c: natural := 5;

  signal clock_usb_s, usb_reset_n_s, app_reset_n_s, rack_reset_n_s: std_ulogic;
  signal utmi_s: nsl_usb.utmi.utmi8_bus;

  type pipe_io is
  record
    cmd, rsp: nsl_bnoc.pipe.pipe_bus_t;
  end record;
  signal rack_pipe_s: pipe_io;

  -- A 128 bit bus does not fit a status word, so every reading of it
  -- the panel carries is four of them, word zero holding the four
  -- earliest slots.
  function word_of(v: std_ulogic_vector; index: natural) return unsigned
  is
    alias a: std_ulogic_vector(v'length - 1 downto 0) is v;
  begin
    return unsigned(a(32 * index + 31 downto 32 * index));
  end function;

begin

  board_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => board_s
      );

  startup_reset: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => board_s,
      reset_n_o => startup_reset_n_s
      );

  ram_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ram_config_c
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,
      clock_o => raw_s,
      locked_o => locked_s
      );

  -- Straight off the block, with no buffer in between.  A serialiser
  -- wants a settled relationship between its fast clock and its
  -- parallel one, and on this family the two come out of one block
  -- already on the clock network: a buffer inserted on one of four
  -- outputs is a skew between them that nothing states.
  ram_s <= raw_s(0);
  fast_s <= raw_s(1);
  data_s <= raw_s(2);
  shifted_s <= raw_s(3);

  memory_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => ram_s,
      data_i => locked_s,
      data_o => ram_reset_n_s
      );

  -- A walker stops for good once it is done, so a new run needs it
  -- taken back to reset.  That is what the panel's run bit does.
  --
  -- The adapter and the core are taken back with it, and that is not a
  -- convenience.  A master reset in the middle of a transaction leaves
  -- its slave waiting for a beat that will never come: the adapter
  -- holds the address and the payload of a transaction whose master
  -- has gone, the core holds an access whose write data it will never
  -- be handed, and nothing in either protocol gets them out again.
  -- Sharing the reset means every run starts from the state the
  -- benches cover -- every side of the bus out of reset together --
  -- and costs the part's power-up sequence at the front of each run.
  bus_reset_n_s <= ram_reset_n_s and run_s;

  selector: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      full_r_s <= (others => '0');
    elsif rising_edge(ram_s) then
      full_r_s <= full_s;
    end if;
  end process;

  -- Which walker that reset reaches: the selected one.  The other
  -- five are held down so they keep off the bus.
  probe_reset_n_s <= bus_reset_n_s when full_r_s = 0 else '0';
  walk_reset_n_s <= bus_reset_n_s when full_r_s = 1 else '0';
  bank_reset_n_s <= bus_reset_n_s when full_r_s = 2 else '0';
  row_reset_n_s <= bus_reset_n_s when full_r_s = 3 else '0';
  low_reset_n_s <= bus_reset_n_s when full_r_s = 4 else '0';
  high_reset_n_s <= bus_reset_n_s when full_r_s = 5 else '0';

  -- The one thing that does not wait for the run is the first
  -- bring-up.  A control register of this family comes out of
  -- configuration at zero, so the run is down until a host raises it,
  -- and a core held in reset until then would hold the part in reset
  -- with it: every instrument on this panel but the walkers works
  -- with the run down, and each of them wants a part that has been
  -- through its power-up sequence.  So the design's own reset is what
  -- releases the adapter and the core until that sequence has played
  -- once, and the run owns their reset from then on.
  --
  -- Nothing is on the bus while it plays: the walkers wait for the
  -- run either way, so the transaction this reset would cut in half
  -- does not exist yet.
  ctrl_reset_n_s <= ram_reset_n_s when part_up_s = '0' else bus_reset_n_s;

  axi_s.m <= walk_axi_s when full_r_s = 1
             else bank_axi_s when full_r_s = 2
             else row_axi_s when full_r_s = 3
             else low_axi_s when full_r_s = 4
             else high_axi_s when full_r_s = 5
             else probe_axi_s;

  probe: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => probe_byte_l2_c,
      burst_length_c => 4,
      seed_c => 20260915,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => probe_reset_n_s,
      start_i => '1',
      axi_o => probe_axi_s,
      axi_i => axi_s.s,
      busy_o => probe_busy_s,
      done_o => probe_done_s,
      error_count_o => probe_errors_s,
      first_error_address_o => probe_first_s
      );

  walk: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => 8,
      seed_c => 20260916,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => walk_reset_n_s,
      start_i => '1',
      axi_o => walk_axi_s,
      axi_i => axi_s.s,
      busy_o => walk_busy_s,
      done_o => walk_done_s,
      error_count_o => walk_errors_s,
      first_error_address_o => walk_first_s
      );

  -- Every bank of row zero, and the same with a second row on top.
  -- Between the probe, which never leaves one page, and the whole
  -- part, which meets everything at once, these are the two steps the
  -- address map has: a bank crossing and then a row crossing.  Each
  -- carries its own seed so that a payload cannot be read back from
  -- what another walker left.
  bank_walk: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => bank_byte_l2_c,
      burst_length_c => 8,
      seed_c => 20260917,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => bank_reset_n_s,
      start_i => '1',
      axi_o => bank_axi_s,
      axi_i => axi_s.s,
      busy_o => bank_busy_s,
      done_o => bank_done_s,
      error_count_o => bank_errors_s,
      first_error_address_o => bank_first_s
      );

  row_walk: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => row_byte_l2_c,
      burst_length_c => 8,
      seed_c => 20260918,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => row_reset_n_s,
      start_i => '1',
      axi_o => row_axi_s,
      axi_i => axi_s.s,
      busy_o => row_busy_s,
      done_o => row_done_s,
      error_count_o => row_errors_s,
      first_error_address_o => row_first_s
      );

  -- One half of the part each, and the top row bit is what tells them
  -- apart.  A14 is the pin a whole-part walk fails on and the pin
  -- neither of these ever changes: the lower half addresses every
  -- bank, row and column this part has with A14 held low, the upper
  -- half does the same with it held high.  Which of the two fails
  -- says which edge of that pin the part misses, and a half that
  -- walks clean at the size the whole part fails at clears everything
  -- but A14.
  --
  -- The upper half starts where the lower one ends, so between them
  -- they are the whole part written twice and read twice, with the
  -- one transition the whole-part walk makes taken out.
  low_walk: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => half_byte_l2_c,
      burst_length_c => 8,
      seed_c => 20260919,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => low_reset_n_s,
      start_i => '1',
      axi_o => low_axi_s,
      axi_i => axi_s.s,
      busy_o => low_busy_s,
      done_o => low_done_s,
      error_count_o => low_errors_s,
      first_error_address_o => low_first_s
      );

  high_walk: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      base_address_c => half_base_c,
      region_byte_l2_c => half_byte_l2_c,
      burst_length_c => 8,
      seed_c => 20260920,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => high_reset_n_s,
      start_i => '1',
      axi_o => high_axi_s,
      axi_i => axi_s.s,
      busy_o => high_busy_s,
      done_o => high_done_s,
      error_count_o => high_errors_s,
      first_error_address_o => high_first_s
      );

  -- One register stage on the way back from the controller, and only
  -- there.
  --
  -- A read beat leaves the core's drain cursor, crosses the adapter's
  -- own logic and lands on a comparison inside every walker at once:
  -- four testers mirror the 128 bit bus and the cursor alone reaches
  -- some 772 loads, of which one walker's are live and three are held
  -- in reset.  That is a cycle spent on fanout that carries nothing,
  -- and it is the read channel's whole path from the memory to the
  -- checker.  A slice cuts it in half: what leaves the register is a
  -- beat, and what the walkers do with it is their own cycle.
  --
  -- One slice for all four, because only one walker runs.  It is a
  -- skid buffer rather than a plain register, so a beat is never
  -- dropped when a walker holds its ready down, and the read channel
  -- keeps a beat a cycle.
  --
  -- The other four channels pass through: an address or a write beat
  -- comes out of the selected walker's own register and reaches the
  -- adapter, which is one mux and no fanout to speak of.
  mem_s.m.aw <= axi_s.m.aw;
  mem_s.m.w <= axi_s.m.w;
  mem_s.m.b <= axi_s.m.b;
  mem_s.m.ar <= axi_s.m.ar;
  axi_s.s.aw <= mem_s.s.aw;
  axi_s.s.w <= mem_s.s.w;
  axi_s.s.b <= mem_s.s.b;
  axi_s.s.ar <= mem_s.s.ar;

  read_stage: nsl_amba.mm_fifo.axi4_mm_r_slice
    generic map(
      config_c => axi_config_c
      )
    port map(
      clock_i => ram_s,
      reset_n_i => ctrl_reset_n_s,

      in_i => mem_s.s.r,
      in_o => mem_s.m.r,

      out_o => axi_s.s.r,
      out_i => axi_s.m.r
      );

  adapter: nsl_ext_ram.frontend.axi4_mm_burst_adapter
    generic map(
      axi_config_c => axi_config_c,
      cycle_byte_count_c => beat_byte_c,
      burst_cycle_count_c => 1
      )
    port map(
      clock_i => ram_s,
      reset_n_i => ctrl_reset_n_s,

      axi_i => mem_s.m,
      axi_o => mem_s.s,

      cmd_o => cmd_s,
      cmd_i => cmd_ack_s,
      wdata_o => wdata_s,
      wdata_i => wdata_ack_s,
      rdata_i => rdata_s,
      rdata_o => rdata_ack_s,

      ready_i => ready_s
      );

  core: nsl_ext_ram.dram.dram_core
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      script_c => script_c,
      burst_length_l2_c => part_c.prefetch_l2,
      keep_row_open_c => true,
      -- Both ends of the column pipeline run at tCCD on this board, as
      -- they do behind ddr3_controller: the PHY lays write bursts back
      -- to back with no preamble between them and reads the read
      -- announcement a cycle of level per cycle of answer, so a read
      -- may be announced every cycle.  A read is answered
      -- read_offset / 8 + 3 cycles after its command, and this
      -- family's round trip is long: the write burst alone sits
      -- sixty-seven slots from its command here against the Artix's
      -- thirty-three, so an answer is near seventy and thirteen is
      -- what that asks for.  The PHY's own queue reaches the far end
      -- of the offset port; this is what the controller keeps in
      -- flight, and every cycle of it is a burst of read data buffered
      -- beside the walkers.
      read_ahead_c => 13,
      write_overlap_c => true
      )
    port map(
      clock_i => ram_s,
      reset_n_i => ctrl_reset_n_s,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,
      wdata_i => wdata_s,
      wdata_o => wdata_ack_s,
      rdata_o => rdata_s,
      rdata_i => rdata_ack_s,

      ready_o => ready_s,

      dfi_o => dfi_master_s,
      dfi_i => dfi_slave_s
      );

  -- Whether the core has played the part's power-up sequence since the
  -- design was configured.
  --
  -- The core's own ready line goes down with the run, because the run
  -- takes the core back to the first step of that sequence.  What a
  -- host asks when it asks whether the controller is ready is whether
  -- the sequence has run at all -- against a clock that never came up
  -- or a part that never answered -- and that answer may not move with
  -- a control bit, so it is latched here and cleared only by the
  -- design's own reset.  Whether the bus can take a transaction at
  -- this instant is the other question, and the handshake word below
  -- is what answers it.
  part_up: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      part_up_s <= '0';
    elsif rising_edge(ram_s) then
      if ready_s = '1' then
        part_up_s <= '1';
      end if;
    end if;
  end process;

  -- Write levelling, driven straight at the DFI.
  --
  -- The part answers on its data lines with what it sampled of CK on
  -- each rising strobe edge, which is the one direct reading of where
  -- the strobe arrives.  Getting it into that mode is a mode register
  -- write, and the core's script plays once at reset with no way to
  -- issue another, so the bus is taken off the core while this runs.
  -- Refreshes are missed meanwhile; nothing here keeps data across a
  -- levelling pass, and the walk that follows writes it all again.
  leveller: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      level_state_s <= LEVEL_OFF;
      level_wait_s <= 0;
      level_tick_s <= 0;
    elsif rising_edge(ram_s) then
      if level_wait_s /= 0 then
        level_wait_s <= level_wait_s - 1;
      end if;

      if level_tick_s /= 0 then
        level_tick_s <= level_tick_s - 1;
      else
        level_tick_s <= level_period_c;
      end if;

      case level_state_s is
        when LEVEL_OFF =>
          if level_s = '1' then
            level_state_s <= LEVEL_PRECHARGE;
            level_wait_s <= level_wait_c;
          elsif mpr_s = '1' then
            level_state_s <= MPR_PRECHARGE;
            level_wait_s <= level_wait_c;
          elsif poke_s = '1' then
            level_state_s <= POKE_PRECHARGE;
            level_wait_s <= level_wait_c;
          end if;

        when LEVEL_PRECHARGE =>
          if level_wait_s = 0 then
            level_state_s <= LEVEL_ENTER;
            level_wait_s <= level_wait_c;
          end if;

        when LEVEL_ENTER =>
          if level_wait_s = 0 then
            level_state_s <= LEVEL_PULSE;
            level_tick_s <= level_period_c;
          end if;

        when LEVEL_PULSE =>
          if level_s = '0' then
            level_state_s <= LEVEL_EXIT;
            level_wait_s <= level_wait_c;
          end if;

        when LEVEL_EXIT =>
          if level_wait_s = 0 then
            level_state_s <= LEVEL_OFF;
          end if;

        when MPR_PRECHARGE =>
          if level_wait_s = 0 then
            level_state_s <= MPR_ENTER;
            level_wait_s <= level_wait_c;
          end if;

        when MPR_ENTER =>
          if level_wait_s = 0 then
            level_state_s <= MPR_READ;
            level_tick_s <= level_period_c;
          end if;

        when MPR_READ =>
          -- Turning the register off with a row still open is quietly
          -- ignored and every later read answers from the register, so
          -- the way out goes through a precharge like the way in.
          if mpr_s = '0' then
            level_state_s <= MPR_SETTLE;
            level_wait_s <= level_wait_c;
          end if;

        when MPR_SETTLE =>
          if level_wait_s = 0 then
            level_state_s <= MPR_EXIT;
            level_wait_s <= level_wait_c;
          end if;

        when MPR_EXIT =>
          if level_wait_s = 0 then
            level_state_s <= LEVEL_OFF;
          end if;

        when POKE_PRECHARGE =>
          if level_wait_s = 0 then
            level_state_s <= POKE_MRS;
            level_wait_s <= level_wait_c;
          end if;

        -- A whole step of quiet behind the mode register write, which
        -- is tMOD many times over.
        when POKE_MRS =>
          if level_wait_s = 0 then
            level_state_s <= POKE_ACTIVATE;
            level_wait_s <= level_wait_c;
          end if;

        when POKE_ACTIVATE =>
          if level_wait_s = 0 then
            level_state_s <= POKE_WRITE;
            level_wait_s <= level_wait_c;
          end if;

        when POKE_WRITE =>
          if level_wait_s = 0 then
            level_state_s <= POKE_SETTLE;
            level_wait_s <= level_wait_c;
          end if;

        when POKE_SETTLE =>
          -- The row stays open, so the read that follows is the
          -- tightest test there is of what the write put in it.
          if level_wait_s = 0 then
            level_state_s <= POKE_READ;
            level_wait_s <= level_wait_c;
          end if;

        when POKE_READ =>
          if level_wait_s = 0 then
            level_state_s <= POKE_PRECHARGE_AGAIN;
            level_wait_s <= level_wait_c;
          end if;

        when POKE_PRECHARGE_AGAIN =>
          if level_wait_s = 0 then
            level_state_s <= POKE_REFRESH;
            level_wait_s <= level_wait_c;
          end if;

        -- The core is off the bus for as long as this runs, so its
        -- refreshes are not happening.  Without one here the array
        -- decays while it is being measured, and an array losing its
        -- charge looks from outside exactly like a write that landed.
        when POKE_REFRESH =>
          if level_wait_s = 0 then
            level_state_s <= POKE_GAP;
            level_wait_s <= level_wait_c;
          end if;

        when POKE_GAP =>
          if level_wait_s = 0 then
            if poke_s = '1' then
              level_state_s <= POKE_PRECHARGE;
              level_wait_s <= level_wait_c;
            else
              level_state_s <= LEVEL_OFF;
            end if;
          end if;
      end case;
    end if;
  end process;

  level_active_s <= '0' when level_state_s = LEVEL_OFF else '1';

  -- Only the levelling steps let go of the data pads.  The PHY takes
  -- this as "release the data lines so the part can answer on them",
  -- which is a different question from "is this sequencer driving the
  -- bus": every other step here -- the register reads, and the poke's
  -- write above all -- wants them driven.  Handed the wider flag, a
  -- write burst is laid into the schedule with nothing turning the
  -- pads on for it, and the part is asked to store a bus it is the
  -- only one holding.
  with level_state_s select write_level_s <=
    '1' when LEVEL_PRECHARGE | LEVEL_ENTER | LEVEL_PULSE | LEVEL_EXIT,
    '0' when others;

  -- What the part answered, straight off the controller-to-PHY line
  -- rather than through the frontend, because in this mode there is no
  -- walker asking.
  -- A DFI cycle is a slot per element and a byte lane per byte inside
  -- one, so what the host reads is flattened through the library's own
  -- accessor rather than by indexing the vector: byte 2s + l is lane l
  -- of slot s, which is the order the AXI beat and the capture below
  -- carry too.
  mpr_catch: process(ram_s, ram_reset_n_s) is
    variable answered: nsl_data.bytestream.byte_string(0 to beat_byte_c - 1);
  begin
    if ram_reset_n_s = '0' then
      mpr_data_s <= (others => '0');
      mpr_count_s <= (others => '0');
      strobe_word_s <= (others => (others => '0'));
    elsif rising_edge(ram_s) then
      if level_state_s = LEVEL_OFF then
        mpr_count_s <= (others => '0');
      elsif dfi_slave_s.rddata_valid = '1' then
        answered := nsl_ext_ram.dfi.value(dfi_config_c, dfi_slave_s.rddata);
        for i in 0 to beat_byte_c - 1
        loop
          mpr_data_s(i * 8 + 7 downto i * 8)
            <= std_ulogic_vector(answered(i));
        end loop;
        -- The same eight slots, on the strobe pins rather than on the
        -- data pins, taken on the cycle the data word is taken.
        strobe_word_s <= strobe_pick_s;
        mpr_count_s <= mpr_count_s + 1;
      end if;
    end if;
  end process;

  -- Five bits rather than four, so that every step has a code of its
  -- own and a sequence stopped on one can be named.
  with level_state_s select level_step_s <=
    "00000" when LEVEL_OFF,
    "00001" when LEVEL_PRECHARGE,
    "00010" when LEVEL_ENTER,
    "00011" when LEVEL_PULSE,
    "00100" when LEVEL_EXIT,
    "00101" when MPR_PRECHARGE,
    "00110" when MPR_ENTER,
    "00111" when MPR_READ,
    "01000" when MPR_SETTLE,
    "01001" when MPR_EXIT,
    "01010" when POKE_PRECHARGE,
    "01011" when POKE_MRS,
    "01100" when POKE_ACTIVATE,
    "01101" when POKE_WRITE,
    "01110" when POKE_SETTLE,
    "01111" when POKE_READ,
    "10000" when POKE_PRECHARGE_AGAIN,
    "10001" when POKE_REFRESH,
    "10010" when POKE_GAP;

  burst_count: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      level_burst_s <= (others => '0');
    elsif rising_edge(ram_s) then
      if level_state_s = LEVEL_OFF then
        level_burst_s <= (others => '0');
      elsif (level_state_s = LEVEL_PULSE or level_state_s = MPR_READ)
        and level_tick_s = 0 then
        level_burst_s <= level_burst_s + 1;
      end if;
    end if;
  end process;

  -- A command is issued on the first cycle of a step and the rest of
  -- the step is quiet, which is what the part's own script does.
  bus_owner: process(dfi_master_s, level_state_s, level_wait_s,
                     level_tick_s, poke_value_s, poke_ap_s, snoop_s,
                     tdqs_s, run_s, part_up_s, force_s) is
    variable poke_bytes: nsl_data.bytestream.byte_string(0 to beat_byte_c - 1);
  begin
    case level_state_s is
      when LEVEL_OFF =>
        dfi_phy_s <= dfi_master_s;

      when LEVEL_PRECHARGE =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_PRECHARGE,
            address => all_banks);
        end if;

      when LEVEL_ENTER | LEVEL_EXIT =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_MODE_REGISTER_SET,
            bank => "001",
            address => mr1_value(level_state_s = LEVEL_ENTER));
        end if;

      when MPR_PRECHARGE | MPR_SETTLE =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_PRECHARGE,
            address => all_banks);
        end if;

      when MPR_ENTER | MPR_EXIT =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_MODE_REGISTER_SET,
            bank => "011",
            address => mr3_value(level_state_s = MPR_ENTER));
        end if;

      when MPR_READ =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        -- A read now and then, announced the way the core announces
        -- one, so the capture path sees exactly what it sees in
        -- ordinary traffic.
        if level_tick_s = 0 then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_READ,
            bank => "000", address => (0 downto 0 => '0'));
          dfi_phy_s.rddata_en <= (others => '1');
        end if;

      when POKE_PRECHARGE | POKE_PRECHARGE_AGAIN =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_PRECHARGE,
            address => all_banks);
        end if;

      when POKE_REFRESH =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_REFRESH);
        end if;

      when POKE_MRS =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_MODE_REGISTER_SET,
            bank => "001",
            address => mr1_value(false, tdqs_s));
        end if;

      when POKE_ACTIVATE =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_ACTIVATE,
            bank => "000", address => (0 downto 0 => '0'));
        end if;

      when POKE_WRITE =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_WRITE,
            bank => "000", address => write_address(poke_ap_s));
          -- A beat per byte, each one different, so that a burst that
          -- comes back rotated or reversed says so rather than
          -- looking like a burst that came back wrong.
          for i in 0 to beat_byte_c - 1
          loop
            poke_bytes(i) := std_ulogic_vector(poke_value_s
                                               + to_unsigned(i, 8));
          end loop;
          dfi_phy_s.wrdata <= nsl_ext_ram.dfi.to_data_vector(dfi_config_c,
                                                             poke_bytes);
          dfi_phy_s.wrdata_en <= (others => '1');
          -- A capture announced on the cycle of the write.  The data
          -- pads are buffers, so the receivers see the burst this
          -- design is driving, and the read offset it turns up at
          -- counts the slots from the command to the data.
          dfi_phy_s.rddata_en <= (others => snoop_s);
        end if;

      when POKE_READ =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        if level_wait_s = level_wait_c then
          dfi_phy_s.command(0) <= nsl_ext_ram.dfi.command(
            dfi_config_c, nsl_ext_ram.dfi.CMD_READ,
            bank => "000", address => (0 downto 0 => '0'));
          -- Left unannounced while the write is being snooped: this
          -- answer comes back later and would overwrite the latch the
          -- write's own capture just filled.
          dfi_phy_s.rddata_en <= (others => not snoop_s);
        end if;

      when POKE_SETTLE | POKE_GAP =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);

      when LEVEL_PULSE =>
        dfi_phy_s <= nsl_ext_ram.dfi.master_idle(dfi_config_c);
        -- Strobe with nothing on the data lines, which is what the
        -- part is waiting to sample the clock on.  One cycle in every
        -- level_period_c by default, which is the discrete strobe
        -- burst levelling asks for; the panel can ask for one on every
        -- cycle instead, or for none at all, which is what the pin
        -- watcher is read against.
        if force_s = "11"
          or (force_s /= "10" and level_tick_s = 0) then
          dfi_phy_s.wrdata_en <= (others => '1');
        end if;
    end case;

    -- A core held in reset drives the part's reset pin low and takes
    -- its clock enable down with it.  That is what a design does
    -- before its first bring-up, and not what it may do between two
    -- runs: every instrument on this panel but the walkers works with
    -- the run down, and each of them wants a part that is initialised
    -- and clocked.  So for as long as the run holds the core in reset,
    -- those two pins are held where the sequence left them.
    --
    -- Only for as long as it holds it there.  The core replays the
    -- sequence from its first step when the run comes back, and that
    -- step's reset pulse is what closes the rows the run before it
    -- left open: the rest of the script is mode register writes, and
    -- the part accepts none of those with a row still open.
    if part_up_s = '1' and run_s = '0' then
      dfi_phy_s.reset_n <= '1';
      for phase in 0 to dfi_config_c.phase_count - 1
      loop
        dfi_phy_s.command(phase).cke <= '1';
      end loop;
    end if;
  end process;

  phy_offset_s <= offset_s when manual_s = '1'
                  else to_unsigned(board_c.read_offset, phy_offset_s'length);
  phy_slip_s <= slip_s when manual_s = '1'
                else to_unsigned(board_c.write_slip, phy_slip_s'length);
  phy_dq_lead_s <= dq_lead_s when manual_s = '1'
                   else to_unsigned(board_c.dq_enable_lead,
                                    phy_dq_lead_s'length);
  phy_dqs_lead_s <= dqs_lead_s when manual_s = '1'
                    else to_unsigned(board_c.dqs_enable_lead,
                                     phy_dqs_lead_s'length);
  phy_invert_s <= dqs_invert_s when manual_s = '1'
                  else nsl_logic.bool.to_logic(board_c.strobe_invert);

  phy: nsl_ext_ram.ddr3_io.ddr3_phy_serdes
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      board_c => board_c,
      -- A GW5A pin's two serialisers share one control set, so a data
      -- pad driven from one clock pair cannot be listened to on
      -- another: the quarter period leaves on the strobe, CK and the
      -- command pins instead.
      shift_strobe_c => true,
      -- A14 is at D1, eight IOLOGIC sites from the group the other
      -- fourteen address pins sit in and twenty-three from CK, and a
      -- half tick of setup is not enough for it: an activate carrying
      -- that bit set lands at the part with it clear, which is the
      -- fault readings 10 and 11 isolate.  The core issues one command
      -- a controller cycle, so the three ticks either side of it
      -- deselect and the address may be presented a memory period
      -- early at no cost on the wire.
      early_address_c => true
      )
    port map(
      clock_i => ram_s,
      fast_clock_i => fast_s,
      data_clock_i => data_s,
      shifted_clock_i => shifted_s,
      -- This family's delay line takes its tap as a number and has
      -- nothing to lock to, so the reference is a wire that says ready
      -- and this clock reaches nothing.
      delay_ref_clock_i => ram_s,
      reset_n_i => ram_reset_n_s,

      dfi_i => dfi_phy_s,
      dfi_o => dfi_slave_s,

      read_offset_i => phy_offset_s,
      write_slip_i => phy_slip_s,
      dq_enable_lead_i => phy_dq_lead_s,
      dqs_enable_lead_i => phy_dqs_lead_s,
      strobe_invert_i => phy_invert_s,
      dq_delay_shift_i => delay_step_s,
      dq_delay_mark_o => delay_mark_s,
      write_level_i => write_level_s,
      write_level_answer_o => level_answer_s,

      ck_o => ck_s,
      cke_o => ddr3_cke_o,
      cs_n_o => ddr3_cs_n_o,
      ras_n_o => ddr3_ras_n_o,
      cas_n_o => ddr3_cas_n_o,
      we_n_o => ddr3_we_n_o,
      ba_o => ram_ba_s,
      a_o => ram_a_s,
      -- The core never asks for termination, so the panel does.  The
      -- part turns its own off while it drives, which is what makes
      -- holding this asserted safe.
      odt_o => open,
      ram_reset_n_o => ddr3_reset_n_o,

      dm_o => dm_s,
      dqs_o => dqs_out_s,
      dqs_n_o => dqs_n_out_s,
      dq_o => dq_out_s,
      dq_i => dq_in_s
      );

  -- Both halves of the clock pair come out of a serialiser of their
  -- own, on the shifted pair with the strobe and the commands: a clock
  -- cannot be assigned at a pin on this family, and a differential
  -- primitive is not what a 1.5V LVCMOS bank offers.
  ddr3_ck_p_o <= ck_s.p;
  ddr3_ck_n_o <= ck_s.n;

  ddr3_ba_o <= std_ulogic_vector(ram_ba_s);
  -- A15 addresses nothing at this density; the pin is an input of the
  -- part all the same, so it is held rather than left floating.
  ddr3_a_o(ram_a_s'length - 1 downto 0) <= std_ulogic_vector(ram_a_s);
  ddr3_a_o(ddr3_a_o'left downto ram_a_s'length) <= (others => '0');
  ddr3_0_dm_o <= dm_s;
  ddr3_odt_o <= odt_s;

  -- Every pad's enable comes from the serialiser that drives it and
  -- reaches the pin with nothing in between: on this family a fabric
  -- signal on a pad's enable is refused (CK0011), and on any family a
  -- gate between a serialiser and its pad is a route that does not
  -- exist.
  dq_pads: for i in 0 to part_c.dq_width - 1
  generate
    ddr3_0_dq_io(i) <= nsl_io.io.to_logic(dq_out_s(i));
    dq_in_s(i) <= to_x01(ddr3_0_dq_io(i));
  end generate;

  -- The strobe is driven on writes and let go of on reads.  The PHY
  -- finds a read burst by training rather than by gating on the
  -- strobe, so nothing above needs it back -- but this bench does.
  --
  -- Everything said about the write path rests on the strobe leaving
  -- the pin, and until the pin is read back that is an assumption.
  -- What is caught here is the board's own strobe, so a word of it
  -- that never changes says the pin is not being driven, whatever the
  -- logic behind it intends.
  strobe_pads: for i in 0 to lane_c - 1
  generate
    ddr3_0_dqs_p_io(i) <= nsl_io.io.to_logic(dqs_out_s(i));
    ddr3_0_dqs_n_io(i) <= nsl_io.io.to_logic(dqs_n_out_s(i));
    dqs_in_s(i) <= to_x01(ddr3_0_dqs_p_io(i));

    -- Through a delay line, like every data pin, and stepped by the
    -- same ticks.  The strobe runs the pattern CK runs, off the clock
    -- that captures it, so its edges land on the sampling edge and raw
    -- it would be caught on its own transitions.
    --
    -- The pad's input reaches nothing but this line.  A pin whose data
    -- goes both through the delay and beside it asks for two routes
    -- out of one site, and the family refuses it.
    --
    -- The counter is on the controller clock; the line itself carries
    -- no clock, so it takes no part in the pin's control set.
    tap: nsl_io.delay.input_delay_variable
      port map(clock_i => ram_s,
               reset_n_i => ram_reset_n_s,
               mark_o => open,
               shift_i => delay_step_s(i),
               data_i => dqs_in_s(i),
               data_o => dqs_delayed_s(i));

    -- On the shifted pair, which is not a choice: this pin's driver is
    -- there, and a GW5A pin's two serialisers share one control set.
    -- So the word arrives in the shifted domain and crosses to the
    -- controller clock below.
    listener: nsl_io.serdes.serdes_input
      generic map(left_first_c => true, ddr_mode_c => true,
                  from_delay_c => true,
                  ratio_c => 8)
      port map(serial_clock_i => data_s,
               parallel_clock_i => shifted_s, reset_n_i => ram_reset_n_s,
               serial_i => dqs_delayed_s(i),
               parallel_o => dqs_shifted_s(i),
               bitslip_i => '0',
               mark_o => open);
  end generate;

  -- The captured strobe, from the shifted clock to the controller
  -- clock, and back to the sense the schedule holds.
  --
  -- The shifted clock's rising edge is a sixteenth of a cycle past the
  -- controller clock's, so a word registered there has fifteen
  -- sixteenths of a cycle to reach the register below -- the long way
  -- round of the pair, and the only direction this bench crosses in.
  -- The sense is taken here rather than at the pin because the delay
  -- line's input comes straight from the pad and nothing may sit
  -- between them.
  strobe_cross: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      dqs_caught_s <= (others => (others => '0'));
    elsif rising_edge(ram_s) then
      for i in 0 to lane_c - 1
      loop
        for s in 0 to 7
        loop
          dqs_caught_s(i)(s) <= dqs_shifted_s(i)(s) xor phy_invert_s;
        end loop;
      end loop;
    end if;
  end process;

  -- The strobe pins read out with the arithmetic the PHY reads the
  -- data pins out with, pipelined to land on the same cycle.
  --
  -- In the PHY's transition process: rin.window takes caught_s every
  -- cycle and pushes the cycle before it down, so r.window during a
  -- cycle holds the two captures before that one; rin.rddata is
  -- registered off r.window every cycle at slots slot_sel to
  -- slot_sel+7, whatever was asked for; and rin.rddata_valid is
  -- registered off r.expected(cycle_sel), which is what says the
  -- burst this read asked for is the one the window is holding now.
  --
  -- So the cycle half of the offset arrives entirely through when the
  -- valid pulse lands, and the slot half entirely through the index.
  -- The same window filled the same way and the same index registered
  -- on the same edge therefore puts strobe_pick_s beside
  -- dfi_slave_s.rddata_valid on the cycle that pulse is high, which is
  -- where mpr_catch takes both.
  --
  -- The crossing above costs this path a cycle the PHY's data path
  -- does not pay, and the strobe's own group pays one going out, so
  -- what the two words say about each other is a reading and not a
  -- calibration: the ruler is what times them together.
  --
  -- The slot half of the offset is taken off a register of its own, so
  -- the sixteen way mux below starts from one rather than from the
  -- panel's copy across the die.  It is an index and not data: the
  -- pipeline the words travel is the same depth either way, and all
  -- that moves is when a change of offset begins to apply, which is a
  -- cycle later.  Nothing reads a window on the cycle a host writes
  -- the offset -- every sweep here settles between a write and a
  -- reading -- so the cycle is free.
  strobe_listen: process(ram_s, ram_reset_n_s) is
    variable slot_sel: natural;
  begin
    if ram_reset_n_s = '0' then
      dqs_window_s <= (others => (others => '0'));
      strobe_pick_s <= (others => (others => '0'));
      pick_slot_s <= (others => '0');
    elsif rising_edge(ram_s) then
      pick_slot_s <= phy_offset_s(2 downto 0);
      slot_sel := to_integer(pick_slot_s);

      for i in 0 to lane_c - 1
      loop
        dqs_window_s(i)(0 to 7) <= dqs_window_s(i)(8 to 15);
        dqs_window_s(i)(8 to 15) <= dqs_caught_s(i);

        for s in 0 to 7
        loop
          strobe_pick_s(i)(s) <= dqs_window_s(i)(slot_sel + s);
        end loop;
      end loop;
    end if;
  end process;

  -- Sticky over a levelling pass or a walk: a slot that was ever high
  -- and a slot that was ever low.  A strobe that toggles makes the two
  -- differ; a pin nobody drives makes them agree, whatever level it
  -- settles at.
  strobe_watch: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      strobe_high_s <= (others => (others => '0'));
      strobe_low_s <= (others => (others => '0'));
    elsif rising_edge(ram_s) then
      if run_s = '0' and level_active_s = '0' then
        strobe_high_s <= (others => (others => '0'));
        strobe_low_s <= (others => (others => '0'));
      else
        for i in 0 to lane_c - 1
        loop
          for s in 0 to 7
          loop
            if dqs_caught_s(i)(s) = '1' then
              strobe_high_s(i)(s) <= '1';
            else
              strobe_low_s(i)(s) <= '1';
            end if;
          end loop;
        end loop;
      end if;
    end if;
  end process;

  -- Whichever of the four walkers the panel selected is the one that
  -- answers; the other three are held in reset and have nothing to
  -- say.
  busy_s <= walk_busy_s when full_r_s = 1
            else bank_busy_s when full_r_s = 2
            else row_busy_s when full_r_s = 3
            else low_busy_s when full_r_s = 4
            else high_busy_s when full_r_s = 5
            else probe_busy_s;
  done_s <= walk_done_s when full_r_s = 1
            else bank_done_s when full_r_s = 2
            else row_done_s when full_r_s = 3
            else low_done_s when full_r_s = 4
            else high_done_s when full_r_s = 5
            else probe_done_s;
  error_count_s <= walk_errors_s when full_r_s = 1
                   else bank_errors_s when full_r_s = 2
                   else row_errors_s when full_r_s = 3
                   else low_errors_s when full_r_s = 4
                   else high_errors_s when full_r_s = 5
                   else probe_errors_s;
  first_error_s <= walk_first_s when full_r_s = 1
                   else bank_first_s when full_r_s = 2
                   else row_first_s when full_r_s = 3
                   else low_first_s when full_r_s = 4
                   else high_first_s when full_r_s = 5
                   else probe_first_s;

  -- One step of every data pin's delay line each time the panel's tick
  -- changes, either way.  The line only ever moves forward and wraps,
  -- so a sweep is a run of ticks and a position is a count of them.
  delay_walk: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      tick_seen_s <= '0';
      delay_step_s <= (others => '0');
    elsif rising_edge(ram_s) then
      tick_seen_s <= tick_s;
      delay_step_s <= (others => tick_s xor tick_seen_s);
    end if;
  end process;

  snoop: process(ram_s, ram_reset_n_s) is
    variable word: nsl_data.bytestream.byte_string(0 to beat_byte_c - 1);
  begin
    if ram_reset_n_s = '0' then
      first_read_s <= (others => '0');
      got_read_s <= '0';
      read_count_s <= (others => '0');
    elsif rising_edge(ram_s) then
      if run_s = '0' then
        got_read_s <= '0';
        read_count_s <= (others => '0');
      elsif is_valid(axi_config_c, axi_s.s.r)
        and is_ready(axi_config_c, axi_s.m.r) then
        read_count_s <= read_count_s + 1;
        if got_read_s = '0' then
          word := bytes(axi_config_c, axi_s.s.r);
          for i in 0 to beat_byte_c - 1
          loop
            first_read_s(i * 8 + 7 downto i * 8) <= word(i);
          end loop;
          got_read_s <= '1';
        end if;
      end if;
    end if;
  end process;

  -- Both sides of every channel, so that a transfer counted here is
  -- one that happened rather than one that was offered.
  traffic: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      aw_count_s <= (others => '0');
      w_count_s <= (others => '0');
      b_count_s <= (others => '0');
      ar_count_s <= (others => '0');
      last_aw_s <= (others => '0');
      last_ar_s <= (others => '0');
    elsif rising_edge(ram_s) then
      if run_s = '0' then
        aw_count_s <= (others => '0');
        w_count_s <= (others => '0');
        b_count_s <= (others => '0');
        ar_count_s <= (others => '0');
        last_aw_s <= (others => '0');
        last_ar_s <= (others => '0');
      else
        if is_valid(axi_config_c, axi_s.m.aw)
          and is_ready(axi_config_c, axi_s.s.aw) then
          aw_count_s <= aw_count_s + 1;
          last_aw_s <= address(axi_config_c, axi_s.m.aw);
        end if;

        if is_valid(axi_config_c, axi_s.m.w)
          and is_ready(axi_config_c, axi_s.s.w) then
          w_count_s <= w_count_s + 1;
        end if;

        if is_valid(axi_config_c, axi_s.s.b)
          and is_ready(axi_config_c, axi_s.m.b) then
          b_count_s <= b_count_s + 1;
        end if;

        if is_valid(axi_config_c, axi_s.m.ar)
          and is_ready(axi_config_c, axi_s.s.ar) then
          ar_count_s <= ar_count_s + 1;
          last_ar_s <= address(axi_config_c, axi_s.m.ar);
        end if;
      end if;
    end if;
  end process;

  handshake: process(axi_s) is
  begin
    handshake_s <= (others => '0');

    if is_valid(axi_config_c, axi_s.m.aw) then
      handshake_s(0) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.s.aw) then
      handshake_s(1) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.m.w) then
      handshake_s(2) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.s.w) then
      handshake_s(3) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.s.b) then
      handshake_s(4) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.m.b) then
      handshake_s(5) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.m.ar) then
      handshake_s(6) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.s.ar) then
      handshake_s(7) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.s.r) then
      handshake_s(8) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.m.r) then
      handshake_s(9) <= '1';
    end if;
  end process;

  -- What the core put on the command pins, by kind.  Every command it
  -- issues goes out on phase zero, and only while the sequencer is off
  -- does what it issues reach the part at all.
  --
  -- Counted from reset rather than from the run, so the power-up
  -- script's own register writes are in the totals: it is what these
  -- do over a run rather than what they hold that belongs to it.
  dfi_decode: process(ram_s, ram_reset_n_s) is
    variable kind: nsl_ext_ram.dfi.command_enum_t;
  begin
    if ram_reset_n_s = '0' then
      count_step_s <= (others => '0');
    elsif rising_edge(ram_s) then
      count_step_s <= (others => '0');
      if level_state_s = LEVEL_OFF then
        kind := nsl_ext_ram.dfi.to_command_enum(dfi_config_c,
                                                dfi_master_s.command(0));
        case kind is
          when nsl_ext_ram.dfi.CMD_ACTIVATE =>
            count_step_s(count_act_c) <= '1';

          when nsl_ext_ram.dfi.CMD_PRECHARGE =>
            count_step_s(count_pre_c) <= '1';

          when nsl_ext_ram.dfi.CMD_WRITE =>
            count_step_s(count_wr_c) <= '1';

          when nsl_ext_ram.dfi.CMD_READ =>
            count_step_s(count_rd_c) <= '1';

          when nsl_ext_ram.dfi.CMD_REFRESH =>
            count_step_s(count_ref_c) <= '1';

          when nsl_ext_ram.dfi.CMD_MODE_REGISTER_SET =>
            count_step_s(count_mrs_c) <= '1';

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

  dfi_watch: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      act_count_s <= (others => '0');
      pre_count_s <= (others => '0');
      wr_count_s <= (others => '0');
      rd_count_s <= (others => '0');
      ref_count_s <= (others => '0');
      mrs_count_s <= (others => '0');
    elsif rising_edge(ram_s) then
      if count_step_s(count_act_c) = '1' then
        act_count_s <= act_count_s + 1;
      end if;
      if count_step_s(count_pre_c) = '1' then
        pre_count_s <= pre_count_s + 1;
      end if;
      if count_step_s(count_wr_c) = '1' then
        wr_count_s <= wr_count_s + 1;
      end if;
      if count_step_s(count_rd_c) = '1' then
        rd_count_s <= rd_count_s + 1;
      end if;
      if count_step_s(count_ref_c) = '1' then
        ref_count_s <= ref_count_s + 1;
      end if;
      if count_step_s(count_mrs_c) = '1' then
        mrs_count_s <= mrs_count_s + 1;
      end if;
    end if;
  end process;

  -- What the capture records, one stage before the instrument.  The
  -- DFI carries a cycle as an array of slots and the host reads a flat
  -- word, so the two are laid out here rather than in the instrument:
  -- slot zero is the first beat out of the part and the first byte of
  -- the word.
  --
  -- Every field goes through this stage, including both of the
  -- instrument's trigger sources, so a window holds the same samples
  -- in the same order and the whole recording sits one cycle later in
  -- absolute time.  What it buys is what stops sharing a cycle with
  -- the analyser's memory and its trigger enable: the sequencer's mux
  -- over the whole DFI, the reduction of the selected walker's error
  -- count to a bit, and the adapter's address arithmetic that both the
  -- command pins and the read channel are worked out behind.
  --
  -- Where a pass begins is the run with a controller that has come
  -- ready under it.  The run is the cycle the selected walker leaves
  -- reset, and the core leaves reset with it, so the part's power-up
  -- sequence sits between that cycle and the first transfer of the
  -- pass -- two hundred microseconds of reset and five hundred of
  -- clock enable, seventy thousand controller cycles of it, against a
  -- window a thousand samples deep.  Ready rises on the cycle the core
  -- can take a transaction, which is the cycle the walker has been
  -- waiting for since it left reset.
  cap_word: process(ram_s, ram_reset_n_s) is
    variable written, read_back:
      nsl_data.bytestream.byte_string(0 to beat_byte_c - 1);
  begin
    if ram_reset_n_s = '0' then
      -- Only the bits that say something happened; the words they
      -- qualify are read through those and keep their reset out of the
      -- fabric.  Nothing reaches a pin from here either way.
      cap_run_s <= '0';
      cap_error_s <= '0';
      cap_wrdata_en_s <= '0';
      cap_rddata_valid_s <= '0';
      cap_r_beat_s <= '0';
    elsif rising_edge(ram_s) then
      written := nsl_ext_ram.dfi.value(dfi_config_c, dfi_phy_s.wrdata);
      read_back := nsl_ext_ram.dfi.value(dfi_config_c, dfi_slave_s.rddata);

      for i in 0 to beat_byte_c - 1
      loop
        cap_wrdata_s(i * 8 + 7 downto i * 8) <= std_ulogic_vector(written(i));
        cap_rddata_s(i * 8 + 7 downto i * 8) <= std_ulogic_vector(read_back(i));
      end loop;

      cap_cs_n_s <= dfi_phy_s.command(0).cs_n;
      cap_ras_n_s <= dfi_phy_s.command(0).ras_n;
      cap_cas_n_s <= dfi_phy_s.command(0).cas_n;
      cap_we_n_s <= dfi_phy_s.command(0).we_n;
      cap_bank_s <= std_ulogic_vector(dfi_phy_s.command(0).bank(2 downto 0));
      cap_address_s
        <= std_ulogic_vector(dfi_phy_s.command(0).address(14 downto 0));
      cap_wrdata_en_s <= dfi_phy_s.wrdata_en(0);
      cap_rddata_valid_s <= dfi_slave_s.rddata_valid;
      cap_error_count_s <= std_ulogic_vector(error_count_s(7 downto 0));

      cap_run_s <= run_s and ready_s;
      cap_error_s <= nsl_logic.bool.to_logic(error_count_s /= 0);
      cap_r_beat_s
        <= nsl_logic.bool.to_logic(is_valid(axi_config_c, axi_s.s.r)
                                   and is_ready(axi_config_c, axi_s.m.r));
    end if;
  end process;

  -- The transport: the board's own USB2 port through the soft PHY, a
  -- serial function over it, and the chunked link that carries a
  -- gatecap rack over a byte pipe.
  usb_pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => board_hz_c,
      output_hz_c => clock_usb_hz_c
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,
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
      product_c => "DDR3 walk",
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
      rx_o => rack_pipe_s.cmd.req,
      rx_i => rack_pipe_s.cmd.ack,
      tx_i => rack_pipe_s.rsp.req,
      tx_o => rack_pipe_s.rsp.ack
      );

  observer: block is
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
        in_i => rack_pipe_s.cmd.req,
        in_o => rack_pipe_s.cmd.ack,
        reset_n_o => rack_reset_n_s,
        out_o => framed_s.cmd.req,
        out_i => framed_s.cmd.ack
        );

    chunker: nsl_bnoc.chunked_link.framed_chunker
      generic map(
        max_txn_length_l2_c => max_txn_length_l2_c
        )
      port map(
        reset_n_i => rack_reset_n_s,
        clock_i => clock_usb_s,
        in_i => framed_s.rsp.req,
        in_o => framed_s.rsp.ack,
        out_o => rack_pipe_s.rsp.req,
        out_i => rack_pipe_s.rsp.ack
        );

    to_stream: nsl_bnoc.axi_adapter.framed_to_axi4_stream
      port map(
        clock_i => clock_usb_s,
        reset_n_i => rack_reset_n_s,
        framed_i => framed_s.cmd.req,
        framed_o => framed_s.cmd.ack,
        axi_o => cmd_s.m,
        axi_i => cmd_s.s
        );

    from_stream: nsl_bnoc.axi_adapter.axi4_stream_to_framed
      port map(
        clock_i => clock_usb_s,
        reset_n_i => rack_reset_n_s,
        axi_i => rsp_s.m,
        axi_o => rsp_s.s,
        framed_o => framed_s.rsp.req,
        framed_i => framed_s.rsp.ack
        );

    rack: gatecap_generated.ddr3_walk.ddr3_walk_core
      generic map(
        stream_config_c => nsl_bnoc.axi_adapter.axi4_stream_framed_config_c,
        burst_length_l2_c => 6
        )
      port map(
        clock_i => clock_usb_s,
        reset_n_i => rack_reset_n_s,
        rx_i => cmd_s.m,
        rx_o => cmd_s.s,
        tx_o => rsp_s.m,
        tx_i => rsp_s.s,

        rates_board_i => board_s,
        rates_ram_i => ram_s,

        panel_clock_i => ram_s,
        panel_reset_n_i => ram_reset_n_s,
        panel_run_o => run_s,
        panel_full_o => full_s,
        panel_level_o => level_s,
        panel_tick_o => tick_s,
        panel_offset_o => offset_s,
        panel_slip_o => slip_s,
        panel_force_o => force_s,
        panel_dq_lead_o => dq_lead_s,
        panel_dqs_lead_o => dqs_lead_s,
        panel_dqs_invert_o => dqs_invert_s,
        panel_manual_o => manual_s,
        panel_mpr_o => mpr_s,
        panel_poke_o => poke_s,
        panel_poke_value_o => poke_value_s,
        panel_poke_ap_o => poke_ap_s,
        panel_odt_o => odt_s,
        panel_snoop_o => snoop_s,
        panel_tdqs_o => tdqs_s,
        panel_ready_i => part_up_s,
        panel_busy_i => busy_s,
        panel_done_i => done_s,
        panel_error_count_i => error_count_s,
        panel_first_error_address_i => first_error_s,
        panel_aw_count_i => aw_count_s,
        panel_w_count_i => w_count_s,
        panel_b_count_i => b_count_s,
        panel_ar_count_i => ar_count_s,
        panel_last_aw_i => last_aw_s,
        panel_last_ar_i => last_ar_s,
        panel_handshake_i => handshake_s,
        panel_act_count_i => act_count_s,
        panel_pre_count_i => pre_count_s,
        panel_wr_count_i => wr_count_s,
        panel_rd_count_i => rd_count_s,
        panel_ref_count_i => ref_count_s,
        panel_mrs_count_i => mrs_count_s,
        panel_first_read_0_i => word_of(first_read_s, 0),
        panel_first_read_1_i => word_of(first_read_s, 1),
        panel_first_read_2_i => word_of(first_read_s, 2),
        panel_first_read_3_i => word_of(first_read_s, 3),
        panel_read_count_i => read_count_s,
        panel_delay_mark_i => unsigned(delay_mark_s),
        panel_level_answer_i => unsigned(level_answer_s),
        panel_strobe_high_0_i => unsigned(strobe_high_s(0)),
        panel_strobe_low_0_i => unsigned(strobe_low_s(0)),
        panel_strobe_high_1_i => unsigned(strobe_high_s(1)),
        panel_strobe_low_1_i => unsigned(strobe_low_s(1)),
        panel_level_step_i => level_step_s,
        panel_level_burst_i => level_burst_s,
        panel_mpr_0_i => word_of(mpr_data_s, 0),
        panel_mpr_1_i => word_of(mpr_data_s, 1),
        panel_mpr_2_i => word_of(mpr_data_s, 2),
        panel_mpr_3_i => word_of(mpr_data_s, 3),
        panel_mpr_count_i => mpr_count_s,
        panel_strobe_word_0_i => unsigned(strobe_word_s(0)),
        panel_strobe_word_1_i => unsigned(strobe_word_s(1)),

        capture_ram_clock_i => ram_s,
        capture_ram_reset_n_i => ram_reset_n_s,
        capture_ram_run_i => cap_run_s,
        capture_ram_error_i => cap_error_s,
        capture_ram_cs_n_i => cap_cs_n_s,
        capture_ram_ras_n_i => cap_ras_n_s,
        capture_ram_cas_n_i => cap_cas_n_s,
        capture_ram_we_n_i => cap_we_n_s,
        capture_ram_bank_i => cap_bank_s,
        capture_ram_address_i => cap_address_s,
        capture_ram_wrdata_en_i => cap_wrdata_en_s,
        capture_ram_wrdata_i => cap_wrdata_s,
        capture_ram_rddata_valid_i => cap_rddata_valid_s,
        capture_ram_rddata_i => cap_rddata_s,
        capture_ram_error_count_i => cap_error_count_s,
        capture_ram_r_beat_i => cap_r_beat_s
        );
  end block;

end architecture;
