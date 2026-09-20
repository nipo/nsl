library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_data, nsl_logic, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.ddr3_io.all;

-- Pin side of a DDR3 controller built from ordinary serialisers and an
-- input delay line, for a family that has no memory flavoured IO block
-- of its own.
--
-- Every pin of the interface goes out through an eight bit double rate
-- serialiser, so a controller cycle is eight slots wide and carries a
-- whole burst of eight, four memory ticks, and the four command slots
-- a cycle is cut into.  Slot zero is the earliest on the wire.
--
--   slot     0     1     2     3     4     5     6     7
--   command  phase 0     phase 1     phase 2     phase 3
--   CK       0     1     0     1     0     1     0     1
--
-- A command therefore covers a pair of slots and CK rises in the
-- middle of it: half a tick of setup and half of hold, and the part is
-- sampled where it is most stable.
--
-- Two things about this shape are worth stating, because the general
-- argument against writing to DDR3 with portable serialisers says both
-- are impossible.
--
-- **The strobe needs no placement of its own.**  DQS runs the same
-- pattern as CK, off the same clock, so its rising edges land on CK's
-- exactly: tDQSS is zero by construction rather than trimmed towards
-- zero by levelling.  What buys that is putting DQS on the clock CK
-- comes from, rather than on the shifted one.
--
-- That places the edges and says nothing about their sense, and a
-- board may present the pair either way round.  Which sense arrives
-- is what a part counts its beats by, so `strobe_invert_i` turns the
-- pattern round in the word the serialiser is given.
--
-- **The quarter tick comes from the clock, not from the serialiser.**
-- One group of pins goes out on data_clock_i, a quarter of a memory
-- period behind fast_clock_i, and the other on fast_clock_i, which
-- puts every data bit's centre on a strobe edge.  The serialisers are
-- the same blocks throughout; the phase comes from whatever generates
-- the clock pair, where it is a continuous knob rather than a choice
-- between whole slots.  A family whose clock generator cannot produce
-- that quarter cannot use this PHY, and that is the honest boundary of
-- the approach.
--
-- Which group takes it is shift_strobe_c, and it is a family's answer
-- rather than a board's: a 7-series pin will drive from one clock pair
-- and listen on another, a Gowin pin will not, and the data pins are
-- the ones that do both.  So false leaves the data on the shifted pair
-- and true moves the strobe, the clock and the command pins onto it
-- instead.  Either way the group on the shifted parallel clock is
-- handed its words through a register stage in that domain, which
-- costs it a cycle and is given back by reading the schedule a cycle
-- further ahead.
--
-- Read capture does not ride the part's strobe.  The bus is sampled on
-- fast_clock_i and each data pin carries a delay line ahead of its
-- capture, walked until the eye sits on the sampling edge.  That is
-- the opposite trade to a strobe gated PHY: the eye is brought to the
-- clock rather than the clock to the eye, it costs a training pass
-- over known data rather than a gate, and it does not track the part
-- over temperature the way a strobe does.  It is reachable with
-- nothing but a delay line finer than the eye, which is the point.
--
-- The DFI inputs are registered once on the way in, and everything
-- below reads the register rather than the port.  Every command pin of
-- this family is fed straight from a serialiser, and a serialiser's
-- parallel side is a register with the whole cycle of fabric ahead of
-- it and nothing to spare: whatever works out what a command is has to
-- fit in that cycle.  A controller that picks its next action out of
-- its own registers and encodes the command in the same cycle leaves
-- nothing, so a register has to go somewhere between the two.  It goes
-- here, because the shape that asks for it -- command pins serialised
-- rather than driven from an IO register -- is a property of the
-- family, and the family is what this PHY is.
--
-- The command, the write data and the read announcement all move by
-- that one cycle together, so nothing in the schedule's arithmetic
-- moves with them, and neither does anything a board measures: the
-- read offset counts slots from the announcement to the first beat,
-- and the announcement and the part's answer to the command it went
-- out with are now both a cycle later than they were.
--
-- The words are registered once more on the way out, a word per pad.
-- A serialiser's parallel side has the whole cycle of fabric ahead of
-- it and lends none of it, and what the fabric does with that cycle is
-- read the schedule at a slip, widen a drive bit into an enable and
-- carry the result to the pad: with sixteen pads on one enable that
-- last carry is a die-wide net behind a mux, and the two do not fit
-- one cycle at any rate worth running.  So each pad gets its own word
-- of its own register and what is left on the wire in front of it is
-- routing.  The copies are identical by construction -- every pad of a
-- lane is enabled together, and every strobe pad runs one pattern --
-- and the point is not their values but that no two pads read the same
-- register.
--
-- Both groups take the stage, so their relative timing is what it was;
-- where the strobe's group already crosses to the shifted clock the
-- stage is what that crossing reads, rather than a second register
-- ahead of it.  One cycle is added, and to everything at once: the
-- command, the burst it asks for and every enable word leave together
-- a cycle later, so burst_at_c, the slip's centre and the enable leads
-- are untouched, and so are the tap placement and init_complete.  The
-- read announcement is the one thing that does not move with them --
-- it enters the queue below out of the DFI register, which is ahead of
-- this stage -- so the part's answer comes back a cycle later against
-- its own announcement and read_offset grows by a word on every
-- family.  That is a board's figure, and a board measures it.
--
-- Nothing here is trained at run time, and nothing needs to be.  The
-- read offset, the tap the eye sits on, the whole-word slip of the
-- write and the lead of each pad's enable are properties of a board
-- and of its family: they are measured once with the instruments of a
-- bench like example/xc7a50t/ddr3, written into a serdes_board_t, and
-- handed here as board_c.  The PHY walks every data pin's delay line
-- to the tap the record names as soon as the delay reference is ready
-- and holds dfi_o.init_complete low until it has, so a controller
-- never issues into a read path that is not placed yet.
--
-- The ports beside board_c default to the record's own figures.  They
-- are there for the bench that measured them, which has to be able to
-- move one and watch what happens; a design leaves them open.
--
-- Each of the whole-slot figures is sampled once on the way in and
-- read from that register everywhere below, so moving one takes effect
-- a cycle later.  They are quasi-static -- a host writes one and waits
-- for the next reading -- and what it buys is that the die-wide route
-- from whatever drives them no longer shares a cycle with the mux that
-- reads the schedule at them.
entity ddr3_phy_serdes is
  generic(
    part_c: dram_part_t;
    timing_c: dram_timing_t;
    dfi_config_c: config_t;
    board_c: serdes_board_t;
    -- Which pins carry the quarter period, which is a property of the
    -- family's IO logic rather than of the board.
    --
    -- False puts it on the data and the mask, which is what a 7-series
    -- pin takes without complaint: its output serialiser runs on the
    -- shifted pair while its capture runs on the unshifted one.  A
    -- Gowin pin refuses that -- its two serialisers share one control
    -- set, so a pad driven from one clock pair cannot be listened to on
    -- another -- and true moves the shift to the strobe, the clock and
    -- the command pins instead, leaving both directions of every data
    -- pin on the unshifted pair.
    --
    -- A quarter period is a quarter period whichever group carries it:
    -- one way the strobe's edges land half a slot ahead of the data's
    -- boundaries and the other way half a slot behind, and either puts
    -- a strobe edge in the middle of a data bit.  What does differ is
    -- which strobe edge a given beat pairs with, and that is a whole
    -- slot, which is what write_slip is for.
    shift_strobe_c: boolean := false
    );
  port(
    -- Controller clock, one cycle per burst of eight
    clock_i: in std_ulogic;
    -- Memory clock rate, four times the above and in phase with it
    fast_clock_i: in std_ulogic;
    -- Memory clock rate, a quarter of a period behind fast_clock_i
    data_clock_i: in std_ulogic;
    -- Controller rate, the parallel clock of whichever group takes the
    -- shifted fast clock, and shifted by the same quarter of a memory
    -- period so that the pair is settled: a serialiser handed a shifted
    -- fast clock against a parallel clock divided from the unshifted
    -- one holds stale words.
    --
    -- A family whose pins take two clock pairs at once may tie this to
    -- clock_i and lose nothing: what the serialisers need is that each
    -- one's own two clocks agree, and the words that reach the shifted
    -- group are registered onto this clock before they get there
    -- whatever it is.
    shifted_clock_i: in std_ulogic;
    -- Reference the input delay lines calibrate their taps against.
    -- Its frequency is a property of the family, not of this design.
    delay_ref_clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    dfi_i: in master_t;
    dfi_o: out slave_t;

    -- Slots from the cycle a read was announced on to the slot the
    -- first beat of its answer is found in, counting the whole way:
    -- the part's CAS latency, the flight there and back, and the
    -- pipelines of both serialisers.  It is the coarse half of what a
    -- board measures, and it is found by sweeping it against known
    -- data.
    read_offset_i: in unsigned(6 downto 0)
      := to_unsigned(board_c.read_offset, 7);

    -- Where the data sits against the strobe, in whole slots, eight
    -- meaning the quarter period the clock pair already provides and
    -- nothing more.
    --
    -- The pair is what places the strobe inside the eye, and on paper
    -- that settles it.  In silicon the serialiser carrying the data
    -- runs its fast side on the shifted clock while its parallel side
    -- stays on the controller clock, and a parallel word crosses
    -- between the two whole.  So the burst lands on one side of that
    -- transfer or on the other and the error is a whole word, eight
    -- slots, rather than a fraction of one; and which side it lands on
    -- is not something the primitive's timing says, because a fast
    -- clock that is not aligned to the parallel one is outside what it
    -- is characterised for.  Hence a range of a word either way: eight
    -- is no slipping at all, zero puts the burst a whole cycle later,
    -- fifteen takes it seven slots earlier.  It is found by sweeping
    -- it once for a board.
    --
    -- Taking it earlier only reaches as far as the burst's own
    -- command: the burst starts a fixed distance into the schedule and
    -- that distance is asserted to leave the preamble room.
    write_slip_i: in unsigned(3 downto 0)
      := to_unsigned(board_c.write_slip, 4);

    -- Turn the strobe pattern round, so what was a rising edge leaves
    -- as a falling one.
    --
    -- A board may present the pair either way about, and a part reads
    -- its beats off the sense of the strobe against its data, so the
    -- wrong way about is a burst whose beats the part pairs up wrong.
    -- This is the one knob that turns a pair round without touching a
    -- pin, and it acts on the word going into the serialiser: nothing
    -- may sit between a serialiser and its pad, so the wire after it
    -- is not somewhere a choice can be made.
    strobe_invert_i: in std_ulogic := to_logic(board_c.strobe_invert);

    -- Slots by which the family puts a pad's tristate word on the pin
    -- ahead of the data word presented beside it: one figure for the
    -- data pads, one for the strobe.
    --
    -- A serialiser carries one tristate register and it sits outside
    -- the pipeline the data word travels: the enable is taken from the
    -- fabric on the fast clock while the word beside it still has a
    -- clock domain to cross.  So the enable reaches the pin first, by
    -- a distance that belongs to the family and to which clock the pad
    -- is serialised on, which is why there are two of these and not
    -- one.
    --
    -- It is measured on a board rather than read anywhere.  A capture
    -- swept across the wire slots of a burst tells a driven slot from
    -- a released one, because a driven slot carries the same level
    -- every pass while a released one settles wherever the bus and the
    -- receiver leave it and reads differently pass to pass.  The lead
    -- is the distance between the slots the pad turned out to hold and
    -- the slots the burst was asked for at.
    --
    -- Zero is a family whose tristate word and data word reach the pin
    -- together, which is what the simulation serialiser does.
    dq_enable_lead_i: in unsigned(3 downto 0)
      := to_unsigned(board_c.dq_enable_lead, 4);
    dqs_enable_lead_i: in unsigned(3 downto 0)
      := to_unsigned(board_c.dqs_enable_lead, 4);

    -- The fine half, one per data pin: each pulse moves that pin's
    -- delay line on a tap, and the mark says it is at its shortest.
    -- Lanes skew and so do the bits inside them, so this is per pin
    -- rather than per lane.
    --
    -- The record's tap is already applied when init_complete rises, so
    -- these move the line off it: they are what a bench sweeps the eye
    -- with, and a design leaves them low.
    dq_delay_shift_i: in std_ulogic_vector;
    dq_delay_mark_o: out std_ulogic_vector;

    -- Write levelling: the strobe still goes out on a write enable but
    -- the data lines are let go of, so the part can answer on them
    -- with whatever it sampled of the memory clock on each strobe
    -- rising edge.  A point to point board with one lane needs no
    -- levelling to work; this is here because the answer is the one
    -- direct measurement that CK and DQS leave together.
    write_level_i: in std_ulogic := '0';
    -- One bit per data pin, not per lane.  The part drives every pin
    -- of a lane with the same answer, so pins that disagree are a bus
    -- nobody is driving -- which is the reading that separates a
    -- strobe that never arrived from a part that never entered the
    -- mode, and the two look alike through one bit.
    write_level_answer_o: out std_ulogic_vector;

    ck_o: out nsl_io.diff.diff_pair;
    cke_o: out std_ulogic;
    cs_n_o: out std_ulogic;
    ras_n_o: out std_ulogic;
    cas_n_o: out std_ulogic;
    we_n_o: out std_ulogic;
    ba_o: out unsigned;
    a_o: out unsigned;
    odt_o: out std_ulogic;
    ram_reset_n_o: out std_ulogic;

    dm_o: out std_ulogic_vector;
    -- The strobe is differential; both halves are serialised from the
    -- same pattern so they cannot drift apart.
    dqs_o: out nsl_io.io.tristated_vector;
    dqs_n_o: out nsl_io.io.tristated_vector;
    dq_o: out nsl_io.io.tristated_vector;
    dq_i: in std_ulogic_vector
    );
