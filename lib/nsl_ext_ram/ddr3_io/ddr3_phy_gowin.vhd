library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;

-- Pin side of a DDR3 controller on a fifth generation Gowin part.
--
-- The family carries a block for exactly this job, and everything here
-- is built around it rather than around the general purpose
-- serialisers.  Per byte lane, DQS takes the fast clock and the strobe
-- arriving from the part, and hands back three clocks:
--
--   DQSW0    a delayed fast clock, which clocks the strobe out
--   DQSW270  a further quarter of a bit on, which clocks data and mask
--            out, so the strobe lands in the middle of the data eye
--   DQSR90   a quarter of a bit into the incoming eye, which captures
--
-- That quarter bit is the thing a plain serialiser cannot produce: it
-- has no clock input of its own, so placing a strobe against data with
-- one costs a second clock domain, and a pad will not carry an input
-- serialiser on one clock beside an output register on another.  The
-- memory flavoured serialisers take the block's clock on TCLK instead.
--
-- Two knobs train the interface, both in silicon:
--
--   WSTEP    delays DQSW0 against the fast clock, which is write
--            levelling: it walks the strobe's first rising edge onto
--            the memory clock's, which is all tDQSS asks
--   DLLSTEP  does the same for the capture clock
--
-- and RPOINT, WPOINT and RVALID are the read gate and the pointers of
-- the capture FIFO each lane's input serialiser carries.
entity ddr3_phy_gowin is
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
    -- The strobe is differential; both halves come off the same
    -- generator so they cannot drift apart.
    dqs_o: out nsl_io.io.tristated_vector;
    dqs_n_o: out nsl_io.io.tristated_vector;
    dqs_i: in std_ulogic_vector;
    dq_o: out nsl_io.io.tristated_vector;
    dq_i: in std_ulogic_vector
    );
end entity;

