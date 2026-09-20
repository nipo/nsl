library ieee;
use ieee.std_logic_1164.all;

-- Datasheet timings of an external memory part, and their resolution to
-- integer tick counts.
--
-- A part is described once, in picoseconds, as it appears in its
-- datasheet.  A design picks a clock period and gets a dram_timing_t
-- holding tick counts.  All of this happens at elaboration: a
-- controller instance only ever sees integers, and counters end up
-- sized for the part actually soldered on the board.
--
-- Every count in dram_timing_t is expressed in tCK, the memory clock
-- period, whatever the number of DFI phases the controller runs.  A
-- controller whose own clock is slower than tCK converts with
-- controller_ticks() where it needs to count in its own domain.
package timing is

  type dram_generation_t is (
    DRAM_SDR,
    DRAM_DDR,
    DRAM_DDR2,
    DRAM_DDR3
    );

  -- Datasheet view of one memory device.
  --
  -- Delays are in picoseconds.  A parameter specified as "the greater
  -- of a delay and a tick count" carries both, in *_ps and *_min_ck; a
  -- parameter that has no delay form carries 0 in *_ps.  Geometry is
  -- per device, before any ganging of several devices onto a wider
  -- bus.
  type dram_part_t is
  record
    generation: dram_generation_t;

    bank_count_l2: natural;
    row_count_l2: natural;
    column_count_l2: natural;
    dq_width: natural;
    -- Data beats fetched by one column access
    prefetch_l2: natural;

    tck_min_ps: natural;
    tck_max_ps: natural;

    -- Read command to first data
    aa_ps: natural;
    -- Activate to read or write, same bank
    rcd_ps: natural;
    -- Precharge to activate, same bank
    rp_ps: natural;
    -- Activate to precharge, same bank
    ras_ps: natural;
    -- Activate to activate, same bank
    rc_ps: natural;
    -- Activate to activate, different bank
    rrd_ps: natural;
    rrd_min_ck: natural;
    -- Window holding at most four activates
    faw_ps: natural;
    -- Column access to column access
    ccd_min_ck: natural;

    -- Last write data to precharge, same bank
    wr_ps: natural;
    wr_min_ck: natural;
    -- Last write data to read
    wtr_ps: natural;
    wtr_min_ck: natural;
    -- Read to precharge, same bank
    rtp_ps: natural;
    rtp_min_ck: natural;

    -- Refresh to activate
    rfc_ps: natural;
    -- Average interval between refreshes
    refi_ps: natural;

    -- Mode register set to next command
    mrd_min_ck: natural;
    -- Mode register set to commands other than another set
    mod_ps: natural;
    mod_min_ck: natural;

    -- Reset asserted at power-up, 0 for a part with no reset pin
    init_reset_ps: natural;
    -- Clock enable asserted before the first command
    init_cke_ps: natural;
    -- Impedance calibration at init, 0 for a part with no ZQ pin
    zqinit_min_ck: natural;
  end record;

  -- Timings of a part at a given clock period, in tCK ticks.
  type dram_timing_t is
  record
    cl: natural;
    cwl: natural;
    rcd: natural;
    rp: natural;
    ras: natural;
    rc: natural;
    rrd: natural;
    faw: natural;
    ccd: natural;
    wr: natural;
    wtr: natural;
    rtp: natural;
    rfc: natural;
    refi: natural;
    mrd: natural;
    mod_update: natural;
    init_reset: natural;
    init_cke: natural;
    zqinit: natural;
    -- Reset exit to the first mode register set
    xpr: natural;
    -- Delay lock after a reset of the DLL
    dll_lock: natural;
  end record;

  -- Ticks of period_ps covering delay_ps, rounded up.
  function ticks(delay_ps, period_ps: natural) return natural;
  -- Same, never less than floor_ck.
  function ticks(delay_ps, period_ps, floor_ck: natural) return natural;

  -- Ticks of a controller clock running phase_count times slower than
  -- tCK, covering tck_count memory ticks.
  function controller_ticks(tck_count: natural;
                            phase_count: positive) return natural;

  -- Resolves a part against a clock period.  Asserts the period is one
  -- the part supports.
  function timings(part_c: dram_part_t; tck_ps: natural) return dram_timing_t;

  -- Byte count one device holds.
  function device_byte_count_l2(part_c: dram_part_t) return natural;

  -- Datasheet view of one synchronous SRAM device.
  --
  -- Delays are in picoseconds, as for a DRAM part.  Latencies are the
  -- exception: they are whole clock cycles fixed by the part's
  -- architecture, not delays to resolve against a frequency.  A
  -- pipelined part answers a read two cycles after the command at any
  -- clock rate it runs at.
  --
  -- There is no maximum clock period.  The array is static and the
  -- pipeline registers hold their state, so a part may be clocked
  -- arbitrarily slowly, or stopped.
  type sram_part_t is
  record
    address_width: natural;
    -- Byte lanes, each with its own write select
    dq_byte_count: natural;
    -- Whether each byte lane carries a parity bit alongside it
    has_parity: boolean;

    -- Command to read data
    read_latency_ck: natural;
    -- Command to write data.  Equal to the read latency on a no bus
    -- latency part, which is what lets reads and writes follow each
    -- other with no turnaround cycle.
    write_latency_ck: natural;

    tck_min_ps: natural;
    ch_ps: natural;
    cl_ps: natural;

    -- Clock rise to valid read data
    co_ps: natural;
    -- Read data held after the next clock rise
    doh_ps: natural;
    -- Clock rise to the part letting go of the bus
    chz_ps: natural;
    -- Clock rise to the part driving the bus
    clz_ps: natural;
    -- Output enable low to valid data
    eov_ps: natural;
    -- Output enable high to the part letting go of the bus
    eohz_ps: natural;
    -- Output enable low to the part driving the bus
    eolz_ps: natural;

    -- Setup before the clock rise
    as_ps: natural;
    ds_ps: natural;
    cens_ps: natural;
    wes_ps: natural;
    ces_ps: natural;

    -- Hold after the clock rise
    ah_ps: natural;
    dh_ps: natural;
    cenh_ps: natural;
    weh_ps: natural;
    ceh_ps: natural;

    -- Supply stable to the first access
    power_ps: natural;
  end record;

  -- Timings of an SRAM part at a given clock period.
  type sram_timing_t is
  record
    read_latency: natural;
    write_latency: natural;
    -- Ticks to hold off the first access after power-up
    power_up: natural;
  end record;

  -- Resolves a part against a clock period.  Asserts the period is one
  -- the part supports.
  function timings(part_c: sram_part_t; tck_ps: natural) return sram_timing_t;

  -- Byte count one device holds, parity aside.
  function device_byte_count_l2(part_c: sram_part_t) return natural;

