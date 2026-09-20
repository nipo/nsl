library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.dram.all;
use nsl_ext_ram.sdram.all;

-- Runs a single data rate SDRAM controller against the model of the
-- part it is configured for.  The model checks the command stream it
-- receives, so a pass means both that data survives a round trip and
-- that the controller respects the part's timings.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: dram_part_t := w9825g6kh_c;
  constant tck_ps_c: natural := 10000;
  constant tck_c: time := tck_ps_c * 1 ps;
  constant burst_length_l2_c: natural := 3;

  constant beat_byte_c: natural := cycle_byte_count(part_c);
  constant burst_beat_c: natural := 2 ** burst_length_l2_c;
  constant access_byte_c: natural := burst_beat_c * beat_byte_c;

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;

  signal cmd_s: cmd_t := cmd_idle;
  signal cmd_ack_s: cmd_ack_t;
  signal wdata_s: wdata_t := wdata_idle;
  signal wdata_ack_s: wdata_ack_t;
  signal rdata_s: rdata_t;
  signal rdata_ack_s: rdata_ack_t := accept(true);
  signal ready_s: std_ulogic;

  signal ram_clock_s: std_ulogic;
  signal ram_cke_s: std_ulogic;
  signal ram_cs_n_s: std_ulogic;
  signal ram_ras_n_s: std_ulogic;
  signal ram_cas_n_s: std_ulogic;
  signal ram_we_n_s: std_ulogic;
  signal ram_ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0);
  signal ram_a_s: unsigned(address_width(part_c) - 1 downto 0);
  signal ram_dqm_s: std_ulogic_vector(beat_byte_c - 1 downto 0);
  signal ram_dq_ctrl_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal ram_dq_model_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal ram_dq_wire_s: std_logic_vector(part_c.dq_width - 1 downto 0);
  signal ram_dq_value_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  -- Payload of one access, derived from its address so a read can be
  -- checked without keeping a copy of what was written.
  function payload(address: natural; beat: natural) return byte_string
  is
    variable ret: byte_string(0 to beat_byte_c - 1);
    variable seed: natural;
  begin
    for i in ret'range
    loop
      seed := (address / access_byte_c * 2654 + beat * 131 + i * 17 + 11)
              mod 256;
      ret(i) := std_ulogic_vector(to_unsigned(seed, 8));
    end loop;

    return ret;
  end function;

  -- Datasheet constraints the model saw broken.  They are
  -- reported as they happen; the run has to fail on them too.
  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after tck_c / 2 when not done_s else '0';
  reset_n_s <= '1' after 3 * tck_c;

  dq_wiring: for i in ram_dq_wire_s'range
  generate
    ram_dq_wire_s(i) <= nsl_io.io.to_logic(ram_dq_ctrl_s(i));
    ram_dq_wire_s(i) <= nsl_io.io.to_logic(ram_dq_model_s(i));
  end generate;
  ram_dq_value_s <= std_ulogic_vector(to_x01(ram_dq_wire_s));

  dut: nsl_ext_ram.sdram.sdram_controller
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      burst_length_l2_c => burst_length_l2_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,
      wdata_i => wdata_s,
      wdata_o => wdata_ack_s,
      rdata_o => rdata_s,
      rdata_i => rdata_ack_s,

      ready_o => ready_s,

      ram_clock_o => ram_clock_s,
      ram_cke_o => ram_cke_s,
      ram_cs_n_o => ram_cs_n_s,
      ram_ras_n_o => ram_ras_n_s,
      ram_cas_n_o => ram_cas_n_s,
      ram_we_n_o => ram_we_n_s,
      ram_ba_o => ram_ba_s,
      ram_a_o => ram_a_s,
      ram_dqm_o => ram_dqm_s,
      ram_dq_o => ram_dq_ctrl_s,
      ram_dq_i => ram_dq_value_s
      );

  model: nsl_ext_ram.simulation.sdram_model
    generic map(
      part_c => part_c
      )
    port map(
      clock_i => ram_clock_s,
      cke_i => ram_cke_s,
      cs_n_i => ram_cs_n_s,
      ras_n_i => ram_ras_n_s,
      cas_n_i => ram_cas_n_s,
      we_n_i => ram_we_n_s,
      ba_i => ram_ba_s,
      a_i => ram_a_s,
      dqm_i => ram_dqm_s,
      dq_i => ram_dq_value_s,
      dq_o => ram_dq_model_s,
      violation_count_o => violation_count_s
      );

  stim: process is
    -- A mismatch reported alone does not fail a run, so they are
    -- counted and the count is asserted on at the end.
    variable errors: natural := 0;

    procedure access_start(address: natural; write: boolean) is
    begin
      wait until falling_edge(clock_s);
      cmd_s <= cmd_request(to_unsigned(address, max_byte_address_width_c),
                           write);
      loop
        wait until rising_edge(clock_s);
        exit when cmd_ack_s.ready = '1';
      end loop;
      wait until falling_edge(clock_s);
      cmd_s <= cmd_idle;
    end procedure;

    procedure write_access(address: natural) is
    begin
      access_start(address, true);

      for beat in 0 to burst_beat_c - 1
      loop
        wait until falling_edge(clock_s);
        wdata_s <= wdata_beat(payload(address, beat));
        loop
          wait until rising_edge(clock_s);
          exit when wdata_ack_s.ready = '1';
        end loop;
        wait until falling_edge(clock_s);
        wdata_s <= wdata_idle;
      end loop;
    end procedure;

    procedure read_access(address: natural) is
      variable want: byte_string(0 to beat_byte_c - 1);
    begin
      access_start(address, false);

      for beat in 0 to burst_beat_c - 1
      loop
        loop
          wait until rising_edge(clock_s);
          exit when rdata_s.valid = '1';
        end loop;

        want := payload(address, beat);
        if rdata_s.data(0 to beat_byte_c - 1) /= want then
          errors := errors + 1;
          report "read mismatch at address " & integer'image(address)
            & " beat " & integer'image(beat)
            & " got " & to_string(rdata_s.data(0 to beat_byte_c - 1))
            & " want " & to_string(want)
            severity error;
        end if;
      end loop;
    end procedure;

    -- Addresses picked to land in different banks and rows, and to
    -- revisit a row already open.
    type address_vector is array (natural range <>) of natural;
    constant probe_c: address_vector := (
      16#000000#,
      16#000010#,
      16#000020#,
      16#010000#,
      16#020000#,
      16#008000#,
      16#000030#,
      16#123450#
      );

  begin
    wait until ready_s = '1';
    report "controller ready at " & time'image(now);

    for i in probe_c'range
    loop
      write_access(probe_c(i));
    end loop;

    for i in probe_c'range
    loop
      read_access(probe_c(i));
    end loop;

    -- Read again in a different order, so rows have to be reopened.
    for i in probe_c'reverse_range
    loop
      read_access(probe_c(i));
    end loop;

    -- Overwrite one location and check the new value sticks.
    write_access(16#010000#);
    read_access(16#010000#);

    -- Stay idle for longer than the model tolerates without a
    -- refresh, so the controller has to keep the array alive on its
    -- own, then check nothing was lost.
    wait for 200 us;
    read_access(16#000000#);
    read_access(16#123450#);

    report "sdram controller test done, " & integer'image(errors)
      & " mismatches";

    assert errors = 0
      report "sdram controller bench found " & integer'image(errors)
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
