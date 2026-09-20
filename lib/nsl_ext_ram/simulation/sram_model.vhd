library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;

-- Behavioural model of a synchronous pipelined SRAM with no bus
-- latency, wired as the boards use it: the burst counter's load input
-- strapped asserted, so every clock rise takes a new address.
--
-- Datasheet violations are reported in picoseconds rather than in
-- ticks, so a controller that is right at one clock rate and wrong at
-- another does not pass quietly.
--
-- Setup and hold are measured with 'last_event rather than 'stable:
-- the latter answers true for a composite signal under GHDL whatever
-- has just happened to it, which would leave the address and byte
-- write checks with no teeth at all.
--
-- Output enable is modelled as an ideal gate.  Its access and
-- disable times are in the part description and are not applied,
-- because a controller that holds the pin asserted -- which is what
-- the part's own tri-stating makes the sensible choice -- never
-- exercises them.  A controller that toggles it wants them added, and
-- wants a test that fails without them.
entity sram_model is
  generic(
    part_c: sram_part_t;
    check_timing_c: boolean := true
    );
  port(
    clock_i: in std_ulogic;
    -- Chip select, standing for all of the part's enables
    cs_n_i: in std_ulogic;
    -- Clock enable: a rise it is deasserted for changes nothing
    cen_n_i: in std_ulogic;
    we_n_i: in std_ulogic;
    bw_n_i: in std_ulogic_vector;
    oe_n_i: in std_ulogic;
    a_i: in unsigned;

    dq_i: in std_ulogic_vector;
    dq_o: out nsl_io.io.tristated_vector;
    dqp_i: in std_ulogic_vector;
    dqp_o: out nsl_io.io.tristated_vector;

    -- Datasheet violations seen so far.  A report alone does not fail
    -- a run, and a check that cannot fail one is not a check.
    violation_count_o: out natural
    );
end entity;

architecture beh of sram_model is

  constant lane_count_c: natural := part_c.dq_byte_count;
  constant word_count_c: natural := 2 ** part_c.address_width;

  -- Storage is cut in pages allocated on first write.  A word never
  -- straddles a page boundary.
  constant page_word_l2_c: natural := 10;
  constant page_word_c: natural := 2 ** page_word_l2_c;
  constant page_count_c: natural := word_count_c / page_word_c;

  subtype word_t is byte_string(0 to lane_count_c - 1);
  subtype lane_bits_t is std_ulogic_vector(0 to lane_count_c - 1);

  type page_access_t is access byte_string;
  type parity_access_t is access std_ulogic_vector;
  type page_table_t is array (natural range <>) of page_access_t;
  type parity_table_t is array (natural range <>) of parity_access_t;

  -- What one clock rise took in.
  type command_t is
  record
    selected: boolean;
    write: boolean;
    lane_n: lane_bits_t;
    address: natural;
  end record;

  constant deselected_c: command_t := (selected => false,
                                       write => false,
                                       lane_n => (others => '1'),
                                       address => 0);

  signal value_s: word_t := (others => (others => 'U'));
  signal parity_s: lane_bits_t := (others => 'U');
  signal driving_s: boolean := false;

  -- The coming clock rise takes write data off the bus
  signal write_due_s: boolean := false;

  signal command_violation_s: natural := 0;
  signal hold_violation_s: natural := 0;

  -- Every hold this part specifies is the same number, so one wait
  -- serves them all.  A part where they differ wants a deadline each,
  -- and the assert below says so before it is silently mis-checked.
  constant hold_ps_c: natural := part_c.ah_ps;

