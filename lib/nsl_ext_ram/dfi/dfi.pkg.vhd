library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data;
use nsl_data.bytestream.all;

-- Interface between a DRAM controller and its PHY, after the shape of
-- the JEDEC DFI specification.
--
-- A controller cycle carries phase_count command slots and
-- phase_count * edge_count data slots.  Slot 0 is the earliest on the
-- wire.  Everything a PHY does with those slots -- serialisation,
-- delay, tristate, strobe generation -- stays behind this boundary, so
-- one controller drives an SDR SDRAM PHY (one phase, one edge) and a
-- DDR3 PHY (four phases, two edges) unchanged.
--
-- Records hold worst-case sized arrays and configuration tells how
-- much of them is meaningful.  Slots beyond the configuration are
-- driven to don't-care and ignored on read.
--
-- Latency belongs to the PHY.  A controller presents write data on the
-- same cycle as the write command and the PHY puts it on the wire CAS
-- write latency later; a PHY raises rddata_valid when read data has
-- come back, rather than the controller counting the delay.  A part
-- whose latency is not a whole number of controller cycles is then a
-- matter for the PHY alone.
package dfi is

  constant max_phase_count_c: natural := 8;
  constant max_edge_count_c: natural := 2;
  constant max_slot_count_c: natural := max_phase_count_c * max_edge_count_c;
  constant max_dq_byte_count_c: natural := 4;
  constant max_bank_width_c: natural := 3;
  constant max_address_width_c: natural := 18;

  type config_t is
  record
    -- Command slots per controller cycle
    phase_count: natural range 1 to max_phase_count_c;
    -- Data slots per command slot: 1 for a single data rate part, 2
    -- for a double data rate one
    edge_count: natural range 1 to max_edge_count_c;
    -- Width of the whole data bus, all devices ganged
    dq_byte_count: natural range 1 to max_dq_byte_count_c;
    bank_width: natural range 1 to max_bank_width_c;
    address_width: natural range 1 to max_address_width_c;
    has_odt: boolean;
    has_reset: boolean;
  end record;

  function config(phase_count: natural;
                  edge_count: natural;
                  dq_width: natural; -- bits
                  bank_width: natural;
                  address_width: natural;
                  odt: boolean := false;
                  reset: boolean := false) return config_t;

  -- Data slots carried by one controller cycle
  function slot_count(cfg: config_t) return natural;
  -- Bytes carried by one controller cycle
  function cycle_byte_count(cfg: config_t) return natural;

  type command_enum_t is (
    -- Chip select deasserted
    CMD_DESELECT,
    CMD_NOP,
    CMD_ACTIVATE,
    CMD_READ,
    CMD_WRITE,
    CMD_PRECHARGE,
    CMD_REFRESH,
    CMD_MODE_REGISTER_SET,
    CMD_ZQ_CALIBRATION
    );

  -- One command slot, as the pins carry it.
  type command_t is
  record
    cke: std_ulogic;
    cs_n: std_ulogic;
    ras_n: std_ulogic;
    cas_n: std_ulogic;
    we_n: std_ulogic;
    bank: unsigned(max_bank_width_c - 1 downto 0);
    address: unsigned(max_address_width_c - 1 downto 0);
    odt: std_ulogic;
  end record;

  type command_vector is array (natural range <>) of command_t;

  -- One data slot.  A set mask bit inhibits the write of its byte.
  type data_t is
  record
    value: byte_string(0 to max_dq_byte_count_c - 1);
    mask: std_ulogic_vector(0 to max_dq_byte_count_c - 1);
  end record;

  type data_vector is array (natural range <>) of data_t;

  -- Controller to PHY.
  type master_t is
  record
    command: command_vector(0 to max_phase_count_c - 1);
    wrdata: data_vector(0 to max_slot_count_c - 1);
    -- Per phase, whether the PHY drives the data bus
    wrdata_en: std_ulogic_vector(0 to max_phase_count_c - 1);
    -- Per phase, whether the PHY should expect read data back
    rddata_en: std_ulogic_vector(0 to max_phase_count_c - 1);
    -- Memory reset pin, active low, driven straight through
    reset_n: std_ulogic;
  end record;

  -- PHY to controller.
  type slave_t is
  record
    rddata: data_vector(0 to max_slot_count_c - 1);
    -- Asserted on the cycle rddata holds the answer to a read
    rddata_valid: std_ulogic;
    -- PHY has finished whatever bring-up it needs for itself
    init_complete: std_ulogic;
  end record;

  -- Idle values, no command, no data, memory held in reset.
  function master_reset(cfg: config_t) return master_t;
  -- No command, memory out of reset.
  function master_idle(cfg: config_t) return master_t;
  function slave_defaults(cfg: config_t) return slave_t;

  function command_defaults(cfg: config_t) return command_t;

  -- Builds a command slot.  Address and bank are ignored for commands
  -- that carry none.
  function command(cfg: config_t;
                   kind: command_enum_t;
                   bank: unsigned := "000";
                   address: unsigned := "0";
                   cke: std_ulogic := '1';
                   odt: std_ulogic := '0') return command_t;

  -- Decodes a command slot back, for a PHY or a memory model to act
  -- on.  A slot the encoding does not cover decodes as CMD_NOP.
  function to_command_enum(cfg: config_t; cmd: command_t) return command_enum_t;

  function bank(cfg: config_t; cmd: command_t) return unsigned;
  function address(cfg: config_t; cmd: command_t) return unsigned;

  -- Builds a data slot from a byte string shorter than the maximum.
  function data(cfg: config_t;
                value: byte_string;
                mask: std_ulogic_vector := "") return data_t;
  function value(cfg: config_t; dat: data_t) return byte_string;
  function mask(cfg: config_t; dat: data_t) return std_ulogic_vector;

  -- Flattens the data slots of one controller cycle, slot 0 first.
  function value(cfg: config_t; dat: data_vector) return byte_string;
  function mask(cfg: config_t; dat: data_vector) return std_ulogic_vector;
  -- Spreads a controller cycle worth of bytes over the data slots.
  function to_data_vector(cfg: config_t;
                          value: byte_string;
                          mask: std_ulogic_vector := "") return data_vector;

