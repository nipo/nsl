library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;

entity ddr3_model is
  generic(
    part_c: dram_part_t;
    check_timing_c: boolean := true;
    -- Skew between the strobe and the data it carries, on reads
    tdqsq_ps_c: natural := 150;
    -- Data valid window a write strobe edge has to sit in
    tds_ps_c: natural := 125;
    -- Command setup against the clock
    tis_ps_c: natural := 350
    );
  port(
    ck_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    cke_i: in std_ulogic;
    cs_n_i: in std_ulogic;
    ras_n_i: in std_ulogic;
    cas_n_i: in std_ulogic;
    we_n_i: in std_ulogic;
    ba_i: in unsigned;
    a_i: in unsigned;
    odt_i: in std_ulogic;

    -- One per byte lane
    dm_i: in std_ulogic_vector;
    dqs_i: in std_ulogic_vector;
    dqs_o: out nsl_io.io.tristated_vector;

    dq_i: in std_ulogic_vector;
    dq_o: out nsl_io.io.tristated_vector;

    -- Datasheet violations seen so far.  A report alone does not fail
    -- a run, and a check that cannot fail one is not a check.
    violation_count_o: out natural
    );
end entity;

-- Commands are sampled on the clock, data travels with the strobe.
--
-- On a read the model drives a preamble, eight data beats with the
-- strobe edge aligned on the data transition, and a postamble.  On a
-- write it captures the data on every strobe edge, which is where the
-- part expects the middle of the eye: a PHY that forwards the strobe
-- aligned with its data instead of centred trips the setup check.
--
-- Storage is sparse and a location that was never written reads as
-- undefined.
architecture beh of ddr3_model is

  constant bank_count_c: natural := 2 ** part_c.bank_count_l2;
  constant row_count_c: natural := 2 ** part_c.row_count_l2;
  constant column_count_c: natural := 2 ** part_c.column_count_l2;
  constant lane_count_c: natural := part_c.dq_width / 8;
  constant burst_c: natural := 2 ** part_c.prefetch_l2;

  constant page_column_l2_c: natural := 8;
  constant page_column_c: natural := 2 ** page_column_l2_c;
  constant page_byte_c: natural := page_column_c * lane_count_c;
  constant page_count_c: natural
    := bank_count_c * row_count_c * (column_count_c / page_column_c);

  type page_access_t is access byte_string;
  type page_table_t is array (natural range <>) of page_access_t;

  type bank_state_t is
  record
    active: boolean;
    row: natural;
    activated_at: time;
    precharged_at: time;
    written_at: time;
  end record;

  type bank_state_vector is array (natural range <>) of bank_state_t;

  -- Column to column, which is what a burst holds the data bus for.
  constant ccd_ck_c: natural := burst_c / 2;

  -- Write bursts the part may be carrying at once.  A write command
  -- comes tCCD after the one before it while its own data is still CAS
  -- write latency away, so what is on the wire and what has been
  -- commanded are several bursts apart.
  constant write_depth_c: natural := 8;

  signal violation_s: natural := 0;