begin

  assert bw_n_i'length = lane_count_c
    report "sram_model: byte write port is " & integer'image(bw_n_i'length)
    & " bits, part has " & integer'image(lane_count_c) & " lanes"
    severity failure;

  assert dq_i'length = lane_count_c * 8
    report "sram_model: data port width does not match the part"
    severity failure;

  assert a_i'length >= part_c.address_width
    report "sram_model: address port is too narrow for the part"
    severity failure;

  assert part_c.dh_ps = hold_ps_c and part_c.cenh_ps = hold_ps_c
    and part_c.weh_ps = hold_ps_c and part_c.ceh_ps = hold_ps_c
    report "sram_model: the part holds its inputs for different times, "
    & "which this model checks against a single deadline"
    severity failure;

  violation_count_o <= command_violation_s + hold_violation_s;

  core: process(clock_i) is
    variable pages: page_table_t(0 to page_count_c - 1);
    variable parities: parity_table_t(0 to page_count_c - 1);

    -- Commands taken in by the previous rise and the one before it
    variable stage1, stage2: command_t := deselected_c;
    variable last_edge: time := 0 ps;
    variable last_rise: time := 0 ps;
    variable last_fall: time := 0 ps;

    variable violations: natural := 0;

    procedure check(condition: in boolean; message: in string) is
    begin
      if check_timing_c and not condition then
        violations := violations + 1;
        command_violation_s <= violations;
        report "sram_model: " & message
          severity error;
      end if;
    end procedure;

    procedure store(address: in natural;
                    lane_n: in lane_bits_t;
                    value: in word_t;
                    parity: in lane_bits_t) is
      variable page: natural := address / page_word_c;
      variable base: natural := (address mod page_word_c) * lane_count_c;
    begin
      if pages(page) = null then
        pages(page) := new byte_string(0 to page_word_c * lane_count_c - 1);
        parities(page) := new std_ulogic_vector(0 to page_word_c * lane_count_c - 1);
      end if;

      for i in 0 to lane_count_c - 1
      loop
        if lane_n(i) = '0' then
          pages(page)(base + i) := value(i);
          parities(page)(base + i) := parity(i);
        end if;
      end loop;
    end procedure;

    procedure fetch(address: in natural;
                    value: out word_t;
                    parity: out lane_bits_t) is
      variable page: natural := address / page_word_c;
      variable base: natural := (address mod page_word_c) * lane_count_c;
    begin
      if pages(page) = null then
        value := (others => (others => 'U'));
        parity := (others => 'U');
      else
        for i in 0 to lane_count_c - 1
        loop
          value(i) := pages(page)(base + i);
          parity(i) := parities(page)(base + i);
        end loop;
      end if;
    end procedure;

    variable taken: command_t;
    variable word: word_t;
    variable parity: lane_bits_t;
    variable written: word_t;
  begin
    if falling_edge(clock_i) then
      check(now - last_rise >= part_c.ch_ps * 1 ps,
            "clock high time violated");
      last_fall := now;
    end if;

    if rising_edge(clock_i) then
      if last_edge /= 0 ps then
        check(now - last_edge >= part_c.tck_min_ps * 1 ps,
              "clock period is shorter than the part supports");
      end if;
      if last_fall /= 0 ps then
        check(now - last_fall >= part_c.cl_ps * 1 ps,
              "clock low time violated");
      end if;
      last_edge := now;
      last_rise := now;

      if cen_n_i = '0' then
        check(cs_n_i'last_event >= part_c.ces_ps * 1 ps,
              "chip select setup time violated");

        -- A deselected rise takes an address and a direction in all
        -- the same, and does nothing with them, so only a selected one
        -- is held to the datasheet.
        if cs_n_i = '0' then
          check(we_n_i'last_event >= part_c.wes_ps * 1 ps
                and bw_n_i'last_event >= part_c.wes_ps * 1 ps,
                "write control setup time violated");
          check(a_i'last_event >= part_c.as_ps * 1 ps,
                "address setup time violated");
        end if;

        if write_due_s then
          check(dq_i'last_event >= part_c.ds_ps * 1 ps
                and dqp_i'last_event >= part_c.ds_ps * 1 ps,
                "write data setup time violated");
        end if;

        -- The command taken two rises ago hands its payload over now.
        if stage2.selected and stage2.write then
          for i in 0 to lane_count_c - 1
          loop
            written(i) := dq_i(dq_i'low + i * 8 + 7 downto dq_i'low + i * 8);
            parity(i) := dqp_i(dqp_i'low + i);
          end loop;
          store(stage2.address, stage2.lane_n, written, parity);
        end if;

        -- The command taken one rise ago reaches the output register.
        if stage1.selected and not stage1.write then
          check(now >= part_c.power_ps * 1 ps,
                "the part was accessed before its supply had settled");
          fetch(stage1.address, word, parity);
          value_s <= word after part_c.co_ps * 1 ps;
          parity_s <= parity after part_c.co_ps * 1 ps;
          driving_s <= true after part_c.clz_ps * 1 ps;
        else
          driving_s <= false after part_c.chz_ps * 1 ps;
        end if;

        taken.selected := cs_n_i = '0';
        taken.write := we_n_i = '0';
        taken.lane_n := bw_n_i;
        taken.address := to_integer(a_i(part_c.address_width - 1 downto 0));

        if taken.selected then
          check(now >= part_c.power_ps * 1 ps,
                "the part was accessed before its supply had settled");
        end if;

        write_due_s <= stage1.selected and stage1.write;

        stage2 := stage1;
        stage1 := taken;
      end if;

      check(cen_n_i'last_event >= part_c.cens_ps * 1 ps,
            "clock enable setup time violated");
    end if;
  end process;

  pins: process(value_s, parity_s, driving_s, oe_n_i) is
  begin
    for i in 0 to lane_count_c - 1
    loop
      if driving_s and oe_n_i = '0' then
        dqp_o(dqp_o'low + i) <= nsl_io.io.to_tristated(parity_s(i));
        for b in 0 to 7
        loop
          dq_o(dq_o'low + i * 8 + b)
            <= nsl_io.io.to_tristated(value_s(i)(b));
        end loop;
      else
        dqp_o(dqp_o'low + i) <= nsl_io.io.tristated_z;
        for b in 0 to 7
        loop
          dq_o(dq_o'low + i * 8 + b) <= nsl_io.io.tristated_z;
        end loop;
      end if;
    end loop;
  end process;

  has_checks: if check_timing_c
  generate
    hold: process is
      variable selected: boolean;
      variable paying: boolean;
      variable violations: natural := 0;

      procedure check(condition: in boolean; message: in string) is
      begin
        if not condition then
          violations := violations + 1;
          hold_violation_s <= violations;
          report "sram_model: " & message
            severity error;
        end if;
      end procedure;
    begin
      wait until rising_edge(clock_i);

      if cen_n_i = '0' then
        selected := cs_n_i = '0';
        paying := write_due_s;

        wait for hold_ps_c * 1 ps;

        check(cs_n_i'last_event >= hold_ps_c * 1 ps
              and cen_n_i'last_event >= hold_ps_c * 1 ps
              and (not selected
                   or (we_n_i'last_event >= hold_ps_c * 1 ps
                       and bw_n_i'last_event >= hold_ps_c * 1 ps
                       and a_i'last_event >= hold_ps_c * 1 ps)),
              "command hold time violated");

        if paying then
          check(dq_i'last_event >= hold_ps_c * 1 ps
                and dqp_i'last_event >= hold_ps_c * 1 ps,
                "write data hold time violated");
        end if;
      end if;
    end process;
  end generate;

end architecture;
