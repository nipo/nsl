library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;

entity sdram_model is
  generic(
    part_c: dram_part_t;
    check_timing_c: boolean := true;
    tac_ps_c: natural := 5400;
    toh_ps_c: natural := 2500;
    tis_ps_c: natural := 1500;
    tih_ps_c: natural := 800
    );
  port(
    clock_i: in std_ulogic;
    cke_i: in std_ulogic;
    cs_n_i: in std_ulogic;
    ras_n_i: in std_ulogic;
    cas_n_i: in std_ulogic;
    we_n_i: in std_ulogic;
    ba_i: in unsigned;
    a_i: in unsigned;
    dqm_i: in std_ulogic_vector;

    dq_i: in std_ulogic_vector;
    dq_o: out nsl_io.io.tristated_vector;

    -- Datasheet violations seen so far.  A report alone does not fail
    -- a run, and a check that cannot fail one is not a check.
    violation_count_o: out natural
    );
end entity;

architecture beh of sdram_model is

  constant bank_count_c: natural := 2 ** part_c.bank_count_l2;
  constant row_count_c: natural := 2 ** part_c.row_count_l2;
  constant column_count_c: natural := 2 ** part_c.column_count_l2;
  constant dq_byte_count_c: natural := part_c.dq_width / 8;

  -- Storage is cut in pages allocated on demand.  A page holds a whole
  -- number of columns so that a burst never straddles a boundary.
  constant page_column_l2_c: natural := 8;
  constant page_column_c: natural := 2 ** page_column_l2_c;
  constant page_byte_c: natural := page_column_c * dq_byte_count_c;
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
    read_at: time;
    written_at: time;
  end record;

  type bank_state_vector is array (natural range <>) of bank_state_t;

  -- A read in flight, one entry per clock tick of CAS latency.
  --
  -- The word a READ registered on edge n answers with is the one the
  -- controller captures on edge n + CAS latency, so the part has to
  -- have it on the pins before that edge: it puts it out on edge
  -- n + CAS latency - 1, access time after that edge, and holds it
  -- output hold time past the capturing one.  That is why access time
  -- bounds the clock period a given CAS latency can be used at, and
  -- it is what an entry reaching slot zero means here: this edge
  -- drives the word the next edge captures.
  type pending_t is
  record
    driving: boolean;
    value: byte_string(0 to 3);
    masked: boolean;
  end record;

  type pending_vector is array (natural range <>) of pending_t;

  constant max_latency_c: natural := 8;

  signal mode_burst_length_s: natural := 1;
  signal mode_interleaved_s: boolean := false;
  signal mode_cas_latency_s: natural := 3;
  signal mode_single_write_s: boolean := false;
  signal initialised_s: boolean := false;

  signal command_violation_s: natural := 0;
  signal setup_violation_s: natural := 0;
  signal hold_violation_s: natural := 0;

