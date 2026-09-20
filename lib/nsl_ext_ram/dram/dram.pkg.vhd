library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;
use nsl_ext_ram.burst.all;

-- Generation-independent half of a DRAM controller: bank state, row
-- policy, refresh, command scheduling, and the power-up sequence.
--
-- Everything a generation brings of its own arrives as data: the part
-- description says how big the array is and how long each operation
-- takes, the DFI configuration says how many commands and how much
-- data fit in a controller cycle, and the init script says what to
-- send at power-up.  What is left is the same for SDR, DDR2 and DDR3.
--
-- The core talks to its user in controller cycles.  One cycle carries
-- cycle_byte_count(dfi_config) bytes, and one memory access carries a
-- whole burst, so a single data rate part spends several cycles per
-- access where a DDR3 part with four phases spends one.
package dram is

  -- Power-up sequence, played out before any access is served.
  constant max_script_step_count_c: natural := 16;

  type init_step_t is
  record
    command: command_enum_t;
    bank: unsigned(max_bank_width_c - 1 downto 0);
    address: unsigned(max_address_width_c - 1 downto 0);
    cke: std_ulogic;
    reset_n: std_ulogic;
    -- Controller cycles to hold before moving on
    delay: natural;
  end record;

  type init_step_vector is array (natural range <>) of init_step_t;

  type init_script_t is
  record
    step: init_step_vector(0 to max_script_step_count_c - 1);
    length: natural;
  end record;

  function init_step(command: command_enum_t;
                     delay: natural;
                     bank: unsigned := "000";
                     address: unsigned := "0";
                     cke: std_ulogic := '1';
                     reset_n: std_ulogic := '1') return init_step_t;

  -- Longest delay any step waits for, so a counter can be sized.
  function longest_delay(script: init_script_t) return natural;

  -- Power-up sequence of a single data rate part: stabilisation with
  -- the clock enabled, precharge, a couple of refreshes, then the mode
  -- register.
  function sdram_init_script(part_c: dram_part_t;
                             timing_c: dram_timing_t;
                             burst_length_l2: natural;
                             phase_count: positive := 1;
                             interleaved: boolean := false)
    return init_script_t;

  -- Power-up sequence of a DDR3 part: reset, stabilisation, the four
  -- mode registers, impedance calibration, then a clean array.
  --
  -- Delays are in controller cycles, as everywhere in a script.
  function ddr3_init_script(part_c: dram_part_t;
                            timing_c: dram_timing_t;
                            phase_count: positive;
                            -- On-die termination during writes,
                            -- as a divisor of RZQ; 0 disables it
                            rtt_nom_divisor: natural := 0)
    return init_script_t;

  -- Geometry a core derives from its part and DFI configuration.
  -- Kept as a function rather than generics so a wrapper and its core
  -- cannot disagree.
  type layout_t is
  record
    -- Data beats one access transfers
    burst_beat_count: natural;
    -- Controller cycles one access takes on the data bus
    burst_cycle_count: natural;
    -- Bytes one controller cycle carries
    cycle_byte_count: natural;
    -- Bytes one access transfers
    access_byte_count_l2: natural;
    -- Data beats one access transfers, as a power of two.  These are
    -- the low column address bits the part sequences by itself.
    burst_length_l2: natural;
    -- Position of each field in a byte address
    column_low: natural;
    column_width: natural;
    bank_low: natural;
    bank_width: natural;
    row_low: natural;
    row_width: natural;
    byte_address_width: natural;
  end record;

  function layout(part_c: dram_part_t;
                  dfi_config_c: config_t;
                  burst_length_l2: natural) return layout_t;

  function bank_of(l: layout_t; address: unsigned) return unsigned;
  function row_of(l: layout_t; address: unsigned) return unsigned;
  function column_of(l: layout_t; address: unsigned) return unsigned;

  component dram_core is
    generic(
      part_c: dram_part_t;
      timing_c: dram_timing_t;
      dfi_config_c: config_t;
      script_c: init_script_t;
      burst_length_l2_c: natural;
      -- Whether a row is left open after an access, betting the next
      -- one lands in it
      keep_row_open_c: boolean := true;
      -- Read bursts that may be announced to the PHY at once.  A PHY
      -- that arms one capture at a time takes 1 and nothing else.
      read_ahead_c: positive := 1;
      -- Whether the PHY can have two write bursts in the air together.
      -- One that lays a whole burst out from the command it belongs to
      -- cannot, and column commands are then spaced by the time the
      -- burst spends on the wire rather than by tCCD.
      write_overlap_c: boolean := false
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      cmd_i: in cmd_t;
      cmd_o: out cmd_ack_t;
      wdata_i: in wdata_t;
      wdata_o: out wdata_ack_t;
      rdata_o: out rdata_t;
      rdata_i: in rdata_ack_t;

      -- Deasserted until the power-up sequence has been played
      ready_o: out std_ulogic;

      dfi_o: out master_t;
      dfi_i: in slave_t
      );
  end component;

end package dram;