end entity;

architecture beh of ddr3_phy_serdes is

  constant lane_count_c: natural := dfi_config_c.dq_byte_count;
  constant dq_bit_c: natural := lane_count_c * 8;
  constant slot_count_c: natural := slot_count(dfi_config_c);
  constant a_width_c: natural := a_o'length;
  constant ba_width_c: natural := ba_o'length;

  -- Slot the first beat of a write goes out on, counted from the slot
  -- the command asking for it goes out on.  Both leave the same cycle,
  -- so the whole of the CAS write latency is a shift down the slot
  -- schedule below.
  constant write_slot_c: natural := 2 * timing_c.cwl;
  -- Slots the data may be slipped by against the strobe, and the
  -- middle of that range, which is where no slipping at all sits.  The
  -- range is a whole word either way because what it is there to undo
  -- moves a whole word: the serialiser hands its parallel word to its
  -- fast side entire, and the data's fast side is not the clock its
  -- parallel side runs on.
  constant slip_count_c: natural := 16;
  constant slip_centre_c: natural := slip_count_c / 2;
  -- Where the strobe is read out of the schedule.  It leaves on the
  -- clock the schedule is shifted by, so it needs no placement of its
  -- own and sits at the centre the data is slipped around.
  constant strobe_at_c: natural := slip_centre_c;
  -- Furthest out a burst may be placed, which is what the schedule has
  -- to be long enough to hold.
  constant offset_max_c: natural := 40;

  -- Slots the strobe, the clock and the command pins are read further
  -- ahead when they are the group that crosses to shifted_clock_i,
  -- which is exactly the cycle their words spend in the register stage
  -- that carries them there.  Reading a cycle ahead and leaving a
  -- cycle late cancel, so a schedule slot means the same instant on
  -- the wire either way, and neither the slip's centre nor the enable
  -- leads move with the generic.
  --
  -- Only that group ever crosses, and that is why the shift can only
  -- go on that side of a family that needs a register to cross at all.
  -- A cycle spent by the data is a cycle the burst has to be presented
  -- ahead of the command asking for it, and the burst's distance from
  -- that command is the CAS write latency: the schedule would have to
  -- hold a burst 2 * cwl - 2 * slot_count_c slots along, which is
  -- behind the command at any write latency under nine.  A cycle spent
  -- by the command takes the schedule with it and costs nothing,
  -- because the burst is written from the register the command is.
  constant dqs_cross_c: natural := if_else(shift_strobe_c, slot_count_c, 0);

  -- Where a burst lands in the schedule: what is presented this cycle
  -- goes out next cycle, so the first slot of a cycle is eight slots
  -- along from the command that shared it.  The whole thing sits far
  -- enough in that the data may be read out ahead of the strobe as
  -- well as behind it.
  --
  -- The command pins share the strobe's clock pair, so when that pair
  -- is the shifted one the command reaches the part a cycle later too,
  -- and the burst it asks for has to follow it: the one thing the
  -- crossing does not cancel is the distance from a command to its own
  -- data, because a command comes out of a register rather than out of
  -- the schedule and cannot be read a cycle ahead.
  constant burst_at_c: natural
    := write_slot_c - slot_count_c + slip_centre_c + dqs_cross_c;
  -- Schedule long enough for the furthest burst, the preamble pair
  -- ahead of it, the postamble pair behind it, the slip either way,
  -- and a whole cycle beyond that so a pad can be told a cycle early
  -- what is coming, rounded to whole cycles.
  constant schedule_c: natural
    := ((offset_max_c - slot_count_c + slip_centre_c + dqs_cross_c
         + 2 * slot_count_c + 2 + slip_centre_c)
        + slot_count_c - 1)
       / slot_count_c * slot_count_c;
  -- Furthest into the schedule a burst may start.  The postamble sits
  -- two slots past the burst's end, so a burst beginning past this
  -- would write off the end of the array.
  constant first_max_c: natural := schedule_c - slot_count_c - 2;

  -- Cycles a read answer may be away, which is how far down the
  -- announcement queue an answer is read out of.  The queue is a delay
  -- line and not a store: a cycle enters it whether or not a read was
  -- announced on it, so its depth has to cover the read offset alone
  -- and says nothing about how many reads may be in flight together.
  -- The offset is a board's figure, read out at
  -- read_offset_i / slot_count_c + 1, so this covers every offset the
  -- port can carry.
  constant read_depth_c: natural := 17;

  -- What one slot puts on the data pins.
  type slot_t is
  record
    data: std_ulogic_vector(dq_bit_c - 1 downto 0);
    mask: std_ulogic_vector(lane_count_c - 1 downto 0);
    dq_drive: std_ulogic;
    dqs: std_ulogic;
    dqs_drive: std_ulogic;
  end record;

  type slot_vector is array (natural range <>) of slot_t;

  -- Every field has a value, none of them a don't care.  A slot that
  -- is not driven still reaches a serialiser, and a strobe whose idle
  -- is a don't care is a pattern built entirely from constants and
  -- don't cares: a synthesiser is then free to decide the whole thing
  -- is one constant, which it cannot be told apart from a pin that is
  -- simply never driven.
  constant slot_idle_c: slot_t := (
    data => (others => '0'),
    mask => (others => '0'),
    dq_drive => '0',
    dqs => '0',
    dqs_drive => '0'
    );

  -- Placing the read path's delay lines, once, out of reset.
  --
  -- A tap only means anything counted from the mark, so the lines are
  -- walked to it and then out by as many taps as the record asks for,
  -- rather than trusted to come out of configuration anywhere in
  -- particular.  A shift is a pulse and not a level, so each tap costs
  -- a cycle of shift and a cycle of quiet.
  type place_t is (
    -- The family's delay lines have taps of no known length until
    -- their reference has calibrated them.
    PLACE_REFERENCE,
    PLACE_MARK,
    PLACE_TAP,
    PLACE_DONE
    );

  -- The whole-slot figures, as of last cycle.
  --
  -- Every word a pad is handed is read out of the schedule at the
  -- slip, widened by a lead and inverted or not, which is a sixteen
  -- way mux per bit of every pin; the read offset picks eight slots
  -- out of a window of sixteen the same way.  Sampling the ports here
  -- keeps whatever drives them out of that mux's path.  A design
  -- leaves the ports open, which makes each of these the same constant
  -- as its own reset value and folds the register away with the mux; a
  -- bench reaches them from across the die, and a change there no
  -- longer has to cross the die and the mux inside one cycle.
  type knobs_t is
  record
    read_offset: unsigned(6 downto 0);
    write_slip: unsigned(3 downto 0);
    dq_enable_lead: unsigned(3 downto 0);
    dqs_enable_lead: unsigned(3 downto 0);
    strobe_invert: std_ulogic;
  end record;

  subtype word_t is std_ulogic_vector(0 to slot_count_c - 1);
  type slot_word_vector is array (natural range <>) of word_t;
  subtype pair_word_t is std_ulogic_vector(0 to slot_count_c / 2 - 1);

  -- What the strobe, the clock and the command pins are handed in one
  -- cycle, and what the data pins and the mask are handed.  The two
  -- groups are what shift_strobe_c chooses between: each one sits
  -- whole on one clock pair, and the one on the shifted pair crosses
  -- to it whole, so grouping them says once what would otherwise be
  -- said on every port map.
  --
  -- Every pad carries its own word of every kind, the enable words
  -- included, although all the pads of a lane are enabled together and
  -- all the strobe's pads run one pattern.  A word here is a register
  -- whose only load is the pad it belongs to, which is the point: one
  -- enable word shared by sixteen pads across two banks is a single
  -- net carrying the whole of the die's routing, and that net is what
  -- the register stage below exists to cut.
  type command_group_t is
  record
    ck: word_t;
    ck_n: word_t;
    cke: word_t;
    cs: word_t;
    ras: word_t;
    cas: word_t;
    we: word_t;
    odt: word_t;
    a: slot_word_vector(0 to max_address_width_c - 1);
    ba: slot_word_vector(0 to max_bank_width_c - 1);
    -- One word per strobe pad, the two halves of a lane's pair being
    -- two pads.  A pad turns round on a pair of slots at finest, so
    -- only the first half of an enable word reaches a serialiser.
    dqs: slot_word_vector(0 to max_dq_byte_count_c - 1);
    dqs_n: slot_word_vector(0 to max_dq_byte_count_c - 1);
    dqs_drive: slot_word_vector(0 to max_dq_byte_count_c - 1);
    dqs_n_drive: slot_word_vector(0 to max_dq_byte_count_c - 1);
  end record;

  type data_group_t is
  record
    dq: slot_word_vector(0 to max_dq_byte_count_c * 8 - 1);
    dm: slot_word_vector(0 to max_dq_byte_count_c - 1);
    dq_drive: slot_word_vector(0 to max_dq_byte_count_c * 8 - 1);
  end record;

  -- The drive bits of the two words already presented and of the one
  -- being presented now, oldest slot first.  An enable word reaches
  -- back into it by as many slots as the family's lead.
  subtype drive_view_t is std_ulogic_vector(0 to 3 * slot_count_c - 1);

  type regs_t is
  record
    -- What the controller asked for last cycle.  Everything below
    -- reads this and not the port, so the command encoding starts from
    -- a register rather than from whatever the controller worked out
    -- this cycle.
    dfi: master_t;

    knobs: knobs_t;

    place: place_t;
    place_shift: std_ulogic;
    place_left: natural range 0 to board_c.read_tap;

    -- The next schedule_c slots of data pin activity, slot 0 first.
    -- The eight at the front are what goes out next cycle.
    schedule: slot_vector(0 to schedule_c - 1);

    -- Reads announced, one bit per cycle since.
    --
    -- DFI states rddata_en as a level that is high for as many cycles
    -- as the answer will take, so a level held over two cycles is two
    -- cycles of answer and not one long one: the meaning is a count of
    -- cycles, not an event.  Column commands may follow each other
    -- every tCCD, which is one controller cycle here, and then there is
    -- no gap between one announcement and the next for an edge to be
    -- found in.  So every cycle the level is high enters the queue, and
    -- each one carries its own cycle of answer down it.
    expected: std_ulogic_vector(0 to read_depth_c - 1);
    -- The bus as the two most recent cycles found it, oldest slot of
    -- the older cycle first
    window: std_ulogic_vector(0 to 2 * slot_count_c * dq_bit_c - 1);

    rddata: data_vector(0 to max_slot_count_c - 1);
    rddata_valid: std_ulogic;

    -- The drive bits of the two words presented before this one, the
    -- older word first, read out at the same slip the words themselves
    -- were.  An enable word covers wire slots that begin ahead of the
    -- data word it is presented with, so the slots it answers for have
    -- already left the schedule by the time it is formed.
    dq_drive_past: std_ulogic_vector(0 to 2 * slot_count_c - 1);
    dqs_drive_past: std_ulogic_vector(0 to 2 * slot_count_c - 1);

    ram_reset_n: std_ulogic;
    level_answer: std_ulogic_vector(dq_bit_c - 1 downto 0);
    level_answer_out: std_ulogic_vector(dq_bit_c - 1 downto 0);

    -- What every pad is handed, a word each.  Nothing but this
    -- register stands between the schedule and a serialiser's parallel
    -- side: whatever a pad's word is read out of the schedule at, and
    -- whatever the enable word covering it comes to, is worked out a
    -- cycle ahead and presented from here.
    --
    -- Both groups pay the cycle, so nothing in the schedule's
    -- arithmetic moves: the command, the burst it asks for and every
    -- enable word leave one cycle later together, and burst_at_c, the
    -- slip's centre and the two leads mean what they meant.  What does
    -- move is the part's answer.  A read is announced into the queue
    -- below out of the same DFI register the command is encoded from,
    -- and the queue is not behind this stage while the command is, so
    -- the answer comes back a cycle later against its announcement and
    -- read_offset grows by a word.  That is a board's figure and is
    -- measured on the board.
    command: command_group_t;
    data: data_group_t;
  end record;

  signal r, rin: regs_t;

  -- The enable word one cycle presents, for a pad whose tristate word
  -- lands lead slots ahead of the data word it goes out beside.
  --
  -- A pad turns around on a pair of slots at finest, and pair i of the
  -- word answers for the wire slots the data at view positions
  -- 2 * slot_count_c + 2 * i and the one after it occupy, taken back
  -- by the lead, plus a slot either side for the skew of a tristate
  -- that does not travel the data's path.  The view is clamped rather
  -- than extended: a lead reaching past it reaches past anything the
  -- schedule still holds.
  function enable_word(view: drive_view_t; lead: natural)
    return pair_word_t is
    variable result: pair_word_t;
    variable at: integer;
  begin
    result := (others => '0');

    for i in 0 to slot_count_c / 2 - 1
    loop
      for k in -1 to 2
      loop
        at := 2 * slot_count_c + 2 * i + k - lead;
        if at < view'low then
          at := view'low;
        end if;
        if at > view'high then
          at := view'high;
        end if;
        result(i) := result(i) or view(at);
      end loop;
    end loop;

    return result;
  end function;

  -- What reaches the serialisers: the register the fabric filled last
  -- cycle for the group that stays on clock_i, and a cycle later again
  -- for the group that crosses.
  signal command_out_s: command_group_t;
  signal data_out_s: data_group_t;

  -- The clock pair each group's serialisers run on.
  signal command_serial_clock_s, command_parallel_clock_s: std_ulogic;
  signal data_serial_clock_s, data_parallel_clock_s: std_ulogic;

  -- The bus as this cycle's capture found it, slot 0 earliest.
  signal caught_s: slot_word_vector(0 to dq_bit_c - 1);
  signal delayed_s: std_ulogic_vector(dq_bit_c - 1 downto 0);

  -- Every data pin's delay line, as the placement sees it: the mark it
  -- is walked to, and the pulses that walk it, which are the
  -- placement's own until it is done and the caller's afterwards.
  signal dq_mark_s, dq_shift_s: std_ulogic_vector(dq_bit_c - 1 downto 0);
  constant all_marked_c: std_ulogic_vector(dq_bit_c - 1 downto 0)
    := (others => '1');

  signal delay_ready_s: std_ulogic;