end package timing;

package body timing is

  function ticks(delay_ps, period_ps: natural) return natural
  is
  begin
    assert period_ps /= 0
      report "timing: null clock period"
      severity failure;

    return (delay_ps + period_ps - 1) / period_ps;
  end function;

  function ticks(delay_ps, period_ps, floor_ck: natural) return natural
  is
    constant from_delay_c: natural := ticks(delay_ps, period_ps);
  begin
    if from_delay_c < floor_ck then
      return floor_ck;
    end if;

    return from_delay_c;
  end function;

  function controller_ticks(tck_count: natural;
                            phase_count: positive) return natural
  is
  begin
    return (tck_count + phase_count - 1) / phase_count;
  end function;

  -- CAS write latency is a table lookup against the clock period for
  -- DDR3, and follows CAS latency for the earlier generations.
  function cas_write_latency(part_c: dram_part_t;
                             tck_ps: natural;
                             cl: natural) return natural
  is
  begin
    case part_c.generation is
      when DRAM_SDR =>
        -- Write data travels with the command
        return 0;

      when DRAM_DDR =>
        return 1;

      when DRAM_DDR2 =>
        return cl - 1;

      when DRAM_DDR3 =>
        if tck_ps >= 2500 then
          return 5;
        elsif tck_ps >= 1875 then
          return 6;
        elsif tck_ps >= 1500 then
          return 7;
        elsif tck_ps >= 1250 then
          return 8;
        elsif tck_ps >= 1071 then
          return 9;
        else
          return 10;
        end if;
    end case;
  end function;

  function timings(part_c: dram_part_t; tck_ps: natural) return dram_timing_t
  is
    variable ret: dram_timing_t;
  begin
    assert tck_ps >= part_c.tck_min_ps
      report "timing: clock period " & integer'image(tck_ps)
      & " ps is faster than the part supports ("
      & integer'image(part_c.tck_min_ps) & " ps)"
      severity failure;

    assert tck_ps <= part_c.tck_max_ps
      report "timing: clock period " & integer'image(tck_ps)
      & " ps is slower than the part supports ("
      & integer'image(part_c.tck_max_ps) & " ps)"
      severity failure;

    ret.cl := ticks(part_c.aa_ps, tck_ps);
    ret.cwl := cas_write_latency(part_c, tck_ps, ret.cl);
    ret.rcd := ticks(part_c.rcd_ps, tck_ps);
    ret.rp := ticks(part_c.rp_ps, tck_ps);
    ret.ras := ticks(part_c.ras_ps, tck_ps);
    ret.rc := ticks(part_c.rc_ps, tck_ps);
    ret.rrd := ticks(part_c.rrd_ps, tck_ps, part_c.rrd_min_ck);
    ret.faw := ticks(part_c.faw_ps, tck_ps);
    ret.ccd := part_c.ccd_min_ck;
    ret.wr := ticks(part_c.wr_ps, tck_ps, part_c.wr_min_ck);
    ret.wtr := ticks(part_c.wtr_ps, tck_ps, part_c.wtr_min_ck);
    ret.rtp := ticks(part_c.rtp_ps, tck_ps, part_c.rtp_min_ck);
    ret.rfc := ticks(part_c.rfc_ps, tck_ps);
    -- Refresh interval is an average not to exceed, so it rounds down.
    ret.refi := part_c.refi_ps / tck_ps;
    ret.mrd := part_c.mrd_min_ck;
    ret.mod_update := ticks(part_c.mod_ps, tck_ps, part_c.mod_min_ck);
    ret.init_reset := ticks(part_c.init_reset_ps, tck_ps);
    ret.init_cke := ticks(part_c.init_cke_ps, tck_ps);
    ret.zqinit := part_c.zqinit_min_ck;

    -- Both are fixed by the DDR3 specification rather than by a part,
    -- and neither exists on the earlier generations.
    if part_c.generation = DRAM_DDR3 then
      ret.xpr := ticks(part_c.rfc_ps + 10000, tck_ps, 5);
      ret.dll_lock := 512;
    else
      ret.xpr := 0;
      ret.dll_lock := 0;
    end if;

    return ret;
  end function;

  function device_byte_count_l2(part_c: dram_part_t) return natural
  is
    variable byte_per_access_l2: natural;
  begin
    case part_c.dq_width is
      when 8 => byte_per_access_l2 := 0;
      when 16 => byte_per_access_l2 := 1;
      when 32 => byte_per_access_l2 := 2;
      when others =>
        assert false
          report "timing: unsupported device data width "
          & integer'image(part_c.dq_width)
          severity failure;
        byte_per_access_l2 := 0;
    end case;

    return part_c.bank_count_l2 + part_c.row_count_l2
      + part_c.column_count_l2 + byte_per_access_l2;
  end function;

  function timings(part_c: sram_part_t; tck_ps: natural) return sram_timing_t
  is
    variable ret: sram_timing_t;
  begin
    assert tck_ps >= part_c.tck_min_ps
      report "timing: clock period " & integer'image(tck_ps)
      & " ps is faster than the part supports ("
      & integer'image(part_c.tck_min_ps) & " ps)"
      severity failure;

    ret.read_latency := part_c.read_latency_ck;
    ret.write_latency := part_c.write_latency_ck;
    ret.power_up := ticks(part_c.power_ps, tck_ps);

    return ret;
  end function;

  function device_byte_count_l2(part_c: sram_part_t) return natural
  is
    variable dq_byte_l2: natural;
  begin
    case part_c.dq_byte_count is
      when 1 => dq_byte_l2 := 0;
      when 2 => dq_byte_l2 := 1;
      when 4 => dq_byte_l2 := 2;
      when 8 => dq_byte_l2 := 3;
      when others =>
        assert false
          report "timing: data bus must be a power of two bytes wide"
          severity failure;
        dq_byte_l2 := 0;
    end case;

    return part_c.address_width + dq_byte_l2;
  end function;

end package body timing;