end package dfi;

package body dfi is

  function config(phase_count: natural;
                  edge_count: natural;
                  dq_width: natural;
                  bank_width: natural;
                  address_width: natural;
                  odt: boolean := false;
                  reset: boolean := false) return config_t
  is
    variable ret: config_t;
  begin
    assert phase_count >= 1 and phase_count <= max_phase_count_c
      report "dfi: unsupported phase count"
      severity failure;

    assert edge_count >= 1 and edge_count <= max_edge_count_c
      report "dfi: unsupported edge count"
      severity failure;

    assert dq_width mod 8 = 0
      report "dfi: data bus width must be a whole number of bytes"
      severity failure;

    assert dq_width / 8 >= 1 and dq_width / 8 <= max_dq_byte_count_c
      report "dfi: unsupported data bus width"
      severity failure;

    ret.phase_count := phase_count;
    ret.edge_count := edge_count;
    ret.dq_byte_count := dq_width / 8;
    ret.bank_width := bank_width;
    ret.address_width := address_width;
    ret.has_odt := odt;
    ret.has_reset := reset;

    return ret;
  end function;

  function slot_count(cfg: config_t) return natural
  is
  begin
    return cfg.phase_count * cfg.edge_count;
  end function;

  function cycle_byte_count(cfg: config_t) return natural
  is
  begin
    return slot_count(cfg) * cfg.dq_byte_count;
  end function;

  function command_defaults(cfg: config_t) return command_t
  is
    variable ret: command_t;
  begin
    ret.cke := '1';
    ret.cs_n := '1';
    ret.ras_n := '-';
    ret.cas_n := '-';
    ret.we_n := '-';
    ret.bank := (others => '-');
    ret.address := (others => '-');
    if cfg.has_odt then
      ret.odt := '0';
    else
      ret.odt := '-';
    end if;

    return ret;
  end function;

  function command(cfg: config_t;
                   kind: command_enum_t;
                   bank: unsigned := "000";
                   address: unsigned := "0";
                   cke: std_ulogic := '1';
                   odt: std_ulogic := '0') return command_t
  is
    variable ret: command_t := command_defaults(cfg);
  begin
    ret.cke := cke;
    if cfg.has_odt then
      ret.odt := odt;
    end if;

    case kind is
      when CMD_DESELECT =>
        ret.cs_n := '1';
        return ret;

      when CMD_NOP =>
        ret.cs_n := '0';
        ret.ras_n := '1';
        ret.cas_n := '1';
        ret.we_n := '1';
        return ret;

      when CMD_ACTIVATE =>
        ret.cs_n := '0';
        ret.ras_n := '0';
        ret.cas_n := '1';
        ret.we_n := '1';

      when CMD_READ =>
        ret.cs_n := '0';
        ret.ras_n := '1';
        ret.cas_n := '0';
        ret.we_n := '1';

      when CMD_WRITE =>
        ret.cs_n := '0';
        ret.ras_n := '1';
        ret.cas_n := '0';
        ret.we_n := '0';

      when CMD_PRECHARGE =>
        ret.cs_n := '0';
        ret.ras_n := '0';
        ret.cas_n := '1';
        ret.we_n := '0';

      when CMD_REFRESH =>
        ret.cs_n := '0';
        ret.ras_n := '0';
        ret.cas_n := '0';
        ret.we_n := '1';
        return ret;

      when CMD_MODE_REGISTER_SET =>
        ret.cs_n := '0';
        ret.ras_n := '0';
        ret.cas_n := '0';
        ret.we_n := '0';

      when CMD_ZQ_CALIBRATION =>
        ret.cs_n := '0';
        ret.ras_n := '1';
        ret.cas_n := '1';
        ret.we_n := '0';
    end case;

    ret.bank(cfg.bank_width - 1 downto 0)
      := resize(bank, cfg.bank_width);
    ret.address(cfg.address_width - 1 downto 0)
      := resize(address, cfg.address_width);

    return ret;
  end function;

  function to_command_enum(cfg: config_t; cmd: command_t) return command_enum_t
  is
    variable code: std_ulogic_vector(2 downto 0);
  begin
    if cmd.cs_n /= '0' then
      return CMD_DESELECT;
    end if;

    code := cmd.ras_n & cmd.cas_n & cmd.we_n;

    case code is
      when "111" => return CMD_NOP;
      when "011" => return CMD_ACTIVATE;
      when "101" => return CMD_READ;
      when "100" => return CMD_WRITE;
      when "010" => return CMD_PRECHARGE;
      when "001" => return CMD_REFRESH;
      when "000" => return CMD_MODE_REGISTER_SET;
      when "110" => return CMD_ZQ_CALIBRATION;
      when others => return CMD_NOP;
    end case;
  end function;

  function bank(cfg: config_t; cmd: command_t) return unsigned
  is
  begin
    return cmd.bank(cfg.bank_width - 1 downto 0);
  end function;

  function address(cfg: config_t; cmd: command_t) return unsigned
  is
  begin
    return cmd.address(cfg.address_width - 1 downto 0);
  end function;

  function data(cfg: config_t;
                value: byte_string;
                mask: std_ulogic_vector := "") return data_t
  is
    alias value_v: byte_string(0 to value'length - 1) is value;
    alias mask_v: std_ulogic_vector(0 to mask'length - 1) is mask;
    variable ret: data_t;
  begin
    assert value'length = cfg.dq_byte_count
      report "dfi: data slot width mismatch"
      severity failure;

    ret.value := (others => dontcare_byte_c);
    ret.value(0 to cfg.dq_byte_count - 1) := value_v;

    ret.mask := (others => '-');
    if mask'length = 0 then
      ret.mask(0 to cfg.dq_byte_count - 1) := (0 to cfg.dq_byte_count - 1 => '0');
    else
      assert mask'length = cfg.dq_byte_count
        report "dfi: data slot mask width mismatch"
        severity failure;
      ret.mask(0 to cfg.dq_byte_count - 1) := mask_v;
    end if;

    return ret;
  end function;

  function value(cfg: config_t; dat: data_t) return byte_string
  is
  begin
    return dat.value(0 to cfg.dq_byte_count - 1);
  end function;

  function mask(cfg: config_t; dat: data_t) return std_ulogic_vector
  is
  begin
    return dat.mask(0 to cfg.dq_byte_count - 1);
  end function;

  function value(cfg: config_t; dat: data_vector) return byte_string
  is
    alias dat_v: data_vector(0 to dat'length - 1) is dat;
    variable ret: byte_string(0 to cycle_byte_count(cfg) - 1);
  begin
    for slot in 0 to slot_count(cfg) - 1
    loop
      ret(slot * cfg.dq_byte_count to (slot + 1) * cfg.dq_byte_count - 1)
        := value(cfg, dat_v(slot));
    end loop;

    return ret;
  end function;

  function mask(cfg: config_t; dat: data_vector) return std_ulogic_vector
  is
    alias dat_v: data_vector(0 to dat'length - 1) is dat;
    variable ret: std_ulogic_vector(0 to cycle_byte_count(cfg) - 1);
  begin
    for slot in 0 to slot_count(cfg) - 1
    loop
      ret(slot * cfg.dq_byte_count to (slot + 1) * cfg.dq_byte_count - 1)
        := mask(cfg, dat_v(slot));
    end loop;

    return ret;
  end function;

  function to_data_vector(cfg: config_t;
                          value: byte_string;
                          mask: std_ulogic_vector := "") return data_vector
  is
    alias value_v: byte_string(0 to value'length - 1) is value;
    alias mask_v: std_ulogic_vector(0 to mask'length - 1) is mask;
    constant stride_c: natural := cfg.dq_byte_count;
    variable ret: data_vector(0 to max_slot_count_c - 1);
  begin
    assert value'length = cycle_byte_count(cfg)
      report "dfi: cycle data width mismatch"
      severity failure;

    ret := (others => (value => (others => dontcare_byte_c),
                       mask => (others => '-')));

    for slot in 0 to slot_count(cfg) - 1
    loop
      if mask'length = 0 then
        ret(slot) := data(cfg, value_v(slot * stride_c to (slot + 1) * stride_c - 1));
      else
        assert mask'length = cycle_byte_count(cfg)
          report "dfi: cycle mask width mismatch"
          severity failure;
        ret(slot) := data(cfg,
                          value_v(slot * stride_c to (slot + 1) * stride_c - 1),
                          mask_v(slot * stride_c to (slot + 1) * stride_c - 1));
      end if;
    end loop;

    return ret;
  end function;

  function master_idle(cfg: config_t) return master_t
  is
    variable ret: master_t;
  begin
    ret.command := (others => command_defaults(cfg));
    ret.wrdata := (others => (value => (others => dontcare_byte_c),
                              mask => (others => '-')));
    ret.wrdata_en := (others => '0');
    ret.rddata_en := (others => '0');
    ret.reset_n := '1';

    return ret;
  end function;

  function master_reset(cfg: config_t) return master_t
  is
    variable ret: master_t := master_idle(cfg);
  begin
    ret.command := (others => command(cfg, CMD_DESELECT, cke => '0'));
    ret.reset_n := '0';

    return ret;
  end function;

  function slave_defaults(cfg: config_t) return slave_t
  is
    variable ret: slave_t;
  begin
    ret.rddata := (others => (value => (others => dontcare_byte_c),
                              mask => (others => '-')));
    ret.rddata_valid := '0';
    ret.init_complete := '0';

    return ret;
  end function;

end package body dfi;