package body dram is

  function init_step(command: command_enum_t;
                     delay: natural;
                     bank: unsigned := "000";
                     address: unsigned := "0";
                     cke: std_ulogic := '1';
                     reset_n: std_ulogic := '1') return init_step_t
  is
    variable ret: init_step_t;
  begin
    ret.command := command;
    ret.bank := resize(bank, max_bank_width_c);
    ret.address := resize(address, max_address_width_c);
    ret.cke := cke;
    ret.reset_n := reset_n;
    ret.delay := delay;

    return ret;
  end function;

  function longest_delay(script: init_script_t) return natural
  is
    variable ret: natural := 0;
  begin
    for i in 0 to script.length - 1
    loop
      if script.step(i).delay > ret then
        ret := script.step(i).delay;
      end if;
    end loop;

    return ret;
  end function;

  function sdram_init_script(part_c: dram_part_t;
                             timing_c: dram_timing_t;
                             burst_length_l2: natural;
                             phase_count: positive := 1;
                             interleaved: boolean := false)
    return init_script_t
  is
    variable mode: unsigned(max_address_width_c - 1 downto 0)
      := (others => '0');
    variable all_banks: unsigned(max_address_width_c - 1 downto 0)
      := (others => '0');
    variable ret: init_script_t;
  begin
    assert part_c.generation = DRAM_SDR
      report "dram: script is for a single data rate part"
      severity failure;

    assert burst_length_l2 <= 3
      report "dram: single data rate burst length is at most 8"
      severity failure;

    assert timing_c.cl = 2 or timing_c.cl = 3
      report "dram: unsupported CAS latency for a single data rate part"
      severity failure;

    -- A10 selects all banks on a precharge
    all_banks(10) := '1';

    mode(2 downto 0) := to_unsigned(burst_length_l2, 3);
    if interleaved then
      mode(3) := '1';
    end if;
    mode(6 downto 4) := to_unsigned(timing_c.cl, 3);

    ret.step := (others => init_step(CMD_DESELECT, 0));
    ret.step(0) := init_step(CMD_DESELECT, 16, cke => '0');
    ret.step(1) := init_step(CMD_DESELECT,
                             controller_ticks(timing_c.init_cke, phase_count));
    ret.step(2) := init_step(CMD_PRECHARGE,
                             controller_ticks(timing_c.rp, phase_count),
                             address => all_banks);
    ret.step(3) := init_step(CMD_REFRESH,
                             controller_ticks(timing_c.rfc, phase_count));
    ret.step(4) := init_step(CMD_REFRESH,
                             controller_ticks(timing_c.rfc, phase_count));
    ret.step(5) := init_step(CMD_MODE_REGISTER_SET,
                             controller_ticks(timing_c.mrd, phase_count),
                             address => mode);
    ret.length := 6;

    return ret;
  end function;

  function ddr3_init_script(part_c: dram_part_t;
                            timing_c: dram_timing_t;
                            phase_count: positive;
                            rtt_nom_divisor: natural := 0)
    return init_script_t
  is
    variable mr0, mr1, mr2, mr3: unsigned(max_address_width_c - 1 downto 0)
      := (others => '0');
    variable all_banks, zq_long: unsigned(max_address_width_c - 1 downto 0)
      := (others => '0');
    variable ret: init_script_t;
    variable calibration: natural;
  begin
    assert part_c.generation = DRAM_DDR3
      report "dram: script is for a DDR3 part"
      severity failure;

    assert timing_c.cl >= 5 and timing_c.cl <= 11
      report "dram: CAS latency is outside what mode register 0 encodes"
      severity failure;

    assert timing_c.cwl >= 5 and timing_c.cwl <= 12
      report "dram: write latency is outside what mode register 2 encodes"
      severity failure;

    all_banks(10) := '1';
    zq_long(10) := '1';

    -- Burst length fixed at 8, sequential order, DLL reset.
    mr0(1 downto 0) := "00";
    mr0(3) := '0';
    mr0(6 downto 4) := to_unsigned(timing_c.cl - 4, 3);
    mr0(8) := '1';
    case timing_c.wr is
      when 5 => mr0(11 downto 9) := "001";
      when 6 => mr0(11 downto 9) := "010";
      when 7 => mr0(11 downto 9) := "011";
      when 8 => mr0(11 downto 9) := "100";
      when 9 | 10 => mr0(11 downto 9) := "101";
      when 11 | 12 => mr0(11 downto 9) := "110";
      when 13 | 14 => mr0(11 downto 9) := "111";
      when others => mr0(11 downto 9) := "000";
    end case;

    -- DLL enabled, no additive latency, drive strength RZQ/6.
    mr1(0) := '0';
    mr1(4 downto 3) := "00";
    case rtt_nom_divisor is
      when 0 => null;
      when 4 => mr1(2) := '1';
      when 2 => mr1(6) := '1';
      when 6 => mr1(6) := '1'; mr1(2) := '1';
      when 12 => mr1(9) := '1';
      when 8 => mr1(9) := '1'; mr1(2) := '1';
      when others =>
        assert false
          report "dram: mode register 1 cannot encode this termination"
          severity failure;
    end case;

    mr2(5 downto 3) := to_unsigned(timing_c.cwl - 5, 3);

    -- Multi purpose register off, predefined pattern selected.
    mr3(2) := '0';
    mr3(1 downto 0) := "00";

    if timing_c.zqinit > timing_c.dll_lock then
      calibration := timing_c.zqinit;
    else
      calibration := timing_c.dll_lock;
    end if;

    ret.step := (others => init_step(CMD_DESELECT, 0));
    ret.step(0) := init_step(CMD_DESELECT,
                             controller_ticks(timing_c.init_reset, phase_count),
                             cke => '0', reset_n => '0');
    ret.step(1) := init_step(CMD_DESELECT,
                             controller_ticks(timing_c.init_cke, phase_count),
                             cke => '0');
    ret.step(2) := init_step(CMD_DESELECT,
                             controller_ticks(timing_c.xpr, phase_count));
    ret.step(3) := init_step(CMD_MODE_REGISTER_SET,
                             controller_ticks(timing_c.mrd, phase_count),
                             bank => "010", address => mr2);
    ret.step(4) := init_step(CMD_MODE_REGISTER_SET,
                             controller_ticks(timing_c.mrd, phase_count),
                             bank => "011", address => mr3);
    ret.step(5) := init_step(CMD_MODE_REGISTER_SET,
                             controller_ticks(timing_c.mrd, phase_count),
                             bank => "001", address => mr1);
    ret.step(6) := init_step(CMD_MODE_REGISTER_SET,
                             controller_ticks(timing_c.mod_update, phase_count),
                             bank => "000", address => mr0);
    ret.step(7) := init_step(CMD_ZQ_CALIBRATION,
                             controller_ticks(calibration, phase_count),
                             address => zq_long);
    ret.step(8) := init_step(CMD_PRECHARGE,
                             controller_ticks(timing_c.rp, phase_count),
                             address => all_banks);
    ret.step(9) := init_step(CMD_REFRESH,
                             controller_ticks(timing_c.rfc, phase_count));
    ret.step(10) := init_step(CMD_REFRESH,
                              controller_ticks(timing_c.rfc, phase_count));
    ret.length := 11;

    return ret;
  end function;

  function layout(part_c: dram_part_t;
                  dfi_config_c: config_t;
                  burst_length_l2: natural) return layout_t
  is
    variable ret: layout_t;
    variable dq_byte_l2: natural;
  begin
    case dfi_config_c.dq_byte_count is
      when 1 => dq_byte_l2 := 0;
      when 2 => dq_byte_l2 := 1;
      when 4 => dq_byte_l2 := 2;
      when others =>
        assert false
          report "dram: data bus must be a power of two bytes wide"
          severity failure;
        dq_byte_l2 := 0;
    end case;

    ret.burst_beat_count := 2 ** burst_length_l2;
    ret.cycle_byte_count := cycle_byte_count(dfi_config_c);
    ret.burst_cycle_count := ret.burst_beat_count / slot_count(dfi_config_c);

    assert ret.burst_cycle_count * slot_count(dfi_config_c)
      = ret.burst_beat_count
      report "dram: burst does not fill a whole number of controller cycles"
      severity failure;

    assert ret.burst_cycle_count <= max_burst_cycle_count_c
      report "dram: burst is longer than the core supports"
      severity failure;

    assert ret.cycle_byte_count <= max_cycle_byte_count_c
      report "dram: controller cycle is wider than a burst beat"
      severity failure;

    assert burst_length_l2 <= part_c.column_count_l2
      report "dram: burst is longer than a row"
      severity failure;

    ret.access_byte_count_l2 := burst_length_l2 + dq_byte_l2;
    ret.burst_length_l2 := burst_length_l2;

    ret.column_low := ret.access_byte_count_l2;
    ret.column_width := part_c.column_count_l2 - burst_length_l2;
    ret.bank_low := ret.column_low + ret.column_width;
    ret.bank_width := part_c.bank_count_l2;
    ret.row_low := ret.bank_low + ret.bank_width;
    ret.row_width := part_c.row_count_l2;
    ret.byte_address_width := ret.row_low + ret.row_width;

    assert ret.byte_address_width <= max_byte_address_width_c
      report "dram: part is bigger than the core address space"
      severity failure;

    return ret;
  end function;

  function bank_of(l: layout_t; address: unsigned) return unsigned
  is
    alias a: unsigned(address'length - 1 downto 0) is address;
  begin
    return a(l.bank_low + l.bank_width - 1 downto l.bank_low);
  end function;

  function row_of(l: layout_t; address: unsigned) return unsigned
  is
    alias a: unsigned(address'length - 1 downto 0) is address;
  begin
    return a(l.row_low + l.row_width - 1 downto l.row_low);
  end function;

  -- The low bits of the column address are the burst order, and the
  -- part supplies them itself.
  function column_of(l: layout_t; address: unsigned) return unsigned
  is
    alias a: unsigned(address'length - 1 downto 0) is address;
  begin
    if l.burst_length_l2 = 0 then
      return a(l.column_low + l.column_width - 1 downto l.column_low);
    end if;

    return a(l.column_low + l.column_width - 1 downto l.column_low)
      & to_unsigned(0, l.burst_length_l2);
  end function;

end package body dram;
