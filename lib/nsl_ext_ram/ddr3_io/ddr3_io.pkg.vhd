library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_logic, nsl_ext_ram;
use nsl_logic.bool.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;

-- Pin side of a DDR3 controller.
--
-- A controller cycle carries several memory ticks, so a PHY here
-- serialises commands across the phases, forwards the clock, puts
-- write data on the wire CAS write latency after its command with the
-- strobe centred in the eye, and hands read data back whenever it has
-- managed to capture it.
package ddr3_io is

  component ddr3_phy is
    generic(
      part_c: dram_part_t;
      timing_c: dram_timing_t;
      dfi_config_c: config_t;
      tck_ps_c: natural
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      dfi_i: in master_t;
      dfi_o: out slave_t;

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
      dqs_o: out nsl_io.io.tristated_vector;
      dqs_i: in std_ulogic_vector;
      dq_o: out nsl_io.io.tristated_vector;
      dq_i: in std_ulogic_vector
      );
  end component;

  component ddr3_phy_gowin is
    generic(
      part_c: dram_part_t;
      timing_c: dram_timing_t;
      dfi_config_c: config_t
      );
    port(
      -- Fabric clock, one memory tick per phase
      clock_i: in std_ulogic;
      -- Memory rate clock, phase locked to the above
      fast_clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      dfi_i: in master_t;
      dfi_o: out slave_t;

      -- Where the strobe sits against the memory clock, and where the
      -- capture clock sits in the incoming eye.  Both are swept while
      -- training and then left alone.
      --
      -- write_step is write levelling: the part is put in its levelling
      -- mode, the strobe is pulsed, and the part answers on its data
      -- lines with whatever it sampled of the memory clock.  Walking
      -- write_step until that answer flips puts the strobe's first
      -- rising edge on a clock edge, which is what tDQSS asks and what
      -- no amount of shifting the burst around can reach.
      write_step_i: in std_ulogic_vector(7 downto 0) := (others => '0');

      -- Write levelling mode.  The strobe still goes out on a write
      -- enable, but the data lines are let go of: in this mode the part
      -- is the one driving them, answering with what it sampled of the
      -- memory clock on each strobe rising edge.  That answer is a level
      -- rather than a burst, so it comes back resynchronised rather than
      -- through the capture path, which has no open gate here.
      write_level_i: in std_ulogic := '0';
      write_level_answer_o: out std_ulogic_vector;

      -- The window in which a read is expected back, a tick per phase,
      -- and where that window sits.  The capture FIFO only calls its
      -- output valid inside it, so a gate that is not opened means no
      -- read ever arrives; read_gate_select walks it a quarter tick at a
      -- time until it does.
      read_gate_i: in std_ulogic_vector(3 downto 0) := (others => '0');
      read_gate_select_i: in std_ulogic_vector(2 downto 0) := (others => '0');
      read_gate_ok_o: out std_ulogic;

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
      dqs_o: out nsl_io.io.tristated_vector;
      dqs_n_o: out nsl_io.io.tristated_vector;
      dqs_i: in std_ulogic_vector;
      dq_o: out nsl_io.io.tristated_vector;
      dq_i: in std_ulogic_vector
      );
  end component;

  -- What a board's own measurement of ddr3_phy_serdes came to.
  --
  -- None of these is in a datasheet and none of them is found by the
  -- design at run time: they are measured once, with the instruments
  -- of a bench like example/xc7a50t/ddr3, and then belong to the board
  -- the way a pinout does.  Every one of them but read_tap is a whole
  -- slot or a whole word, which is to say a property of the family's
  -- serialisers and of the flight time rounded to a slot, and does not
  -- move with a unit or with temperature.
  type serdes_board_t is
  record
    -- Slots from a read's announcement to its first beat
    read_offset: natural;
    -- Delay line taps from the mark, every data pin
    read_tap: natural;
    -- 0..15, eight meaning no slip
    write_slip: natural;
    -- Slots the data pads' enable reaches the pin ahead of its word
    dq_enable_lead: natural;
    -- The same for the strobe pad
    dqs_enable_lead: natural;
    -- The pair reaches the part the other way round
    strobe_invert: boolean;
  end record;

  -- A family whose serialisers hand word and enable to the pin
  -- together and whose clocks are exact, which is what the behavioural
  -- blocks of nsl_io do: nothing leads, nothing slips, and the pair is
  -- the way round the schedule holds it.  The offset and the tap are
  -- what tests/ext_ram/ddr3_serdes_phy measures -- the offset the
  -- part's CAS latency and the two pipelines put the burst at, and the
  -- middle of the run of taps it survives.
  constant serdes_simulation_board_c: serdes_board_t := (
    read_offset => 47,
    read_tap => 10,
    write_slip => 8,
    dq_enable_lead => 0,
    dqs_enable_lead => 0,
    strobe_invert => false
    );

  -- DDR3 PHY built from ordinary serialisers and an input delay line,
  -- for a family with no memory flavoured IO block.
  --
  -- It asks two things of its surroundings that the generic blocks do
  -- not provide: a memory rate clock pair a quarter of a period apart,
  -- which is where the strobe's placement inside the data eye comes
  -- from, and a variable input delay per data pin, which is what the
  -- read eye is walked onto the sampling clock with.
  component ddr3_phy_serdes is
    generic(
      part_c: dram_part_t;
      timing_c: dram_timing_t;
      dfi_config_c: config_t;
      -- What the board this is built for measured.  The PHY applies it
      -- by itself at reset and holds dfi_o.init_complete low until it
      -- has.
      board_c: serdes_board_t;
      -- Which pins carry the quarter period the write needs, which is
      -- the family's answer and not the board's.  False leaves it on
      -- the data and the mask, which a 7-series pin takes while its
      -- capture runs on the unshifted clock.  A Gowin pin refuses two
      -- clock pairs at once -- its input and output serialisers share
      -- one control set -- so true moves the shift onto the strobe,
      -- the clock and the command pins and leaves both directions of
      -- every data pin on the unshifted pair.
      shift_strobe_c: boolean := false;
      -- Hold a command's address and bank on the pins for the memory
      -- tick before the command as well, which a tick that deselects
      -- the part has no use of.  It is a board's answer rather than a
      -- family's -- an address pin the board routes away from the rest
      -- is what asks for it -- but it sits here and not in
      -- serdes_board_t because a record every board states in full
      -- cannot gain a field without every board being rewritten.  The
      -- select pins never move with it, so the part still sees one
      -- command.
      early_address_c: boolean := false
      );
    port(
      clock_i: in std_ulogic;
      fast_clock_i: in std_ulogic;
      data_clock_i: in std_ulogic;
      -- Controller rate, shifted the same quarter of a memory period
      -- as data_clock_i: the parallel clock of whichever group takes
      -- the shifted fast one.  A family whose pins take two pairs at
      -- once may tie it to clock_i.
      shifted_clock_i: in std_ulogic;
      delay_ref_clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      dfi_i: in master_t;
      dfi_o: out slave_t;

      -- The board record's whole-slot figures, as ports a bench may
      -- sweep.  A design leaves every one of them open and gets what
      -- the record says.
      --
      -- Each is sampled once on the way in, so moving one takes effect
      -- a cycle later.  They are quasi-static: a host writes one and
      -- waits for the next reading.
      --
      -- Slots from the cycle a read was announced on to the slot its
      -- first beat is found in.
      read_offset_i: in unsigned(6 downto 0)
        := to_unsigned(board_c.read_offset, 7);

      -- Where the data sits against the strobe, in whole slots; eight
      -- is the quarter period the clock pair provides and nothing
      -- more.  The range is a word either way because the serialiser
      -- hands its parallel word across to its fast side entire, and
      -- the data's fast clock is not the one its parallel side runs
      -- on: the burst lands a whole cycle from where an aligned pair
      -- would put it, one way or the other.
      write_slip_i: in unsigned(3 downto 0)
        := to_unsigned(board_c.write_slip, 4);

      -- Slots by which the family puts a pad's tristate word on the
      -- pin ahead of the data word beside it, for the data pads and
      -- for the strobe.  The tristate register sits outside the word
      -- pipeline, so the two need not arrive together; zero is a
      -- family where they do.  Measured on a board by reading a pad
      -- back, since a released pad reads differently pass to pass.
      dq_enable_lead_i: in unsigned(3 downto 0)
        := to_unsigned(board_c.dq_enable_lead, 4);
      dqs_enable_lead_i: in unsigned(3 downto 0)
        := to_unsigned(board_c.dqs_enable_lead, 4);

      -- Turn the strobe pattern round in the word the serialiser is
      -- given, for a board that presents the pair the other way
      -- about.  A part reads its beats off the sense of the strobe
      -- against its data.
      strobe_invert_i: in std_ulogic
        := to_logic(board_c.strobe_invert);

      -- One delay line step per pulse, per data pin, on top of where
      -- the record left the lines at reset; the mark says a line is at
      -- its shortest tap.
      dq_delay_shift_i: in std_ulogic_vector;
      dq_delay_mark_o: out std_ulogic_vector;

      write_level_i: in std_ulogic := '0';
      -- One bit per data pin: pins that disagree are a bus nobody is
      -- driving.
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
      dqs_o: out nsl_io.io.tristated_vector;
      dqs_n_o: out nsl_io.io.tristated_vector;
      dq_o: out nsl_io.io.tristated_vector;
      dq_i: in std_ulogic_vector
      );
  end component;

end package ddr3_io;