begin

  violation_count_o <= violation_s;

  assert part_c.generation = DRAM_DDR3
    report "ddr3_model: part is not DDR3"
    severity failure;

  assert dq_i'length = part_c.dq_width
    report "ddr3_model: data port width does not match the part"
    severity failure;

  assert dqs_i'length = lane_count_c and dm_i'length = lane_count_c
    report "ddr3_model: one strobe and one mask per byte lane"
    severity failure;

  core: process(ck_i, dqs_i, reset_n_i) is
    variable pages: page_table_t(0 to page_count_c - 1);
    variable bank: bank_state_vector(0 to bank_count_c - 1)
      := (others => (active => false, row => 0,
                     activated_at => 0 ps, precharged_at => 0 ps,
                     written_at => 0 ps));

    variable cl, cwl: natural := 5;
    variable initialised: boolean := false;
    variable dll_reset_at: time := 0 ps;

    variable last_edge: time := 0 ps;
    variable tck: time := 0 ps;
    variable last_refresh: time := 0 ps;
    variable refresh_credit: integer := 0;
    variable last_activate: time := 0 ps;

    -- Write bursts commanded and not yet wholly taken in, oldest
    -- first.  The command of one burst arrives while the data of the
    -- one before it is still being taken, so where a beat belongs is
    -- read out of this rather than out of one set of registers.
    type write_entry_t is
    record
      bank: natural;
      row: natural;
      column: natural;
    end record;
    type write_entry_vector is array (natural range <>) of write_entry_t;
    type lane_beat_vector is array (natural range <>) of natural;
    type lane_flag_vector is array (natural range <>) of boolean;

    variable write_queue: write_entry_vector(0 to write_depth_c - 1);
    -- Commands taken in, and bursts each lane has finished taking; a
    -- lane is filling entry write_done(lane) while that is behind
    -- write_issued.  They only ever count up, so an entry is at
    -- index mod write_depth_c and the difference is what is in the air.
    variable write_issued: natural := 0;
    variable write_done: lane_beat_vector(0 to lane_count_c - 1)
      := (others => 0);
    variable write_started: lane_flag_vector(0 to lane_count_c - 1)
      := (others => false);
    variable write_beat: lane_beat_vector(0 to lane_count_c - 1)
      := (others => 0);
    variable dqs_previous: std_ulogic_vector(dqs_i'range) := (others => 'U');
    variable entry: write_entry_t;

    -- Column commands, so tCCD can be checked, and read commands on
    -- their own, because what says whether a read burst needs a
    -- preamble is the read before it and not any column command.
    variable last_column: time := 0 ps;
    variable last_read: time := 0 ps;

    variable violations: natural := 0;

    -- The oldest burst any lane is still taking, which is the tail of
    -- the queue.
    impure function write_oldest return natural is
      variable oldest: natural;
    begin
      oldest := write_issued;

      for lane in 0 to lane_count_c - 1
      loop
        if write_done(lane) < oldest then
          oldest := write_done(lane);
        end if;
      end loop;

      return oldest;
    end function;

    variable cmd: command_enum_t;
    variable ba, row, col: natural;

    procedure locate(bank_index, row_index, column_index: in natural;
                     page: out natural;
                     offset: out natural) is
      variable linear: natural;
    begin
      linear := (bank_index * row_count_c + row_index) * column_count_c
                + column_index;
      page := linear / page_column_c;
      offset := (linear mod page_column_c) * lane_count_c;
    end procedure;

    procedure store(bank_index, row_index, column_index, lane: in natural;
                    value: in std_ulogic_vector(7 downto 0)) is
      variable page, offset: natural;
    begin
      locate(bank_index, row_index, column_index, page, offset);

      if pages(page) = null then
        pages(page) := new byte_string(0 to page_byte_c - 1);
        pages(page).all := (others => (others => 'U'));
      end if;

      pages(page).all(offset + lane) := value;
    end procedure;

    impure function fetch(bank_index, row_index, column_index, lane: natural)
      return std_ulogic_vector is
      variable page, offset: natural;
    begin
      locate(bank_index, row_index, column_index, page, offset);

      if pages(page) = null then
        return "UUUUUUUU";
      end if;

      return pages(page).all(offset + lane);
    end function;

    -- Column visited at a given step of the burst, wrapping inside the
    -- group of eight the part sequences by itself.
    function burst_column(base, step: natural) return natural is
      variable low: natural;
    begin
      low := (base + step) mod burst_c;

      return (base / burst_c) * burst_c + low;
    end function;

    procedure check(condition: in boolean; message: in string) is
    begin
      if check_timing_c and not condition then
        violations := violations + 1;
        violation_s <= violations;
        report "ddr3_model: " & message
          severity error;
      end if;
    end procedure;

    -- A command that lands too early against a row's own state does
    -- not spoil one beat: the part takes it as the end of whatever was
    -- in flight, and every column of the row after it holds the
    -- payload of the one that follows.  Nothing downstream can tell
    -- that apart from a read path that is out of place, so it stops
    -- the run here rather than being counted as bad data.
    procedure check_fatal(condition: in boolean; message: in string) is
    begin
      if check_timing_c and not condition then
        violations := violations + 1;
        violation_s <= violations;
        report "ddr3_model: " & message
          severity failure;
      end if;
    end procedure;

    variable beat_at: time;
    variable value: std_ulogic_vector(7 downto 0);
  begin
    if reset_n_i = '0' then
      for b in bank'range
      loop
        bank(b).active := false;
      end loop;
      initialised := false;
      write_issued := 0;
      write_done := (others => 0);
      write_started := (others => false);
      for i in dqs_o'range
      loop
        dqs_o(i) <= nsl_io.io.tristated_z;
      end loop;
      for i in dq_o'range
      loop
        dq_o(i) <= nsl_io.io.tristated_z;
      end loop;

    elsif rising_edge(ck_i) then
      if last_edge /= 0 ps then
        tck := now - last_edge;
      end if;
      last_edge := now;

      check(cs_n_i'stable(tis_ps_c * 1 ps)
            and ras_n_i'stable(tis_ps_c * 1 ps)
            and cas_n_i'stable(tis_ps_c * 1 ps)
            and we_n_i'stable(tis_ps_c * 1 ps)
            and ba_i'stable(tis_ps_c * 1 ps)
            and a_i'stable(tis_ps_c * 1 ps),
            "command setup time violated");

      if initialised and tck /= 0 ps then
        refresh_credit := refresh_credit
          - ((now - last_refresh) / (part_c.refi_ps * 1 ps));
        if (now - last_refresh) >= (part_c.refi_ps * 1 ps) then
          last_refresh := last_refresh
            + ((now - last_refresh) / (part_c.refi_ps * 1 ps))
            * (part_c.refi_ps * 1 ps);
        end if;
        check(refresh_credit > -8,
              "refresh is more than 8 intervals late");
      end if;

      if cke_i = '1' then
        cmd := to_command_enum(config(1, 2, part_c.dq_width,
                                      part_c.bank_count_l2, a_i'length),
                               (cke => cke_i,
                                cs_n => cs_n_i,
                                ras_n => ras_n_i,
                                cas_n => cas_n_i,
                                we_n => we_n_i,
                                bank => resize(ba_i, max_bank_width_c),
                                address => resize(a_i, max_address_width_c),
                                odt => odt_i));

        ba := to_integer(ba_i);
        row := to_integer(a_i(part_c.row_count_l2 - 1 downto 0));
        col := to_integer(a_i(part_c.column_count_l2 - 1 downto 0));

        case cmd is
          when CMD_DESELECT | CMD_NOP =>
            null;

          when CMD_MODE_REGISTER_SET =>
            for b in bank'range
            loop
              check(not bank(b).active,
                    "mode register set with a bank still active");
            end loop;

            case ba is
              when 0 =>
                cl := to_integer(a_i(6 downto 4)) + 4;
                check(a_i(1 downto 0) = "00",
                      "only a fixed burst of eight is modelled");
                if a_i(8) = '1' then
                  dll_reset_at := now;
                end if;
                initialised := true;
                last_refresh := now;
                refresh_credit := 0;
              when 1 =>
                check(a_i(0) = '0', "the DLL has been disabled");
                check(a_i(4 downto 3) = "00",
                      "additive latency is not modelled");
              when 2 =>
                cwl := to_integer(a_i(5 downto 3)) + 5;
              when 3 =>
                check(a_i(2) = '0',
                      "the multi purpose register is not modelled");
              when others =>
                check(false, "mode register set to a bank above three");
            end case;

          when CMD_ZQ_CALIBRATION =>
            for b in bank'range
            loop
              check(not bank(b).active,
                    "impedance calibration with a bank still active");
            end loop;

          when CMD_ACTIVATE =>
            check(not bank(ba).active,
                  "activate on a bank that is already active");
            check(now - bank(ba).precharged_at >= part_c.rp_ps * 1 ps,
                  "tRP violated");
            check(now - bank(ba).activated_at >= part_c.rc_ps * 1 ps,
                  "tRC violated");
            check(now - last_activate >= part_c.rrd_ps * 1 ps
                  and (tck = 0 ps
                       or now - last_activate >= part_c.rrd_min_ck * tck),
                  "tRRD violated");
            check(dll_reset_at = 0 ps
                  or now - dll_reset_at >= 512 * tck,
                  "activate before the DLL had time to lock");

            bank(ba).active := true;
            bank(ba).row := row;
            bank(ba).activated_at := now;
            last_activate := now;

          when CMD_READ =>
            check(bank(ba).active, "read on a bank that is not active");
            check(now - bank(ba).activated_at >= part_c.rcd_ps * 1 ps,
                  "tRCD violated by read");
            check(a_i(10) = '0',
                  "auto precharge is not modelled");
            check(last_column = 0 ps or tck = 0 ps
                  or now - last_column >= ccd_ck_c * tck,
                  "tCCD violated by read");

            last_column := now;

            -- Strobe preamble, then eight beats with the strobe edge
            -- on the data transition, then a postamble.
            --
            -- A burst that follows the one before it by tCCD gets no
            -- preamble: the strobe simply keeps toggling, and a
            -- preamble written here would land on the last beats of
            -- that burst instead.  What releases the bus behind a
            -- burst needs no such care, because the first beat of the
            -- burst that follows falls on the very edge it releases
            -- on and is scheduled later, so it takes it back.
            if last_read = 0 ps or tck = 0 ps
              or now - last_read > ccd_ck_c * tck then
              for lane in 0 to lane_count_c - 1
              loop
                dqs_o(dqs_o'low + lane)
                  <= transport nsl_io.io.to_tristated('0', '1')
                     after (cl - 1) * tck;
              end loop;
            end if;

            last_read := now;

            for step in 0 to burst_c - 1
            loop
              beat_at := cl * tck + (step * tck) / 2;

              for lane in 0 to lane_count_c - 1
              loop
                if step mod 2 = 0 then
                  dqs_o(dqs_o'low + lane)
                    <= transport nsl_io.io.to_tristated('1', '1')
                       after beat_at;
                else
                  dqs_o(dqs_o'low + lane)
                    <= transport nsl_io.io.to_tristated('0', '1')
                       after beat_at;
                end if;

                value := fetch(ba, bank(ba).row,
                               burst_column(col, step), lane);
                for b in 0 to 7
                loop
                  dq_o(dq_o'low + lane * 8 + b)
                    <= transport nsl_io.io.to_tristated(value(b), '1')
                       after beat_at + tdqsq_ps_c * 1 ps;
                end loop;
              end loop;
            end loop;

            for lane in 0 to lane_count_c - 1
            loop
              dqs_o(dqs_o'low + lane)
                <= transport nsl_io.io.tristated_z
                   after cl * tck + (burst_c * tck) / 2 + tck / 2;
            end loop;
            for i in dq_o'range
            loop
              dq_o(i) <= transport nsl_io.io.tristated_z
                         after cl * tck + (burst_c * tck) / 2
                         + tdqsq_ps_c * 1 ps;
            end loop;

          when CMD_WRITE =>
            check(bank(ba).active, "write on a bank that is not active");
            check(now - bank(ba).activated_at >= part_c.rcd_ps * 1 ps,
                  "tRCD violated by write");
            check(a_i(10) = '0',
                  "auto precharge is not modelled");
            -- Column commands may follow each other every tCCD, which
            -- is half a burst in ticks, and the part then takes the
            -- two bursts back to back off a strobe that never stops.
            -- Anything closer would have them overlap on the wire.
            check(last_column = 0 ps or tck = 0 ps
                  or now - last_column >= ccd_ck_c * tck,
                  "tCCD violated by write");
            check_fatal(write_issued - write_oldest < write_depth_c,
                        "more write bursts are in the air than the part"
                        & " can be carrying");

            last_column := now;
            bank(ba).written_at := now;

            write_queue(write_issued mod write_depth_c)
              := (bank => ba, row => bank(ba).row, column => col);
            write_issued := write_issued + 1;

          when CMD_PRECHARGE =>
            for n in write_oldest to write_issued - 1
            loop
              check_fatal(not (a_i(10) = '1'
                               or write_queue(n mod write_depth_c).bank = ba),
                          "precharge while a write burst was still"
                          & " expecting its data");
            end loop;

            for b in bank'range
            loop
              if a_i(10) = '1' or b = ba then
                if bank(b).active then
                  check_fatal(now - bank(b).activated_at
                              >= part_c.ras_ps * 1 ps,
                              "tRAS violated by precharge");
                  -- Write recovery starts at the last beat of the
                  -- burst, which the part expects CAS write latency
                  -- after the command and which spans half the burst
                  -- length in ticks.
                  check_fatal(bank(b).written_at = 0 ps
                              or tck = 0 ps
                              or now - bank(b).written_at
                                 >= (cwl + burst_c / 2) * tck
                                    + part_c.wr_ps * 1 ps,
                              "tWR violated by precharge");
                  bank(b).active := false;
                  bank(b).precharged_at := now;
                end if;
              end if;
            end loop;

          when CMD_REFRESH =>
            for b in bank'range
            loop
              check(not bank(b).active,
                    "refresh with a bank still active");
            end loop;
            refresh_credit := refresh_credit + 1;
        end case;
      end if;

    end if;

    -- A strobe edge is not the opposite case of a clock edge, and
    -- writing this as another arm of the same choice loses half of
    -- every burst: a PHY that puts tDQSS at nothing, which is the
    -- middle of what the part allows, has every rising strobe edge
    -- land on a rising clock edge.
    if reset_n_i = '1' and dqs_i /= dqs_previous then
      -- Data rides both strobe edges and the part expects the edge in
      -- the middle of the eye.  The preamble holds the strobe low, so a
      -- burst that follows a gap starts on the first rising edge and
      -- not before; a burst that follows another has no preamble in
      -- front of it, and the rising edge that starts it is the edge
      -- after the last beat of the one before.  Looking for a rising
      -- edge with nothing under way finds both.
      for lane in 0 to lane_count_c - 1
      loop
        if dqs_i(dqs_i'low + lane) /= dqs_previous(dqs_i'low + lane)
          and write_done(lane) < write_issued then

          if not write_started(lane) then
            if dqs_i(dqs_i'low + lane) = '1' then
              write_started(lane) := true;
              write_beat(lane) := 0;
            end if;
          end if;

          if write_started(lane) then
            -- 'stable answers true for a bus whatever has just
            -- happened to it, so this asks the bus when it last
            -- moved instead.
            check(dq_i'last_event >= tds_ps_c * 1 ps,
                  "write data setup violated,"
                  & " the strobe is not centred in the eye");

            entry := write_queue(write_done(lane) mod write_depth_c);

            if dm_i(dm_i'low + lane) = '0' then
              store(entry.bank, entry.row,
                    burst_column(entry.column, write_beat(lane)), lane,
                    dq_i(dq_i'low + lane * 8 + 7 downto dq_i'low + lane * 8));
            end if;

            write_beat(lane) := write_beat(lane) + 1;
            if write_beat(lane) = burst_c then
              write_started(lane) := false;
              write_done(lane) := write_done(lane) + 1;
            end if;
          end if;
        end if;
      end loop;
    end if;

    if reset_n_i = '0' or dqs_i /= dqs_previous then
      dqs_previous := dqs_i;
    end if;
  end process;

end architecture;