begin

  violation_count_o <= command_violation_s + setup_violation_s
                       + hold_violation_s;

  assert ba_i'length = part_c.bank_count_l2
    report "sdram_model: bank port is " & integer'image(ba_i'length)
    & " bits, part has " & integer'image(part_c.bank_count_l2)
    severity failure;

  assert a_i'length >= part_c.row_count_l2
    report "sdram_model: address port is too narrow for the part rows"
    severity failure;

  assert dq_i'length = part_c.dq_width
    report "sdram_model: data port width does not match the part"
    severity failure;

  assert part_c.generation = DRAM_SDR
    report "sdram_model: part is not a single data rate SDRAM"
    severity failure;

  core: process(clock_i) is
    variable pages: page_table_t(0 to page_count_c - 1);
    variable bank: bank_state_vector(0 to bank_count_c - 1)
      := (others => (active => false,
                     row => 0,
                     activated_at => 0 ps,
                     precharged_at => 0 ps,
                     read_at => 0 ps,
                     written_at => 0 ps));
    variable pending: pending_vector(0 to max_latency_c);
    -- Read masking has a latency of two clocks: a mask registered on
    -- edge m blanks the word captured on edge m + 2, which is the one
    -- driven from edge m + 1.
    variable dqm_pending: std_ulogic_vector(0 to 1) := (others => '0');

    -- Burst in progress
    variable burst_left: natural := 0;
    variable burst_read: boolean := false;
    variable burst_bank: natural := 0;
    variable burst_column: natural := 0;
    variable burst_base: natural := 0;
    variable burst_index: natural := 0;
    variable burst_autoprecharge: boolean := false;

    variable last_edge: time := 0 ps;
    variable tck: time := 0 ps;
    variable last_refresh: time := 0 ps;
    variable refresh_credit: integer := 0;
    variable last_activate: time := 0 ps;
    variable mrs_at: time := 0 ps;

    variable cmd: command_enum_t;
    variable ba: natural;
    variable row: natural;
    variable col: natural;

    -- Byte offset of a column inside the whole device
    procedure locate(bank_index, row_index, column_index: in natural;
                     page: out natural;
                     offset: out natural) is
      variable linear: natural;
    begin
      linear := (bank_index * row_count_c + row_index) * column_count_c
                + column_index;
      page := linear / page_column_c;
      offset := (linear mod page_column_c) * dq_byte_count_c;
    end procedure;

    procedure store(bank_index, row_index, column_index: in natural;
                    value: in byte_string;
                    mask: in std_ulogic_vector) is
      variable page, offset: natural;
    begin
      locate(bank_index, row_index, column_index, page, offset);

      if pages(page) = null then
        pages(page) := new byte_string(0 to page_byte_c - 1);
        pages(page).all := (others => (others => 'U'));
      end if;

      for i in 0 to dq_byte_count_c - 1
      loop
        if mask(i) = '0' then
          pages(page).all(offset + i) := value(i);
        end if;
      end loop;
    end procedure;

    procedure fetch(bank_index, row_index, column_index: in natural;
                    value: out byte_string) is
      variable page, offset: natural;
    begin
      locate(bank_index, row_index, column_index, page, offset);

      if pages(page) = null then
        value := (others => (others => 'U'));
        return;
      end if;

      value(0 to dq_byte_count_c - 1)
        := pages(page).all(offset to offset + dq_byte_count_c - 1);
    end procedure;

    -- Column visited at a given step of a burst.
    function burst_column_of(base, index, length: natural;
                             interleaved: boolean) return natural is
      variable low: natural;
    begin
      if length = 0 or length > column_count_c then
        return (base + index) mod column_count_c;
      end if;

      if interleaved then
        low := to_integer(to_unsigned(base mod length, 16)
                          xor to_unsigned(index mod length, 16));
      else
        low := (base + index) mod length;
      end if;

      return (base / length) * length + low;
    end function;

    variable violations: natural := 0;

    procedure check(condition: in boolean; message: in string) is
    begin
      if check_timing_c and not condition then
        violations := violations + 1;
        command_violation_s <= violations;
        report "sdram_model: " & message
          severity error;
      end if;
    end procedure;

    -- A precharge that arrives before the row has served its own
    -- delays does not spoil one beat: it cuts whatever the part had in
    -- flight, and the columns of the row after it hold the payload of
    -- the access that follows.  That reads downstream as a read path
    -- out of place, so it stops the run here.
    procedure check_fatal(condition: in boolean; message: in string) is
    begin
      if check_timing_c and not condition then
        violations := violations + 1;
        command_violation_s <= violations;
        report "sdram_model: " & message
          severity failure;
      end if;
    end procedure;

    variable value: byte_string(0 to 3);
    variable mask: std_ulogic_vector(0 to 3);
  begin
    if rising_edge(clock_i) then
      if last_edge /= 0 ps then
        tck := now - last_edge;
      end if;
      last_edge := now;

      -- Refresh accounting.  A part tolerates a few refreshes being
      -- pulled in or pushed back, not an unbounded drift.
      if tck /= 0 ps and initialised_s then
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

      for slot in 0 to max_latency_c - 1
      loop
        pending(slot) := pending(slot + 1);
      end loop;
      pending(max_latency_c) := (driving => false,
                                 value => (others => (others => '-')),
                                 masked => false);

      dqm_pending(0) := dqm_pending(1);
      dqm_pending(1) := '0';
      for i in dqm_i'range
      loop
        if dqm_i(i) = '1' then
          dqm_pending(1) := '1';
        end if;
      end loop;

      -- Clock suspend and self refresh are not modelled beyond
      -- freezing the part.
      if cke_i = '1' then
        cmd := to_command_enum(config(1, 1, part_c.dq_width,
                                      part_c.bank_count_l2, a_i'length),
                               (cke => cke_i,
                                cs_n => cs_n_i,
                                ras_n => ras_n_i,
                                cas_n => cas_n_i,
                                we_n => we_n_i,
                                bank => resize(ba_i, max_bank_width_c),
                                address => resize(a_i, max_address_width_c),
                                odt => '0'));

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

            case to_integer(a_i(2 downto 0)) is
              when 0 => mode_burst_length_s <= 1;
              when 1 => mode_burst_length_s <= 2;
              when 2 => mode_burst_length_s <= 4;
              when 3 => mode_burst_length_s <= 8;
              when 7 => mode_burst_length_s <= column_count_c;
              when others =>
                check(false, "reserved burst length in mode register");
            end case;


            mode_interleaved_s <= a_i(3) = '1';
            mode_cas_latency_s <= to_integer(a_i(6 downto 4));
            mode_single_write_s <= a_i(9) = '1';

            check(a_i(8 downto 7) = "00",
                  "reserved operating mode in mode register");
            check(to_integer(a_i(6 downto 4)) >= 2
                  and to_integer(a_i(6 downto 4)) <= 3,
                  "unsupported CAS latency in mode register");

            mrs_at := now;
            initialised_s <= true;
            last_refresh := now;
            refresh_credit := 0;

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
            check(mrs_at = 0 ps or now - mrs_at >= part_c.mrd_min_ck * tck,
                  "tMRD violated");

            bank(ba).active := true;
            bank(ba).row := row;
            bank(ba).activated_at := now;
            last_activate := now;

          when CMD_READ =>
            check(bank(ba).active, "read on a bank that is not active");
            check(now - bank(ba).activated_at >= part_c.rcd_ps * 1 ps,
                  "tRCD violated by read");

            burst_read := true;
            burst_bank := ba;
            burst_base := col;
            burst_index := 0;
            burst_left := mode_burst_length_s;
            burst_autoprecharge := a_i(10) = '1';
            bank(ba).read_at := now;

          when CMD_WRITE =>
            check(bank(ba).active, "write on a bank that is not active");
            check(now - bank(ba).activated_at >= part_c.rcd_ps * 1 ps,
                  "tRCD violated by write");

            burst_read := false;
            burst_bank := ba;
            burst_base := col;
            burst_index := 0;
            if mode_single_write_s then
              burst_left := 1;
            else
              burst_left := mode_burst_length_s;
            end if;
            burst_autoprecharge := a_i(10) = '1';

          when CMD_PRECHARGE =>
            check_fatal(burst_left = 0 or burst_read
                        or not (a_i(10) = '1' or burst_bank = ba),
                        "precharge cutting a write burst short");

            for b in bank'range
            loop
              if a_i(10) = '1' or b = ba then
                if bank(b).active then
                  check_fatal(now - bank(b).activated_at
                              >= part_c.ras_ps * 1 ps,
                              "tRAS violated by precharge");
                  -- Write recovery runs from the last data word the
                  -- part took, which is the beat the burst ended on.
                  check_fatal(bank(b).written_at = 0 ps
                              or (now - bank(b).written_at
                                  >= part_c.wr_ps * 1 ps
                                  and (tck = 0 ps
                                       or now - bank(b).written_at
                                          >= part_c.wr_min_ck * tck)),
                              "tWR violated by precharge");
                  bank(b).active := false;
                  bank(b).precharged_at := now;
                end if;
              end if;
            end loop;
            burst_left := 0;

          when CMD_REFRESH =>
            for b in bank'range
            loop
              check(not bank(b).active,
                    "refresh with a bank still active");
            end loop;
            check(now - last_refresh >= part_c.rfc_ps * 1 ps
                  or refresh_credit < 8,
                  "more than 8 refreshes pulled in");
            refresh_credit := refresh_credit + 1;

          when CMD_ZQ_CALIBRATION =>
            check(false, "single data rate part has no ZQ calibration");
        end case;

        -- A burst beat happens on the very cycle its command lands,
        -- and a new command truncates whatever was running, so this
        -- comes after the command has been acted on.
        if burst_left /= 0 then
          if burst_read then
            fetch(burst_bank, bank(burst_bank).row,
                  burst_column_of(burst_base, burst_index,
                                  mode_burst_length_s, mode_interleaved_s),
                  value);
            pending(mode_cas_latency_s - 1) := (driving => true,
                                                value => value,
                                                masked => false);
          else
            mask := (others => '1');
            for i in 0 to dq_byte_count_c - 1
            loop
              mask(i) := dqm_i(dqm_i'low + i);
              value(i) := dq_i(dq_i'low + i * 8 + 7 downto dq_i'low + i * 8);
            end loop;
            store(burst_bank, bank(burst_bank).row,
                  burst_column_of(burst_base, burst_index,
                                  mode_burst_length_s, mode_interleaved_s),
                  value, mask);
            bank(burst_bank).written_at := now;
          end if;

          burst_index := burst_index + 1;
          burst_left := burst_left - 1;

          if burst_left = 0 and burst_autoprecharge then
            check(now - bank(burst_bank).activated_at
                  >= part_c.ras_ps * 1 ps,
                  "tRAS violated by auto precharge");
            bank(burst_bank).active := false;
            if burst_read then
              bank(burst_bank).precharged_at := now;
            else
              bank(burst_bank).precharged_at := now + part_c.wr_ps * 1 ps;
            end if;
          end if;
        end if;
      end if;
    end if;

    -- Output is driven from the head of the latency pipeline, with the
    -- part's own access time, and goes invalid shortly after the edge
    -- so that a PHY sampling in the wrong place sees it.
    if rising_edge(clock_i) then
      if pending(0).driving and dqm_pending(0) = '0' then
        for i in 0 to dq_byte_count_c - 1
        loop
          for b in 0 to 7
          loop
            dq_o(dq_o'low + i * 8 + b)
              <= nsl_io.io.to_tristated('X', '1') after toh_ps_c * 1 ps,
                 nsl_io.io.to_tristated(pending(0).value(i)(b), '1')
                 after tac_ps_c * 1 ps;
          end loop;
        end loop;
      else
        for i in dq_o'range
        loop
          dq_o(i) <= nsl_io.io.tristated_z after toh_ps_c * 1 ps;
        end loop;
      end if;
    end if;
  end process;

  has_checks: if check_timing_c
  generate
    setup: process(clock_i) is
      variable violations: natural := 0;
    begin
      if rising_edge(clock_i) then
        if not (cs_n_i'stable(tis_ps_c * 1 ps)
                and ras_n_i'stable(tis_ps_c * 1 ps)
                and cas_n_i'stable(tis_ps_c * 1 ps)
                and we_n_i'stable(tis_ps_c * 1 ps)
                and cke_i'stable(tis_ps_c * 1 ps)
                and ba_i'stable(tis_ps_c * 1 ps)
                and a_i'stable(tis_ps_c * 1 ps)) then
          violations := violations + 1;
          setup_violation_s <= violations;
          report "sdram_model: command setup time violated"
            severity error;
        end if;
      end if;
    end process;

    hold: process is
      variable violations: natural := 0;
    begin
      wait until rising_edge(clock_i);
      wait for tih_ps_c * 1 ps;

      if not (cs_n_i'stable(tih_ps_c * 1 ps)
              and ras_n_i'stable(tih_ps_c * 1 ps)
              and cas_n_i'stable(tih_ps_c * 1 ps)
              and we_n_i'stable(tih_ps_c * 1 ps)
              and cke_i'stable(tih_ps_c * 1 ps)
              and ba_i'stable(tih_ps_c * 1 ps)
              and a_i'stable(tih_ps_c * 1 ps)) then
        violations := violations + 1;
        hold_violation_s <= violations;
        report "sdram_model: command hold time violated"
          severity error;
      end if;
    end process;
  end generate;

end architecture;