architecture gowin of ddr3_phy_gowin is

  constant lane_count_c: natural := dfi_config_c.dq_byte_count;
  constant slot_count_c: natural := slot_count(dfi_config_c);

  attribute syn_black_box: boolean;

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

  -- The strobe generator works in taps of a delay line and does not
  -- measure one itself: the tap length comes from a loop locked to the
  -- fast clock, and the tools refuse a generator whose step arrives
  -- from anywhere else.  One of these serves every lane, so it is not
  -- a knob and does not appear on the entity.
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

  component IDES8_MEM is
    port(
      D, RESET : in std_logic;
      CALIB : in std_logic;
      FCLK, ICLK, PCLK : in std_logic;
      Q0, Q1, Q2, Q3, Q4, Q5, Q6, Q7 : out std_logic;
      WADDR : in std_logic_vector(2 downto 0);
      RADDR : in std_logic_vector(2 downto 0)
      );
  end component;
  attribute syn_black_box of IDES8_MEM : component is true;

  signal reset_s: std_logic;
  signal captured_s: std_ulogic_vector(dq_i'length * slot_count_c - 1 downto 0);
  signal valid_s: std_ulogic_vector(lane_count_c - 1 downto 0);
  -- A lane says so when a burst landed inside its gate, which is how
  -- the gate gets walked onto the data in the first place.
  signal burst_seen_s: std_ulogic_vector(lane_count_c - 1 downto 0);
  signal dll_step_s: std_logic_vector(7 downto 0);
  signal level_meta_s: std_ulogic_vector(lane_count_c - 1 downto 0);

  constant a_width_c: natural := a_o'length;
  constant ba_width_c: natural := ba_o'length;

  -- Every command pin carries one slot per half tick, so a command
  -- placed on a phase reaches the part on that phase's tick and on no
  -- other.
  type slot_word_vector is array (natural range <>)
    of std_ulogic_vector(0 to slot_count_c - 1);

  signal cke_word_s, cs_word_s, ras_word_s, cas_word_s, we_word_s,
    odt_word_s: std_ulogic_vector(0 to slot_count_c - 1);
  signal a_word_s: slot_word_vector(0 to a_width_c - 1);
  signal ba_word_s: slot_word_vector(0 to ba_width_c - 1);
  signal ck_word_s, ck_n_word_s: std_ulogic_vector(0 to slot_count_c - 1);

  -- Whether the strobe generator carries the half cycle itself.  The
  -- vendor picks this by write latency alone, and by read latency
  -- where two settings meet; the table is theirs, transcribed rather
  -- than derived, because nothing published says what the block does
  -- differently.  Getting it wrong puts the strobe half a cycle from
  -- where write levelling can reach.
  function hardware_levelling(wl, rl: natural) return string is
  begin
    case wl is
      when 5|9|13|17|18|21|25 =>
        return "false";
      when 6|7|8|10|11|14|15|20|22|24 =>
        return "true";
      when 12 =>
        if rl = 16 then return "false"; else return "true"; end if;
      when 16 =>
        if rl = 24 then return "false"; else return "true"; end if;
      when 19|23 =>
        if rl = 27 then return "false"; else return "true"; end if;
      when others =>
        assert false
          report "ddr3_phy_gowin: no strobe generator setting for this write latency"
          severity failure;
        return "false";
    end case;
  end function;

begin

  assert dfi_config_c.edge_count = 2
    report "ddr3_phy_gowin: DDR3 carries two data words per tick"
    severity failure;

  assert ba_o'length <= max_bank_width_c
    report "ddr3_phy_gowin: the bank bus is wider than a command carries"
    severity failure;

  assert a_o'length <= max_address_width_c
    report "ddr3_phy_gowin: the address bus is wider than a command carries"
    severity failure;

  assert slot_count_c = 8
    report "ddr3_phy_gowin: the memory serialisers move eight slots a cycle"
    severity failure;

  reset_s <= not reset_n_i;

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
      clkin => fast_clock_i,
      reset => reset_s
      );

  lane: for l in 0 to lane_count_c - 1
  generate
    signal dqsr90_s, dqsw0_s, dqsw270_s: std_logic;
    signal rpoint_s, wpoint_s: std_logic_vector(2 downto 0);
    signal rvalid_s, burst_s: std_logic;
    signal strobe_gate_s, strobe_gate_n_s: std_logic;
    signal strobe_off_s: std_logic_vector(2 downto 0);
    signal dqs_disable_s, dqs_n_disable_s: std_logic;
    signal data_off_s: std_logic;
  begin

    -- One block a lane: its strobe is what the block phases against.
    timing_block: DQS
      generic map(
        DQS_MODE => "X4",
        HWL => hardware_levelling(timing_c.cwl, timing_c.cl)
        )
      port map(
        dqsin => dqs_i(dqs_i'low + l),
        pclk => clock_i,
        fclk => fast_clock_i,
        reset => reset_s,
        read => std_logic_vector(read_gate_i),
        rclksel => std_logic_vector(read_gate_select_i),
        dllstep => dll_step_s,
        wstep => std_logic_vector(write_step_i),
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
        rpoint => rpoint_s,
        wpoint => wpoint_s,
        rvalid => rvalid_s,
        rburst => burst_s,
        rflag => open,
        wflag => open
        );

    valid_s(l) <= rvalid_s;
    burst_seen_s(l) <= burst_s;

    -- A strobe is a clock that only runs over its burst: every other
    -- slot carries the gate, and the three tristate words shape the
    -- preamble ahead of it and the postamble behind.
    strobe_gate_s <= dfi_i.wrdata_en(0);
    strobe_gate_n_s <= not dfi_i.wrdata_en(0);
    strobe_off_s <= (others => not dfi_i.wrdata_en(0));
    data_off_s <= (not dfi_i.wrdata_en(0)) or write_level_i;

    strobe: OSER8_MEM
      generic map(
        TCLK_SOURCE => "DQSW"
        )
      port map(
        d0 => '0', d1 => strobe_gate_s,
        d2 => '0', d3 => strobe_gate_s,
        d4 => '0', d5 => strobe_gate_s,
        d6 => '0', d7 => strobe_gate_s,
        tx0 => strobe_off_s(2),
        tx1 => strobe_off_s(1),
        tx2 => strobe_off_s(1),
        tx3 => strobe_off_s(0),
        pclk => clock_i,
        reset => reset_s,
        fclk => fast_clock_i,
        tclk => dqsw0_s,
        q0 => dqs_o(dqs_o'low + l).v,
        q1 => dqs_disable_s
        );

    strobe_n: OSER8_MEM
      generic map(
        TCLK_SOURCE => "DQSW"
        )
      port map(
        d0 => '1', d1 => strobe_gate_n_s,
        d2 => '1', d3 => strobe_gate_n_s,
        d4 => '1', d5 => strobe_gate_n_s,
        d6 => '1', d7 => strobe_gate_n_s,
        tx0 => strobe_off_s(2),
        tx1 => strobe_off_s(1),
        tx2 => strobe_off_s(1),
        tx3 => strobe_off_s(0),
        pclk => clock_i,
        reset => reset_s,
        fclk => fast_clock_i,
        tclk => dqsw0_s,
        q0 => dqs_n_o(dqs_n_o'low + l).v,
        q1 => dqs_n_disable_s
        );

    dqs_o(dqs_o'low + l).en <= not dqs_disable_s;
    dqs_n_o(dqs_n_o'low + l).en <= not dqs_n_disable_s;

    bit: for b in 0 to 7
    generate
      constant pin_c: natural := l * 8 + b;
      signal word_s: std_ulogic_vector(0 to slot_count_c - 1);
      signal dq_disable_s: std_logic;
    begin

      -- Data leaves a quarter of a bit ahead of the strobe, which is
      -- what puts the strobe in the middle of its eye.
      slot_map: for s in 0 to slot_count_c - 1
      generate
        word_s(s) <= dfi_i.wrdata(s).value(l)(b);
      end generate;

      driver: OSER8_MEM
        generic map(
          TCLK_SOURCE => "DQSW270"
          )
        port map(
          d0 => word_s(0), d1 => word_s(1),
          d2 => word_s(2), d3 => word_s(3),
          d4 => word_s(4), d5 => word_s(5),
          d6 => word_s(6), d7 => word_s(7),
          tx0 => data_off_s,
          tx1 => data_off_s,
          tx2 => data_off_s,
          tx3 => data_off_s,
          pclk => clock_i,
          reset => reset_s,
          fclk => fast_clock_i,
          tclk => dqsw270_s,
          q0 => dq_o(dq_o'low + pin_c).v,
          q1 => dq_disable_s
          );

      -- The pad's enable has to come off the serialiser's own tristate
      -- output; the tools refuse a memory serialiser driving a pad
      -- whose enable arrives from the fabric.  Letting go of the line
      -- while levelling goes through the serialiser's tristate inputs
      -- rather than through here.
      dq_o(dq_o'low + pin_c).en <= not dq_disable_s;

      -- Capture rides the part's own strobe, a quarter of a bit into
      -- the eye, through the FIFO the block keeps pointers for.
      listener: IDES8_MEM
        port map(
          d => dq_i(dq_i'low + pin_c),
          reset => reset_s,
          calib => '0',
          fclk => fast_clock_i,
          iclk => dqsr90_s,
          pclk => clock_i,
          q0 => captured_s(pin_c * slot_count_c + 0),
          q1 => captured_s(pin_c * slot_count_c + 1),
          q2 => captured_s(pin_c * slot_count_c + 2),
          q3 => captured_s(pin_c * slot_count_c + 3),
          q4 => captured_s(pin_c * slot_count_c + 4),
          q5 => captured_s(pin_c * slot_count_c + 5),
          q6 => captured_s(pin_c * slot_count_c + 6),
          q7 => captured_s(pin_c * slot_count_c + 7),
          waddr => wpoint_s,
          raddr => rpoint_s
          );
    end generate;

    -- The mask never hides anything yet; a controller that needs it
    -- wants a serialiser of its own here, off DQSW270 like the data.
    dm_o(dm_o'low + l) <= '0';
  end generate;

  -- A command belongs to one tick, and a controller cycle carries one
  -- per phase, so every command pin goes out through a serialiser
  -- running at tick rate rather than being held for a whole cycle.
  -- Holding chip select for a cycle would hand the part the same
  -- command once a tick for four ticks.
  --
  -- Serialising the address and control alongside chip select is what
  -- keeps them together: a pin driven from a plain register arrives
  -- ahead of one driven from a serialiser, and a command whose select
  -- pulse lands after its address has moved on reaches the part as a
  -- no-op.
  words: process(dfi_i) is
    variable cmd: command_t;
    variable a: unsigned(max_address_width_c - 1 downto 0);
    variable b: unsigned(max_bank_width_c - 1 downto 0);
    variable slot: natural;
  begin
    for phase in 0 to dfi_config_c.phase_count - 1
    loop
      cmd := dfi_i.command(phase);
      a := resize(address(dfi_config_c, cmd), max_address_width_c);
      b := resize(bank(dfi_config_c, cmd), max_bank_width_c);

      for edge in 0 to dfi_config_c.edge_count - 1
      loop
        slot := phase * dfi_config_c.edge_count + edge;

        cke_word_s(slot) <= cmd.cke;
        cs_word_s(slot) <= cmd.cs_n;
        ras_word_s(slot) <= cmd.ras_n;
        cas_word_s(slot) <= cmd.cas_n;
        we_word_s(slot) <= cmd.we_n;
        odt_word_s(slot) <= cmd.odt;

        for i in 0 to a_width_c - 1
        loop
          a_word_s(i)(slot) <= a(i);
        end loop;

        for i in 0 to ba_width_c - 1
        loop
          ba_word_s(i)(slot) <= b(i);
        end loop;
      end loop;
    end loop;
  end process;

  -- The part samples on the rising edge, so it falls in the middle of
  -- a tick's worth of command rather than on its boundary.
  ck_pattern: for slot in 0 to slot_count_c - 1
  generate
    ck_word_s(slot) <= '0' when slot mod 2 = 0 else '1';
    ck_n_word_s(slot) <= '1' when slot mod 2 = 0 else '0';
  end generate;

  -- One serialiser a pin, all of them on the one clock pair.
  command_pins: block is
  begin
    ck_p: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => ck_word_s, serial_o => ck_o.p);

    ck_n: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => ck_n_word_s, serial_o => ck_o.n);

    cke: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => cke_word_s, serial_o => cke_o);

    cs: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => cs_word_s, serial_o => cs_n_o);

    ras: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => ras_word_s, serial_o => ras_n_o);

    cas: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => cas_word_s, serial_o => cas_n_o);

    we: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => we_word_s, serial_o => we_n_o);

    odt: nsl_io.serdes.serdes_output
      generic map(left_first_c => true, ddr_mode_c => true,
                  ratio_c => slot_count_c)
      port map(serial_clock_i => fast_clock_i,
               parallel_clock_i => clock_i, reset_n_i => reset_n_i,
               parallel_i => odt_word_s, serial_o => odt_o);

    address_pins: for i in 0 to a_width_c - 1
    generate
      line: nsl_io.serdes.serdes_output
        generic map(left_first_c => true, ddr_mode_c => true,
                    ratio_c => slot_count_c)
        port map(serial_clock_i => fast_clock_i,
                 parallel_clock_i => clock_i, reset_n_i => reset_n_i,
                 parallel_i => a_word_s(i), serial_o => a_o(a_o'low + i));
    end generate;

    bank_pins: for i in 0 to ba_width_c - 1
    generate
      line: nsl_io.serdes.serdes_output
        generic map(left_first_c => true, ddr_mode_c => true,
                    ratio_c => slot_count_c)
        port map(serial_clock_i => fast_clock_i,
                 parallel_clock_i => clock_i, reset_n_i => reset_n_i,
                 parallel_i => ba_word_s(i), serial_o => ba_o(ba_o'low + i));
    end generate;
  end block;

  -- What the part sampled of the memory clock, one bit a lane off its
  -- prime data line.
  levelling: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      for l in 0 to lane_count_c - 1
      loop
        level_meta_s(l) <= dq_i(dq_i'low + l * 8);
        write_level_answer_o(write_level_answer_o'low + l) <= level_meta_s(l);
      end loop;
    end if;
  end process;

  -- The reset pin is not a command and changes far slower than a tick.
  memory_reset: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      ram_reset_n_o <= dfi_i.reset_n;
    end if;

    if reset_n_i = '0' then
      ram_reset_n_o <= '0';
    end if;
  end process;

  answer: process(captured_s, valid_s, burst_seen_s) is
    variable word: byte_string(0 to max_dq_byte_count_c - 1);
  begin
    dfi_o <= slave_defaults(dfi_config_c);

    for s in 0 to slot_count_c - 1
    loop
      word := (others => dontcare_byte_c);
      for l in 0 to lane_count_c - 1
      loop
        for b in 0 to 7
        loop
          word(l)(b) := captured_s((l * 8 + b) * slot_count_c + s);
        end loop;
      end loop;
      dfi_o.rddata(s) <= data(dfi_config_c, word(0 to lane_count_c - 1));
    end loop;

    dfi_o.rddata_valid <= valid_s(0);
    read_gate_ok_o <= burst_seen_s(0);
    dfi_o.init_complete <= '1';
  end process;

end architecture;