begin

  assert dfi_config_c.edge_count = 2
    report "ddr3_phy_serdes: DDR3 carries two data words per tick"
    severity failure;

  assert slot_count_c = 8
    report "ddr3_phy_serdes: a cycle is eight slots, which is one burst"
    severity failure;

  assert burst_at_c >= strobe_at_c + dqs_cross_c + 2
    report "ddr3_phy_serdes: the write schedule needs a preamble ahead of the burst"
    severity failure;

  assert 2 * timing_c.cwl <= offset_max_c
    report "ddr3_phy_serdes: the write schedule is shorter than the part's write latency"
    severity failure;

  assert first_max_c >= burst_at_c
    report "ddr3_phy_serdes: the write schedule cannot hold a burst at the part's write latency"
    severity failure;

  -- A bench sweeps the offset port over its whole range, and an answer
  -- is read out of the queue at read_offset / slot_count_c + 1.  The
  -- queue has to reach the far end of the port or a sweep runs off it.
  assert read_depth_c > (2 ** read_offset_i'length - 1) / slot_count_c + 1
    report "ddr3_phy_serdes: the announcement queue is shorter than the read offset port"
    severity failure;

  assert board_c.read_offset < 2 ** read_offset_i'length
    report "ddr3_phy_serdes: the board's read offset does not fit the port"
    severity failure;

  assert dq_i'length = dq_bit_c
    report "ddr3_phy_serdes: data bus is not the configured width"
    severity failure;

  assert ba_o'length <= max_bank_width_c
    report "ddr3_phy_serdes: the bank bus is wider than a command carries"
    severity failure;

  assert a_o'length <= max_address_width_c
    report "ddr3_phy_serdes: the address bus is wider than a command carries"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      -- The write payload is reached through wrdata_en, so clearing
      -- that is enough and the payload register keeps its reset out of
      -- the fabric.
      r.dfi.command <= (others => command(dfi_config_c, CMD_DESELECT,
                                          cke => '0'));
      r.dfi.wrdata_en <= (others => '0');
      r.dfi.rddata_en <= (others => '0');
      r.dfi.reset_n <= '0';
      -- Only what says a pin is held matters here: the rest of a slot
      -- is read through those and costs nothing to leave alone.
      for i in 0 to schedule_c - 1
      loop
        r.schedule(i).dq_drive <= '0';
        r.schedule(i).dqs_drive <= '0';
      end loop;
      r.dq_drive_past <= (others => '0');
      r.dqs_drive_past <= (others => '0');
      r.expected <= (others => '0');
      r.rddata_valid <= '0';
      r.ram_reset_n <= '0';
      r.place <= PLACE_REFERENCE;
      r.place_shift <= '0';
      r.place_left <= board_c.read_tap;
      -- The record's own figures, so that the first cycle out of reset
      -- reads the schedule where a design with nothing attached to
      -- these ports will go on reading it.
      r.knobs <= (read_offset => to_unsigned(board_c.read_offset, 7),
                  write_slip => to_unsigned(board_c.write_slip, 4),
                  dq_enable_lead => to_unsigned(board_c.dq_enable_lead, 4),
                  dqs_enable_lead => to_unsigned(board_c.dqs_enable_lead, 4),
                  strobe_invert => to_logic(board_c.strobe_invert));
      -- What a pad is to be handed while the PHY is held: a part
      -- deselected with its clock enable down, and every pad that can
      -- be let go of let go of.  The rest of a word is read through
      -- these and costs nothing to leave alone.
      r.command.cke <= (others => '0');
      r.command.cs <= (others => '1');
      r.command.dqs_drive <= (others => (others => '0'));
      r.command.dqs_n_drive <= (others => (others => '0'));
      r.data.dq_drive <= (others => (others => '0'));
    end if;
  end process;

  transition: process(r, dfi_i, caught_s, write_level_i,
                      read_offset_i, write_slip_i, dq_enable_lead_i,
                      dqs_enable_lead_i, strobe_invert_i,
                      delay_ready_s, dq_mark_s) is
    variable slot: data_t;
    variable at: natural;
    variable slip: natural;
    variable cycle_sel: natural;
    variable slot_sel: natural;
    variable word: byte_string(0 to max_dq_byte_count_c - 1);
    variable cmd: command_t;
    variable cmd_a: unsigned(max_address_width_c - 1 downto 0);
    variable cmd_b: unsigned(max_bank_width_c - 1 downto 0);
    variable pin_slot: natural;
    variable strobe: std_ulogic;
    variable dq_view, dqs_view: drive_view_t;
    variable dq_enable, dqs_enable: pair_word_t;
  begin
    rin <= r;

    rin.dfi <= dfi_i;

    rin.knobs <= (read_offset => read_offset_i,
                  write_slip => write_slip_i,
                  dq_enable_lead => dq_enable_lead_i,
                  dqs_enable_lead => dqs_enable_lead_i,
                  strobe_invert => strobe_invert_i);

    -- The index the data pins are read out of the schedule at, because
    -- what says a pad was driven has to be read where the word it
    -- belongs to was read.
    slip := to_integer(r.knobs.write_slip);

    case r.place is
      when PLACE_REFERENCE =>
        if delay_ready_s = '1' then
          rin.place <= PLACE_MARK;
        end if;

      when PLACE_MARK =>
        if r.place_shift = '1' then
          rin.place_shift <= '0';
        elsif dq_mark_s = all_marked_c then
          rin.place <= PLACE_TAP;
        else
          rin.place_shift <= '1';
        end if;

      when PLACE_TAP =>
        if r.place_shift = '1' then
          rin.place_shift <= '0';
        elsif r.place_left = 0 then
          rin.place <= PLACE_DONE;
        else
          rin.place_shift <= '1';
          rin.place_left <= r.place_left - 1;
        end if;

      when PLACE_DONE =>
        null;
    end case;

    rin.ram_reset_n <= r.dfi.reset_n;

    -- The schedule walks a cycle's worth of slots forward and the tail
    -- comes up empty, so a burst that is not written in stays gone.
    for i in 0 to schedule_c - slot_count_c - 1
    loop
      rin.schedule(i) <= r.schedule(i + slot_count_c);
    end loop;
    for i in schedule_c - slot_count_c to schedule_c - 1
    loop
      rin.schedule(i) <= slot_idle_c;
    end loop;

    if r.dfi.wrdata_en(0) = '1' then
      -- Preamble: the strobe is held low over the pair of slots ahead
      -- of the burst, which is a whole memory period of it.
      --
      -- Unless a burst is already there.  Column accesses may follow
      -- each other every cycle, and then the slots this preamble would
      -- take are the last two beats of the burst before it: DDR3 has
      -- no preamble between bursts, the strobe simply keeps toggling.
      -- What the schedule holds at those slots after the shift is what
      -- the cycle before it put there, which is what this reads.
      for k in 0 to 1
      loop
        if r.schedule(burst_at_c - 2 + k + slot_count_c).dq_drive = '0' then
          rin.schedule(burst_at_c - 2 + k).dqs <= '0';
          rin.schedule(burst_at_c - 2 + k).dqs_drive <= '1';
        end if;
      end loop;

      for k in 0 to slot_count_c - 1
      loop
        at := burst_at_c + k;
        slot := r.dfi.wrdata(k);

        for lane in 0 to lane_count_c - 1
        loop
          for b in 0 to 7
          loop
            rin.schedule(at).data(lane * 8 + b) <= slot.value(lane)(b);
          end loop;
          rin.schedule(at).mask(lane) <= slot.mask(lane);
        end loop;

        rin.schedule(at).dq_drive <= not write_level_i;
        -- The same pattern CK runs, so the edge that takes a beat is
        -- the edge that takes the command in the tick it belongs to.
        if k mod 2 = 0 then
          rin.schedule(at).dqs <= '0';
        else
          rin.schedule(at).dqs <= '1';
        end if;
        rin.schedule(at).dqs_drive <= '1';
      end loop;

      -- Postamble, the falling edge behind the last beat and a slot of
      -- quiet after it.
      for k in 0 to 1
      loop
        rin.schedule(burst_at_c + slot_count_c + k).dqs <= '0';
        rin.schedule(burst_at_c + slot_count_c + k).dqs_drive <= '1';
      end loop;
    end if;

    -- The drive bits of the word being presented, kept because the
    -- enable words of the cycles after this one answer for the wire
    -- slots it occupies.  Read at the same indices the pins are, so
    -- what is remembered is what went out.
    for i in 0 to slot_count_c - 1
    loop
      rin.dq_drive_past(i) <= r.dq_drive_past(i + slot_count_c);
      rin.dqs_drive_past(i) <= r.dqs_drive_past(i + slot_count_c);
      rin.dq_drive_past(i + slot_count_c)
        <= r.schedule(i + slip).dq_drive;
      rin.dqs_drive_past(i + slot_count_c)
        <= r.schedule(i + strobe_at_c + dqs_cross_c).dqs_drive;
    end loop;

    rin.expected(0) <= r.dfi.rddata_en(0);
    for i in 1 to read_depth_c - 1
    loop
      rin.expected(i) <= r.expected(i - 1);
    end loop;

    -- Two cycles of capture stand side by side so that a burst
    -- straddling a cycle boundary is still eight slots in a row.
    for pin in 0 to dq_bit_c - 1
    loop
      for s in 0 to slot_count_c - 1
      loop
        rin.window(pin * 2 * slot_count_c + s)
          <= r.window(pin * 2 * slot_count_c + slot_count_c + s);
        rin.window(pin * 2 * slot_count_c + slot_count_c + s)
          <= caught_s(pin)(s);
      end loop;
    end loop;

    -- A burst starting at window slot j is only whole once the cycle
    -- after the one it started in has been caught, hence the cycle of
    -- slack on top of the offset's own.
    --
    -- The window walks a cycle per cycle and the answer is cut out of
    -- it afresh every cycle, so an announcement reaching the end of the
    -- queue selects its own eight slots at its own time.  Reads
    -- announced on consecutive cycles therefore answer on consecutive
    -- cycles, each out of the window as it stood when its own burst was
    -- whole.
    cycle_sel := to_integer(r.knobs.read_offset(6 downto 3)) + 1;
    slot_sel := to_integer(r.knobs.read_offset(2 downto 0));

    rin.rddata_valid <= r.expected(cycle_sel);
    for s in 0 to slot_count_c - 1
    loop
      word := (others => dontcare_byte_c);
      for lane in 0 to lane_count_c - 1
      loop
        for b in 0 to 7
        loop
          word(lane)(b)
            := r.window((lane * 8 + b) * 2 * slot_count_c + slot_sel + s);
        end loop;
      end loop;
      rin.rddata(s) <= data(dfi_config_c, word(0 to lane_count_c - 1));
    end loop;

    -- The levelling answer is a level, not a burst, so any slot of the
    -- capture carries it.  It is read there rather than off the pin
    -- because a pin whose data reaches the fabric both through its
    -- delay line and beside it asks for a route through the very site
    -- the capture serialiser sits in, and the two cannot both have it.
    for pin in 0 to dq_bit_c - 1
    loop
      rin.level_answer(pin) <= caught_s(pin)(slot_count_c - 1);
    end loop;
    rin.level_answer_out <= r.level_answer;

    -- What every pad is handed next cycle.
    --
    -- A command belongs to one memory tick, so every command pin goes
    -- out through a serialiser running at slot rate rather than being
    -- held for a whole cycle: a pin driven from a plain register
    -- arrives ahead of one driven from a serialiser, and a select
    -- pulse landing after its address has moved on reaches the part as
    -- a no-op.
    --
    -- Both groups are worked out here, on clock_i, whichever clock
    -- pair each of them goes out on: the schedule, the DFI register
    -- and the knobs are in this domain and nothing else needs to be in
    -- another.
    for phase in 0 to dfi_config_c.phase_count - 1
    loop
      cmd := r.dfi.command(phase);
      cmd_a := resize(address(dfi_config_c, cmd), max_address_width_c);
      cmd_b := resize(bank(dfi_config_c, cmd), max_bank_width_c);

      for edge in 0 to dfi_config_c.edge_count - 1
      loop
        pin_slot := phase * dfi_config_c.edge_count + edge;

        rin.command.cke(pin_slot) <= cmd.cke;
        rin.command.cs(pin_slot) <= cmd.cs_n;
        rin.command.ras(pin_slot) <= cmd.ras_n;
        rin.command.cas(pin_slot) <= cmd.cas_n;
        rin.command.we(pin_slot) <= cmd.we_n;
        rin.command.odt(pin_slot) <= cmd.odt;

        for i in 0 to max_address_width_c - 1
        loop
          rin.command.a(i)(pin_slot) <= cmd_a(i);
        end loop;

        for i in 0 to max_bank_width_c - 1
        loop
          rin.command.ba(i)(pin_slot) <= cmd_b(i);
        end loop;
      end loop;
    end loop;

    -- The part samples on the rising edge, so it falls in the middle
    -- of a tick's worth of command rather than on its boundary.
    for s in 0 to slot_count_c - 1
    loop
      if s mod 2 = 0 then
        rin.command.ck(s) <= '0';
        rin.command.ck_n(s) <= '1';
      else
        rin.command.ck(s) <= '1';
        rin.command.ck_n(s) <= '0';
      end if;
    end loop;

    -- The two words already presented, then the one being presented
    -- now, which is the stretch of wire an enable word may answer for.
    dq_view(0 to 2 * slot_count_c - 1) := r.dq_drive_past;
    dqs_view(0 to 2 * slot_count_c - 1) := r.dqs_drive_past;
    for s in 0 to slot_count_c - 1
    loop
      dq_view(2 * slot_count_c + s)
        := r.schedule(s + slip).dq_drive;
      dqs_view(2 * slot_count_c + s)
        := r.schedule(s + strobe_at_c + dqs_cross_c).dqs_drive;
    end loop;

    -- Pins the configuration does not carry are still fields of a
    -- record, and a field nothing reads costs nothing.
    rin.data.dq <= (others => (others => '0'));
    rin.data.dm <= (others => (others => '0'));

    for s in 0 to slot_count_c - 1
    loop
      strobe := r.schedule(s + strobe_at_c + dqs_cross_c).dqs
                xor r.knobs.strobe_invert;

      for lane in 0 to max_dq_byte_count_c - 1
      loop
        rin.command.dqs(lane)(s) <= strobe;
        rin.command.dqs_n(lane)(s) <= not strobe;
      end loop;

      for pin in 0 to dq_bit_c - 1
      loop
        rin.data.dq(pin)(s) <= r.schedule(s + slip).data(pin);
      end loop;

      for lane in 0 to lane_count_c - 1
      loop
        rin.data.dm(lane)(s) <= r.schedule(s + slip).mask(lane);
      end loop;
    end loop;

    -- The schedule is laid out so a burst, its preamble and its
    -- postamble all start and end on a pair of slots, which is the
    -- finest a pad turns around on; a family that rounds further only
    -- holds the pin longer.  The enable word each pad is given is the
    -- one that covers the slots its own words asked for, whatever
    -- distance the family carries it by.
    --
    -- One value, and a copy of it per pad: the pads of a lane are
    -- enabled together, and it is the register they read it out of
    -- that has to be theirs.
    dq_enable := enable_word(dq_view, to_integer(r.knobs.dq_enable_lead));
    dqs_enable := enable_word(dqs_view, to_integer(r.knobs.dqs_enable_lead));

    for pin in 0 to max_dq_byte_count_c * 8 - 1
    loop
      rin.data.dq_drive(pin) <= (others => '0');
      rin.data.dq_drive(pin)(0 to slot_count_c / 2 - 1) <= dq_enable;
    end loop;

    for lane in 0 to max_dq_byte_count_c - 1
    loop
      rin.command.dqs_drive(lane) <= (others => '0');
      rin.command.dqs_drive(lane)(0 to slot_count_c / 2 - 1) <= dqs_enable;
      rin.command.dqs_n_drive(lane) <= (others => '0');
      rin.command.dqs_n_drive(lane)(0 to slot_count_c / 2 - 1) <= dqs_enable;
    end loop;
  end process;

  -- Which clock pair each group runs on, and therefore which of them
  -- crosses.  A data pin's capture stays on the unshifted pair either
  -- way: with the shift on the strobe it has to, because a pin's two
  -- serialisers share one control set and the pin's driver is on the
  -- unshifted pair; with the shift on the data it may, because what
  -- the read path is placed against is the delay line and the offset a
  -- board measured in this domain, and nothing about the eye is easier
  -- to find from a clock the part has never heard of.
  unshifted_strobe: if not shift_strobe_c
  generate
    command_serial_clock_s <= fast_clock_i;
    command_parallel_clock_s <= clock_i;
    data_serial_clock_s <= data_clock_i;
    data_parallel_clock_s <= shifted_clock_i;
  end generate;

  shifted_strobe: if shift_strobe_c
  generate
    command_serial_clock_s <= data_clock_i;
    command_parallel_clock_s <= shifted_clock_i;
    data_serial_clock_s <= fast_clock_i;
    data_parallel_clock_s <= clock_i;
  end generate;

  -- Handing the strobe's group from clock_i to shifted_clock_i.
  --
  -- The two clocks are a quarter of a memory period apart, which is a
  -- sixteenth of a controller cycle, and nothing states that
  -- relationship to a timing engine.  The transfer holds by
  -- construction instead: the falling edge of the shifted clock is
  -- seven sixteenths of a cycle past the rising edge that made the
  -- word, which is the setup, and the rising edge after it hands the
  -- word on, so what a serialiser is given has been registered on the
  -- clock its own parallel side runs on.  Two edges of one clock is a
  -- path the tools time by themselves, with no constraint to write and
  -- none to get wrong.
  --
  -- It costs the group a whole cycle, and the whole of it pays --
  -- strobe, clock, commands and the strobe pad's enable alike -- so
  -- the lead a board measured between that pad's enable and its data
  -- does not move.  The cycle is given back by reading the schedule a
  -- cycle further ahead, which is dqs_cross_c above.
  command_direct: if not shift_strobe_c
  generate
    command_out_s <= r.command;
  end generate;

  command_crossed: if shift_strobe_c
  generate
    signal half_s: command_group_t;
  begin
    early: process(shifted_clock_i, reset_n_i) is
    begin
      if falling_edge(shifted_clock_i) then
        half_s <= r.command;
      end if;

      if reset_n_i = '0' then
        half_s.cke <= (others => '0');
        half_s.cs <= (others => '1');
        half_s.dqs_drive <= (others => (others => '0'));
        half_s.dqs_n_drive <= (others => (others => '0'));
      end if;
    end process;

    late: process(shifted_clock_i, reset_n_i) is
    begin
      if rising_edge(shifted_clock_i) then
        command_out_s <= half_s;
      end if;

      if reset_n_i = '0' then
        command_out_s.cke <= (others => '0');
        command_out_s.cs <= (others => '1');
        command_out_s.dqs_drive <= (others => (others => '0'));
        command_out_s.dqs_n_drive <= (others => (others => '0'));
      end if;
    end process;
  end generate;

  -- The data pins take their words straight out of the register.  A
  -- family that puts the shift here is one whose pins carry two clock
  -- pairs at once, which is the same family whose two parallel clocks
  -- are outputs of one generator a sixteenth of a cycle apart: a path
  -- the tools have both ends of and time as any other, and with the
  -- register in front of it there is nothing but routing on it.
  data_out_s <= r.data;

  command_pins: block is
  begin
    ck_p: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.ck, serial_o => ck_o.p);

    ck_n: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.ck_n, serial_o => ck_o.n);

    cke: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.cke, serial_o => cke_o);

    cs: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.cs, serial_o => cs_n_o);

    ras: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.ras, serial_o => ras_n_o);

    cas: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.cas, serial_o => cas_n_o);

    we: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.we, serial_o => we_n_o);

    odt: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.odt, serial_o => odt_o);

    address_pins: for i in 0 to a_width_c - 1
    generate
      line: nsl_io.serdes.serdes_output
        generic map(left_first_c => true, ddr_mode_c => true,
                    ratio_c => slot_count_c)
        port map(serial_clock_i => command_serial_clock_s,
                 parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
                 parallel_i => command_out_s.a(i), serial_o => a_o(a_o'low + i));
    end generate;

    bank_pins: for i in 0 to ba_width_c - 1
    generate
      line: nsl_io.serdes.serdes_output
        generic map(left_first_c => true, ddr_mode_c => true,
                    ratio_c => slot_count_c)
        port map(serial_clock_i => command_serial_clock_s,
                 parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
                 parallel_i => command_out_s.ba(i), serial_o => ba_o(ba_o'low + i));
    end generate;
  end block;

  -- The strobe leaves on the clock CK leaves on, so their edges
  -- coincide whatever the frequency and tDQSS is zero.  Which clock
  -- that is is shift_strobe_c's business; that they share it is not.
  strobe_pins: for lane in 0 to lane_count_c - 1
  generate
    p: nsl_io.serdes.serdes_output_tristated
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.dqs(lane),
               output_enable_i
                 => command_out_s.dqs_drive(lane)(0 to slot_count_c / 2 - 1),
               pad_o => dqs_o(dqs_o'low + lane));

    n: nsl_io.serdes.serdes_output_tristated
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => command_serial_clock_s,
               parallel_clock_i => command_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => command_out_s.dqs_n(lane),
               output_enable_i
                 => command_out_s.dqs_n_drive(lane)(0 to slot_count_c / 2 - 1),
               pad_o => dqs_n_o(dqs_n_o'low + lane));

    -- The mask travels with the data it hides, so it leaves on the
    -- data pins' clock pair and not on the strobe's.
    mask: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => data_serial_clock_s,
               parallel_clock_i => data_parallel_clock_s, reset_n_i => reset_n_i,
               parallel_i => data_out_s.dm(lane),
               serial_o => dm_o(dm_o'low + lane));
  end generate;

  reference: nsl_io.delay.delay_reference
    port map(
      clock_i => delay_ref_clock_i,
      reset_n_i => reset_n_i,
      ready_o => delay_ready_s
      );

  data_pins: for pin in 0 to dq_bit_c - 1
  generate
    driver: nsl_io.serdes.serdes_output_tristated
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => data_serial_clock_s,
               parallel_clock_i => data_parallel_clock_s,
               reset_n_i => reset_n_i,
               parallel_i => data_out_s.dq(pin),
               output_enable_i
                 => data_out_s.dq_drive(pin)(0 to slot_count_c / 2 - 1),
               pad_o => dq_o(dq_o'low + pin));

    dq_shift_s(pin) <= r.place_shift
                       or dq_delay_shift_i(dq_delay_shift_i'low + pin);
    dq_delay_mark_o(dq_delay_mark_o'low + pin) <= dq_mark_s(pin);

    tap: nsl_io.delay.input_delay_variable
      port map(clock_i => clock_i,
               reset_n_i => reset_n_i,
               mark_o => dq_mark_s(pin),
               shift_i => dq_shift_s(pin),
               data_i => dq_i(dq_i'low + pin),
               data_o => delayed_s(pin));

    -- The capture runs on the unshifted pair whichever group took the
    -- shift, so the window, the read offset and everything the
    -- schedule is written in stay in one domain.  With the shift on
    -- the strobe it also has to: this pin's driver is on the unshifted
    -- pair, and a pin's two serialisers share one control set.
    listener: nsl_io.serdes.serdes_input
      generic map(left_first_c => true, ddr_mode_c => true,
                  from_delay_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               serial_i => delayed_s(pin),
               parallel_o => caught_s(pin),
               bitslip_i => '0',
               mark_o => open);
  end generate;

  moore: process(r) is
  begin
    ram_reset_n_o <= r.ram_reset_n;

    for pin in 0 to dq_bit_c - 1
    loop
      write_level_answer_o(write_level_answer_o'low + pin)
        <= r.level_answer_out(pin);
    end loop;

    dfi_o <= slave_defaults(dfi_config_c);
    dfi_o.rddata <= r.rddata;
    dfi_o.rddata_valid <= r.rddata_valid;
    -- The delay lines are where the record put them, which is what the
    -- read path needs before a controller issues anything at all.
    dfi_o.init_complete <= to_logic(r.place = PLACE_DONE);
  end process;

end architecture;
