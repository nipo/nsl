library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;

-- Drives a single data rate SDRAM model through a full bring-up and a
-- set of accesses, checking data comes back and that the model does
-- not complain about the command stream.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: dram_part_t := w9825g6kh_c;
  constant tck_ps_c: natural := 10000;
  constant tck_c: time := tck_ps_c * 1 ps;
  constant t_c: dram_timing_t := timings(part_c, tck_ps_c);

  constant burst_length_c: natural := 8;
  constant dq_byte_c: natural := part_c.dq_width / 8;

  signal clock_s: std_ulogic := '0';
  signal done_s: boolean := false;

  signal cke_s: std_ulogic := '0';
  signal cs_n_s: std_ulogic := '1';
  signal ras_n_s: std_ulogic := '1';
  signal cas_n_s: std_ulogic := '1';
  signal we_n_s: std_ulogic := '1';
  signal ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0) := (others => '0');
  signal a_s: unsigned(part_c.row_count_l2 - 1 downto 0) := (others => '0');
  signal dqm_s: std_ulogic_vector(dq_byte_c - 1 downto 0) := (others => '0');

  signal dq_drive_s: std_ulogic_vector(part_c.dq_width - 1 downto 0)
    := (others => '0');
  signal dq_enable_s: std_ulogic := '0';
  signal dq_wire_s: std_logic_vector(part_c.dq_width - 1 downto 0);
  signal dq_model_i_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);
  signal dq_model_o_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);

  -- Word written at a given location, so a read can be checked without
  -- keeping a copy of the memory.
  function expected(bank, row, column: natural) return std_ulogic_vector
  is
    variable seed: natural;
  begin
    seed := (bank * 1103 + row * 12289 + column * 7919) mod 65536;
    return std_ulogic_vector(to_unsigned(seed, part_c.dq_width));
  end function;

  -- Datasheet constraints the model saw broken.  They are
  -- reported as they happen; the run has to fail on them too.
  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after tck_c / 2 when not done_s else '0';

  dq_from_model: for i in dq_wire_s'range
  generate
    dq_wire_s(i) <= nsl_io.io.to_logic(dq_model_o_s(i));
  end generate;

  dq_wire_s <= std_logic_vector(dq_drive_s) when dq_enable_s = '1'
               else (others => 'Z');
  dq_model_i_s <= std_ulogic_vector(to_x01(dq_wire_s));

  dut: nsl_ext_ram.simulation.sdram_model
    generic map(
      part_c => part_c
      )
    port map(
      clock_i => clock_s,
      cke_i => cke_s,
      cs_n_i => cs_n_s,
      ras_n_i => ras_n_s,
      cas_n_i => cas_n_s,
      we_n_i => we_n_s,
      ba_i => ba_s,
      a_i => a_s,
      dqm_i => dqm_s,
      dq_i => dq_model_i_s,
      dq_o => dq_model_o_s,
      violation_count_o => violation_count_s
      );

  stim: process is
    -- A mismatch reported alone does not fail a run, so they are
    -- counted and the count is asserted on at the end.
    variable errors: natural := 0;

    procedure tick(count: natural := 1) is
    begin
      for i in 1 to count
      loop
        wait until falling_edge(clock_s);
      end loop;
    end procedure;

    procedure nop is
    begin
      cs_n_s <= '0';
      ras_n_s <= '1';
      cas_n_s <= '1';
      we_n_s <= '1';
      tick;
    end procedure;

    procedure deselect(count: natural := 1) is
    begin
      cs_n_s <= '1';
      ras_n_s <= '1';
      cas_n_s <= '1';
      we_n_s <= '1';
      tick(count);
    end procedure;

    procedure precharge_all is
    begin
      cs_n_s <= '0';
      ras_n_s <= '0';
      cas_n_s <= '1';
      we_n_s <= '0';
      a_s <= (others => '0');
      a_s(10) <= '1';
      tick;
      deselect(t_c.rp);
    end procedure;

    procedure refresh is
    begin
      cs_n_s <= '0';
      ras_n_s <= '0';
      cas_n_s <= '0';
      we_n_s <= '1';
      tick;
      deselect(t_c.rfc);
    end procedure;

    procedure mode_register_set is
      variable value: unsigned(part_c.row_count_l2 - 1 downto 0);
    begin
      value := (others => '0');
      -- Burst length 8, sequential order
      value(2 downto 0) := "011";
      value(3) := '0';
      value(6 downto 4) := to_unsigned(t_c.cl, 3);
      value(9) := '0';

      cs_n_s <= '0';
      ras_n_s <= '0';
      cas_n_s <= '0';
      we_n_s <= '0';
      ba_s <= (others => '0');
      a_s <= value;
      tick;
      deselect(t_c.mrd);
    end procedure;

    procedure activate(bank, row: natural) is
    begin
      cs_n_s <= '0';
      ras_n_s <= '0';
      cas_n_s <= '1';
      we_n_s <= '1';
      ba_s <= to_unsigned(bank, ba_s'length);
      a_s <= to_unsigned(row, a_s'length);
      tick;
      deselect(t_c.rcd);
    end procedure;

    procedure precharge(bank: natural) is
    begin
      cs_n_s <= '0';
      ras_n_s <= '0';
      cas_n_s <= '1';
      we_n_s <= '0';
      ba_s <= to_unsigned(bank, ba_s'length);
      a_s <= (others => '0');
      tick;
      deselect(t_c.rp);
    end procedure;

    procedure write_burst(bank, row, column: natural;
                          autoprecharge: boolean := false;
                          mask_first: boolean := false) is
    begin
      cs_n_s <= '0';
      ras_n_s <= '1';
      cas_n_s <= '0';
      we_n_s <= '0';
      ba_s <= to_unsigned(bank, ba_s'length);
      a_s <= (others => '0');
      a_s(part_c.column_count_l2 - 1 downto 0)
        <= to_unsigned(column, part_c.column_count_l2);
      if autoprecharge then
        a_s(10) <= '1';
      end if;

      dq_enable_s <= '1';
      dq_drive_s <= expected(bank, row, column);
      if mask_first then
        dqm_s <= (others => '1');
      else
        dqm_s <= (others => '0');
      end if;
      tick;

      cs_n_s <= '1';
      for beat in 1 to burst_length_c - 1
      loop
        dq_drive_s <= expected(bank, row, column + beat);
        dqm_s <= (others => '0');
        tick;
      end loop;

      dq_enable_s <= '0';
      dqm_s <= (others => '0');
    end procedure;

    procedure read_burst(bank, row, column: natural;
                         autoprecharge: boolean := false;
                         unwritten_beats: natural := 0) is
      variable want: std_ulogic_vector(part_c.dq_width - 1 downto 0);
    begin
      cs_n_s <= '0';
      ras_n_s <= '1';
      cas_n_s <= '0';
      we_n_s <= '1';
      ba_s <= to_unsigned(bank, ba_s'length);
      a_s <= (others => '0');
      a_s(part_c.column_count_l2 - 1 downto 0)
        <= to_unsigned(column, part_c.column_count_l2);
      if autoprecharge then
        a_s(10) <= '1';
      end if;
      tick;
      cs_n_s <= '1';

      -- The part puts the first word out one edge short of the CAS
      -- latency and holds it past the next one, so it is stable on
      -- the edge that is CAS latency ticks past the command.
      for beat in 0 to t_c.cl - 2
      loop
        tick;
      end loop;

      for beat in 0 to burst_length_c - 1
      loop
        wait until rising_edge(clock_s);
        want := expected(bank, row, column + beat);
        if beat < unwritten_beats then
          if not is_x(dq_wire_s) then
            errors := errors + 1;
            report "masked write should have left memory unwritten"
              severity error;
          end if;
        else
          if std_ulogic_vector(to_x01(dq_wire_s)) /= want then
            errors := errors + 1;
            report "read mismatch at bank " & integer'image(bank)
              & " row " & integer'image(row)
              & " column " & integer'image(column + beat)
              severity error;
          end if;
        end if;
      end loop;

      tick;
    end procedure;

  begin
    report "tCK " & integer'image(tck_ps_c) & " ps, CL " & integer'image(t_c.cl)
      & ", tRCD " & integer'image(t_c.rcd)
      & ", tRP " & integer'image(t_c.rp)
      & ", tRAS " & integer'image(t_c.ras)
      & ", tRC " & integer'image(t_c.rc)
      & ", tRFC " & integer'image(t_c.rfc);

    -- Power up: clock enable low, then the part's stabilisation wait.
    cke_s <= '0';
    deselect(10);
    cke_s <= '1';
    deselect(t_c.init_cke);

    precharge_all;
    refresh;
    refresh;
    mode_register_set;

    -- A location that was never written reads as undefined.
    activate(1, 100);
    read_burst(1, 100, 0, unwritten_beats => burst_length_c);
    precharge(1);

    -- Plain write then read back, same row.
    activate(0, 42);
    write_burst(0, 42, 16);
    deselect(t_c.wr);
    read_burst(0, 42, 16);
    precharge(0);

    -- Another bank, checking bank state is kept apart.
    activate(2, 7);
    write_burst(2, 7, 256);
    deselect(t_c.wr);
    read_burst(2, 7, 256);
    precharge(2);

    -- Auto precharge closes the row for us.
    activate(3, 511);
    write_burst(3, 511, 64, autoprecharge => true);
    deselect(t_c.wr + t_c.rp);
    activate(3, 511);
    read_burst(3, 511, 64, autoprecharge => true);
    deselect(t_c.rp);

    -- Data written under a mask must not reach the array.
    activate(1, 100);
    write_burst(1, 100, 32, mask_first => true);
    deselect(t_c.wr);
    read_burst(1, 100, 32, unwritten_beats => 1);
    precharge(1);

    -- Earlier writes survive the traffic that followed.
    activate(0, 42);
    read_burst(0, 42, 16);
    precharge(0);

    refresh;
    refresh;

    report "sdram model test done, " & integer'image(errors) & " mismatches";

    assert errors = 0
      report "sdram model bench found " & integer'image(errors)
      & " mismatches"
      severity failure;

    assert violation_count_s = 0
      report integer'image(violation_count_s)
      & " datasheet constraints were broken on the part's pins"
      severity failure;

    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
