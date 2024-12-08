library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data, nsl_amba;
use nsl_amba.address.all;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

-- This package defines APB configuration, signals and accessor
-- functions.  Signals are defined as records where all members are of
-- fixed width of the worst-case size.  Accessor functions will ensure
-- meaningless signals are never set to other value than "-" (dont
-- care) and all reads ignore signals that are not used by
-- configuration.  Any useful synthesis tools should propagate
-- constants and ignore useless parts.
package apb is
  
  -- Internal
  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');
  constant na_u: unsigned(1 to 0) := (others => '-');

  subtype version_t is integer range 2 to 5;
  
  -- By spec
  constant max_address_width_c: natural := 32;
  constant max_data_byte_count_l2_c : natural := 2;
  -- Recommanded is 128, modify it if needed
  constant max_user_width_c: natural := 64;

  subtype addr_t is nsl_amba.address.address_t;
  subtype user_t is std_ulogic_vector(max_user_width_c - 1 downto 0);
  subtype strb_t is std_ulogic_vector(0 to 2**max_data_byte_count_l2_c - 1);
  subtype data_t is byte_string(0 to 2**max_data_byte_count_l2_c-1);
  subtype prot_t is std_ulogic_vector(3 - 1 downto 0);
  subtype nse_t is std_ulogic_vector(1 - 1 downto 0);

  -- APB Configuration. This can be spawned by config() function below.
  type config_t is
  record
    address_width: natural range 1 to max_address_width_c;
    data_bus_width_l2: natural range 0 to max_data_byte_count_l2_c;
    auser_width: natural range 0 to max_user_width_c;
    wuser_width: natural range 0 to max_user_width_c;
    ruser_width: natural range 0 to max_user_width_c;
    buser_width: natural range 0 to max_user_width_c;
    has_prot: boolean;
    has_rme: boolean;
    has_strb: boolean;
    has_ready: boolean;
    has_err: boolean;
    has_wakeup: boolean;
  end record;

  type address_space_t is (
    ADDRESS_SPACE_SECURE,
    ADDRESS_SPACE_NON_SECURE,
    ADDRESS_SPACE_ROOT,
    ADDRESS_SPACE_REALM
    );
  
  -- APB2 subset of the spec One could call apb5_config and get the
  -- same subset.  This function just ensure not to enable excluded
  -- options.
  function apb2_config(address_width: natural; -- 1 .. 32
                       data_bus_width: natural -- bits, either 8, 16 or 32
                       ) return config_t;

  -- APB3 subset of the spec One could call apb5_config and get the
  -- same subset.  This function just ensure not to enable excluded
  -- options.
  function apb3_config(address_width: natural; -- 1 .. 32
                       data_bus_width: natural; -- bits, either 8, 16 or 32
                       ready: boolean := true;
                       err: boolean := false) return config_t;

  -- APB4 subset of the spec One could call apb5_config and get the
  -- same subset.  This function just ensure not to enable excluded
  -- options.
  function apb4_config(address_width: natural; -- 1 .. 32
                       data_bus_width: natural; -- bits, either 8, 16 or 32
                       prot: boolean := false;
                       strb: boolean := false;
                       ready: boolean := true;
                       err: boolean := false) return config_t;

  -- Generates a configuration suitable for any revision of the spec,
  -- as long as excluded features are not enabled.
  function config(address_width: natural; -- 1 .. 32
                  data_bus_width: natural; -- bits, either 8, 16 or 32
                  auser_width: natural := 0;
                  buser_width: natural := 0;
                  wuser_width: natural := 0;
                  ruser_width: natural := 0;
                  prot: boolean := false;
                  rme: boolean := false;
                  strb: boolean := false;
                  ready: boolean := true;
                  err: boolean := false;
                  wakeup: boolean := false) return config_t;

  function version(cfg: config_t) return version_t;

  -- Signal data types.

  -- Master-driven meta-record. Can typically be used as port.
  type master_t is
  record
    addr: addr_t;
    prot: prot_t;
    nse: nse_t;
    sel: std_ulogic;
    enable: std_ulogic;
    write: std_ulogic;
    wdata: data_t;
    strb: strb_t;
    auser: user_t;
    wuser: user_t;
  end record;

  -- Slave-driven meta-record. Can typically be used as port.
  type slave_t is
  record
    ready: std_ulogic;
    rdata: data_t;
    slverr: std_ulogic;
    wakeup: std_ulogic;
    ruser: user_t;
    buser: user_t;
  end record;

  -- Bus meta-record, typically used for a signal.
  type bus_t is
  record
    m: master_t;
    s: slave_t;
  end record;

  -- Vectors
  type master_vector is array (natural range <>) of master_t;
  type slave_vector is array (natural range <>) of slave_t;
  type bus_vector is array (natural range <>) of bus_t;
  type address_vector is array (natural range <>) of addr_t;

  type phase_t is(
    PHASE_SETUP,
    PHASE_ACCESS
    );

  function transfer_idle(cfg: config_t) return master_t;

  function write_transfer(cfg: config_t;
                          addr: unsigned := na_u;
                          bytes: byte_string;
                          strb: std_ulogic_vector := na_suv;
                          order: byte_order_t := BYTE_ORDER_INCREASING;
                          prot: prot_t := "000";
                          nse: std_ulogic := '0';
                          auser: std_ulogic_vector := na_suv;
                          wuser: std_ulogic_vector := na_suv;
                          phase: phase_t;
                          valid: boolean := true) return master_t;

  function write_transfer(cfg: config_t;
                          addr: unsigned := na_u;
                          value: unsigned := na_u;
                          strb: std_ulogic_vector := na_suv;
                          endian: endian_t := ENDIAN_LITTLE;
                          prot: prot_t := "000";
                          nse: std_ulogic := '0';
                          auser: std_ulogic_vector := na_suv;
                          wuser: std_ulogic_vector := na_suv;
                          phase: phase_t;
                          valid: boolean := true) return master_t;

  function read_transfer(cfg: config_t;
                         addr: unsigned := na_u;
                         prot: prot_t := "000";
                         nse: std_ulogic := '0';
                         auser: std_ulogic_vector := na_suv;
                         phase: phase_t;
                         valid: boolean := true) return master_t;

  function response_idle(cfg: config_t) return slave_t;

  function write_response(cfg: config_t;
                          error: boolean := false;
                          wakeup: boolean := false;
                          buser: std_ulogic_vector := na_suv;
                          ready: boolean := true) return slave_t;

  function read_response(cfg: config_t;
                         bytes: byte_string;
                         order: byte_order_t := BYTE_ORDER_INCREASING;
                         error: boolean := false;
                         wakeup: boolean := false;
                         ruser: std_ulogic_vector := na_suv;
                         ready: boolean := true) return slave_t;

  function read_response(cfg: config_t;
                         value: unsigned := na_u;
                         endian: endian_t := ENDIAN_LITTLE;
                         error: boolean := false;
                         wakeup: boolean := false;
                         ruser: std_ulogic_vector := na_suv;
                         ready: boolean := true) return slave_t;
  
  -- Retrieves beat address from the master's current
  -- state. Returned vector has the size defined in configuration.
  -- Caller may override returned LSB position.
  function address(cfg: config_t; m: master_t;
                   lsb: natural := 0) return unsigned;
  -- Retrieves address space from master.
  function address_space(cfg: config_t; m: master_t) return address_space_t;
  -- Retrieves protection mode of master.
  function prot(cfg: config_t; m: master_t) return prot_t;
  -- Retrieves realm of master.
  function nse(cfg: config_t; m: master_t) return nse_t;
  -- Retrieves auser data of master. Returned value has length defined
  -- in configuration.
  function auser(cfg: config_t; m: master_t) return std_ulogic_vector;
  -- Retrieve wuser data of master. Returned value has length defined
  -- in configuration.
  function wuser(cfg: config_t; m: master_t) return std_ulogic_vector;
  -- Tells whether peripheral is selected
  function is_selected(cfg: config_t; m: master_t) return boolean;
  -- Tells whether we are in setup cycle (selected but no transfer active)
  function is_setup(cfg: config_t; m: master_t) return boolean;
  -- Tells whether we are in access cycle (selected and enabled)
  function is_access(cfg: config_t; m: master_t) return boolean;
  -- Tells whether we are in a write transfer
  function is_write(cfg: config_t; m: master_t) return boolean;
  -- Tells whether we are in a read transfer
  function is_read(cfg: config_t; m: master_t) return boolean;
  -- Retrieves phase from master
  function phase(cfg: config_t; m: master_t) return phase_t;
  -- Retrieves wdata bytes of master interface in selected order
  function bytes(cfg: config_t; m: master_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;
  -- Retrieves strb mask of master interface in selected order
  function strb(cfg: config_t; m: master_t;
                order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  -- Retrieves wdata as integer value of master interface in selected order
  function value(cfg: config_t; m: master_t;
                 endian: endian_t := ENDIAN_LITTLE) return unsigned;

  -- Tells whether response is valid.
  function is_ready(cfg: config_t; s: slave_t) return boolean;
  -- Tells whether response is an error.
  function is_error(cfg: config_t; s: slave_t) return boolean;
  -- Retrieves rdata bytes of slave interface in selected order
  function bytes(cfg: config_t; s: slave_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;
  -- Retrieves rdata as integer value of slave interface in selected order
  function value(cfg: config_t; s: slave_t;
                 endian: endian_t := ENDIAN_LITTLE) return unsigned;
  -- Retrieves buser data of slave. Returned value has length defined
  -- in configuration.
  function buser(cfg: config_t; s: slave_t) return std_ulogic_vector;
  -- Retrieve ruser data of slave. Returned value has length defined
  -- in configuration.
  function ruser(cfg: config_t; s: slave_t) return std_ulogic_vector;

  -- Probes wakeup signal
  function is_wakeup(cfg: config_t; s: slave_t) return boolean;

  -- Pretty printers for bus records, useful for debugging test-benches
  function to_string(cfg: config_t) return string;
  function to_string(cfg: config_t; m: master_t) return string;
  function to_string(cfg: config_t; s: slave_t; hide_data: boolean := false) return string;
  
  -- APB transaction dumper.
  component apb_dumper is
    generic(
      config_c : config_t;
      prefix_c : string := "APB"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      bus_i : in bus_t
      );
  end component;

  -- APB slave abstraction. It hides all the handshake to the
  -- bus.
  component apb_slave is
    generic (
      config_c: config_t
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';

      apb_i: in master_t;
      apb_o: out slave_t;

      -- Address of either write or read.
      address_o : out unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);

      -- Write data value
      w_data_o : out byte_string(0 to 2**config_c.data_bus_width_l2-1);
      -- Write data mask
      w_mask_o : out std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
      -- Write data acceptance from user (or signaling or error)
      w_ready_i : in std_ulogic := '1';
      -- Write error response (SLVERR)
      w_error_i : in std_ulogic := '0';
      -- Asserted when write beat happens
      w_valid_o : out std_ulogic;

      -- Read data value
      r_data_i : in byte_string(0 to 2**config_c.data_bus_width_l2-1);
      -- Read is required
      r_ready_o : out std_ulogic;
      -- Read got served
      r_valid_i : in std_ulogic := '1'
      );
  end component;

  -- APB register map helper. It hides all details of APB and only
  -- exposes a bunch of register designated by indexes. The whole
  -- register map has one endianness on the bus. Only writes of a full
  -- data bus width are permitted. Shorter writes will signal a
  -- SLVERR.
  component apb_regmap is
    generic (
      config_c: config_t;
      -- Default to 4kB block of 32-bit registers, which is defaults
      -- for typical CMSIS register block. Note final memory block
      -- byte size also depends on the bus width.
      reg_count_l2_c : natural := 10;
      endianness_c: endian_t := ENDIAN_LITTLE
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';

      apb_i: in master_t;
      apb_o: out slave_t;

      -- Register number, i.e. aligned address divided by bus width.
      -- This output is stable during all the read/write cycle.
      -- - During write, reg_no_o is stable at least during the
      --   w_strobe_o assertion cycle.
      -- - During read, reg_no_o is stable at least during the
      --   r_strobe_o assertion cycle and the one after.
      reg_no_o : out integer range 0 to 2**reg_count_l2_c-1;
      -- Value, with all bits meaningful and no mask, extracted from the bus
      -- using the relevant endianness
      w_value_o : out unsigned(8*(2**config_c.data_bus_width_l2)-1 downto 0);
      -- Strobe is asserted when data on bus is significant.
      w_strobe_o : out std_ulogic;
      -- Value, with all bits meaningful and no mask, will be
      -- serialized to the bus using the relevant endianness
      r_value_i : in unsigned(8*(2**config_c.data_bus_width_l2)-1 downto 0);
      -- r_value_i must be asserted on the interface the cycle
      -- r_strobe_o is asserted.
      r_strobe_o : out std_ulogic
      );
  end component;


  -- Test bench helpers
  
  -- Simulation helper function to issue a write transaction to an
  -- APB.
  procedure apb_write(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant addr: unsigned;
                      constant val: unsigned;
                      constant strb: std_ulogic_vector := "";
                      constant endian: endian_t := ENDIAN_LITTLE;
                      err: out boolean);

  -- Simulation helper function to issue a read transaction to an
  -- APB.
  procedure apb_read(constant cfg: config_t;
                     signal clock: in std_ulogic;
                     signal apb_i: in slave_t;
                     signal apb_o: out master_t;
                     constant addr: unsigned;
                     val: out unsigned;
                     err: out boolean;
                     constant endian: endian_t := ENDIAN_LITTLE);

  -- Simulation helper function to issue a read transaction to an APB
  -- and check return value matches (will use std_match to check
  -- return value). Checks response before value, if response is an
  -- expected error, value is meaningless.
  procedure apb_check(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant addr: unsigned;
                      constant val: unsigned := na_u;
                      constant err: boolean := false;
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant sev: severity_level := failure);

  -- Same as previous using integer (register) addresses
  procedure apb_write(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      constant val: unsigned;
                      constant strb: std_ulogic_vector := "";
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant err: boolean := false;
                      constant sev: severity_level := failure);

  procedure apb_read(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      val: out unsigned;
                      err: out boolean;
                      constant endian: endian_t := ENDIAN_LITTLE);

  procedure apb_check(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal apb_i: in slave_t;
                       signal apb_o: out master_t;
                       constant reg: integer;
                       constant reg_lsb: integer := 0;
                       constant val: unsigned := na_u;
                       constant err: boolean := false;
                       constant endian: endian_t := ENDIAN_LITTLE;
                       constant sev: severity_level := failure);

end package;

package body apb is

  function apb2_config(address_width: natural;
                       data_bus_width: natural) return config_t
  is
  begin
    return apb3_config(address_width => address_width,
                       data_bus_width => data_bus_width,
                       ready => false,
                       err => false);
  end function;

  function apb3_config(address_width: natural;
                       data_bus_width: natural;
                       ready: boolean := true;
                       err: boolean := false) return config_t
  is
  begin
    return apb4_config(address_width => address_width,
                       data_bus_width => data_bus_width,
                       ready => ready,
                       err => err,
                       strb => false,
                       prot => false);
  end function;

  function apb4_config(address_width: natural;
                       data_bus_width: natural;
                       prot: boolean := false;
                       strb: boolean := false;
                       ready: boolean := true;
                       err: boolean := false) return config_t
  is
  begin
    return config(address_width => address_width,
                  data_bus_width => data_bus_width,
                  ready => ready,
                  err => err,
                  strb => strb,
                  prot => prot,
                  rme => false,
                  wakeup => false);
  end function;

  function config(address_width: natural;
                  data_bus_width: natural;
                  auser_width: natural := 0;
                  buser_width: natural := 0;
                  wuser_width: natural := 0;
                  ruser_width: natural := 0;
                  prot: boolean := false;
                  rme: boolean := false;
                  strb: boolean := false;
                  ready: boolean := true;
                  err: boolean := false;
                  wakeup: boolean := false) return config_t
  is
  begin
    return config_t'(
      address_width => address_width,
      data_bus_width_l2 => nsl_math.arith.log2(data_bus_width / 8),
      auser_width => auser_width,
      buser_width => buser_width,
      ruser_width => ruser_width,
      wuser_width => wuser_width,
      has_prot => prot,
      has_rme => rme,
      has_strb => strb,
      has_ready => ready,
      has_err => err,
      has_wakeup => wakeup);
  end function;

  function version(cfg: config_t) return version_t
  is
  begin
    if cfg.auser_width /= 0
      or cfg.buser_width /= 0
      or cfg.ruser_width /= 0
      or cfg.wuser_width /= 0
      or cfg.has_wakeup
      or cfg.has_rme then
      return 5;
    end if;

    if cfg.has_prot
      or cfg.has_strb then
      return 4;
    end if;

    if cfg.has_ready
      or cfg.has_err then
      return 3;
    end if;

    return 2;
  end function;

  function address(cfg: config_t; m: master_t;
                   lsb: natural := 0) return unsigned
  is
  begin
    return m.addr(cfg.address_width-1 downto lsb);
  end function;

  function address_space(cfg: config_t; m: master_t) return address_space_t
  is
    constant p: prot_t := prot(cfg, m);
    constant np: std_ulogic_vector(1 downto 0) := nse(cfg, m) & p(1);
  begin
    case np is
      when "00" => return ADDRESS_SPACE_SECURE;
      when "01" => return ADDRESS_SPACE_NON_SECURE;
      when "10" => return ADDRESS_SPACE_ROOT;
      when others => return ADDRESS_SPACE_REALM;
    end case;
  end function;

  function prot(cfg: config_t; m: master_t) return prot_t
  is
  begin
    if cfg.has_prot then
      return m.prot;
    end if;

    return "000";
  end function;

  function nse(cfg: config_t; m: master_t) return nse_t
  is
  begin
    if cfg.has_rme then
      return m.nse;
    end if;

    return "0";
  end function;

  function auser(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return m.auser(cfg.auser_width-1 downto 0);
  end function;

  function wuser(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return m.wuser(cfg.wuser_width-1 downto 0);
  end function;

  function is_selected(cfg: config_t; m: master_t) return boolean
  is
  begin
    return m.sel = '1';
  end function;

  function is_setup(cfg: config_t; m: master_t) return boolean
  is
  begin
    return m.sel = '1' and m.enable = '0';
  end function;

  function is_access(cfg: config_t; m: master_t) return boolean
  is
  begin
    return m.sel = '1' and m.enable = '1';
  end function;

  function is_write(cfg: config_t; m: master_t) return boolean
  is
  begin
    return m.write = '1';
  end function;

  function is_read(cfg: config_t; m: master_t) return boolean
  is
  begin
    return m.write = '0';
  end function;

  function phase(cfg: config_t; m: master_t) return phase_t
  is
  begin
    if m.enable = '1' then
      return PHASE_ACCESS;
    else
      return PHASE_SETUP;
    end if;
  end function;

  function bytes(cfg: config_t; m: master_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
  begin
    return reorder(m.wdata(0 to 2**cfg.data_bus_width_l2-1), order);
  end function;

  function strb(cfg: config_t; m: master_t;
                order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
    constant k1: std_ulogic_vector(0 to 2**cfg.data_bus_width_l2-1) := (others => '1');
  begin
    if cfg.has_strb then
      return reorder_mask(m.strb(0 to 2**cfg.data_bus_width_l2-1), order);
    else
      return k1;
    end if;
  end function;

  function value(cfg: config_t; m: master_t;
                 endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
  begin
    return from_endian(bytes(cfg, m), endian);
  end function;

  function is_ready(cfg: config_t; s: slave_t) return boolean
  is
  begin
    if cfg.has_ready then
      return s.ready = '1';
    end if;

    return true;
  end function;

  function is_error(cfg: config_t; s: slave_t) return boolean
  is
  begin
    if cfg.has_err then
      return s.slverr = '1';
    end if;

    return false;
  end function;

  function bytes(cfg: config_t; s: slave_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
  begin
    return reorder(s.rdata(0 to 2**cfg.data_bus_width_l2-1), order);
  end function;

  function value(cfg: config_t; s: slave_t;
                 endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
  begin
    return from_endian(bytes(cfg, s), endian);
  end function;

  function buser(cfg: config_t; s: slave_t) return std_ulogic_vector
  is
  begin
    return s.buser(cfg.buser_width-1 downto 0);
  end function;

  function ruser(cfg: config_t; s: slave_t) return std_ulogic_vector
  is
  begin
    return s.ruser(cfg.ruser_width-1 downto 0);
  end function;

  function is_wakeup(cfg: config_t; s: slave_t) return boolean
  is
  begin
    if cfg.has_wakeup then
      return s.wakeup = '1';
    end if;
    return false;
  end function;

  function to_string(cfg: config_t) return string
  is
  begin
    return "<APB"&to_string(version(cfg))
      &" A"&to_string(cfg.address_width)
      &" D"&to_string(8 * 2**cfg.data_bus_width_l2)
      &if_else(cfg.auser_width>0, " A"&to_string(cfg.auser_width), "")
      &if_else(cfg.buser_width>0, " B"&to_string(cfg.buser_width), "")
      &if_else(cfg.ruser_width>0, " R"&to_string(cfg.ruser_width), "")
      &if_else(cfg.wuser_width>0, " W"&to_string(cfg.wuser_width), "")
      &" "
      &if_else(cfg.has_prot, "P", "")
      &if_else(cfg.has_rme, "R", "")
      &if_else(cfg.has_strb, "S", "")
      &if_else(cfg.has_ready, "R", "")
      &if_else(cfg.has_err, "E", "")
      &if_else(cfg.has_wakeup, "W", "")
      &">";
  end function;

  function to_string(cfg: config_t; m: master_t) return string
  is
  begin
    if is_selected(cfg, m) then
      return "<APB "
        &if_else(m.enable = '1', "access", "setup ")
        &" @"&to_string(address(cfg, m))
        &if_else(is_write(cfg, m),
                 " W "&to_string(bytes(cfg, m), mask => strb(cfg, m), masked_out_value => "=="),
                 " R")
        &if_else(cfg.has_prot, " P:"&to_string(prot(cfg, m)), "")
        &if_else(cfg.has_rme, " N:"&to_string(nse(cfg, m)), "")
        &if_else(cfg.auser_width>0, " Au:"&to_string(auser(cfg, m)), "")
        &if_else(cfg.wuser_width>0, " wu:"&to_string(wuser(cfg, m)), "")
        &">";
    else
      return "<APB idle>";
    end if;
  end function;

  function to_string(cfg: config_t; s: slave_t; hide_data: boolean := false) return string
  is
  begin
    if is_ready(cfg, s) then
      return "<APB rsp"
        &if_else(hide_data, "", " "&to_string(bytes(cfg, s)))
        &if_else(is_error(cfg, s), " Error", " OK")
        &if_else(cfg.ruser_width>0, " Ru:"&to_string(ruser(cfg, s)), "")
        &if_else(cfg.buser_width>0, " Bu:"&to_string(buser(cfg, s)), "")
        &if_else(is_wakeup(cfg, s), " Wakeup", "")
        &">";
    else
      return "<APB rsp idle"
        &if_else(is_wakeup(cfg, s), " Wakeup", "")
        &">";
    end if;
  end function;

  function transfer_idle(cfg: config_t) return master_t
  is
    variable ret: master_t;
  begin
    ret.addr := (others => '-');
    ret.prot := "---";
    ret.nse := "-";
    ret.sel := '0';
    ret.enable := '-';
    ret.write := '-';
    ret.wdata := (others => dontcare_byte_c);
    ret.strb := (others => '-');
    ret.auser := (others => '-');
    ret.wuser := (others => '-');

    return ret;
  end function;

  function response_idle(cfg: config_t) return slave_t
  is
    variable ret: slave_t;
  begin
    ret.rdata := (others => dontcare_byte_c);
    ret.ready := '1';
    ret.slverr := '-';
    ret.wakeup := '0';
    ret.buser := (others => '-');
    ret.ruser := (others => '-');

    return ret;
  end function;
  
  function write_transfer(cfg: config_t;
                          addr: unsigned := na_u;
                          bytes: byte_string;
                          strb: std_ulogic_vector := na_suv;
                          order: byte_order_t := BYTE_ORDER_INCREASING;
                          prot: prot_t := "000";
                          nse: std_ulogic := '0';
                          auser: std_ulogic_vector := na_suv;
                          wuser: std_ulogic_vector := na_suv;
                          phase: phase_t;
                          valid: boolean := true) return master_t
  is
    variable ret: master_t := transfer_idle(cfg);
  begin
    if cfg.address_width /= 0 and addr'length /= 0 then
      assert cfg.address_width = addr'length
        report "Bad Address vector passed"
        severity failure;
      ret.addr(addr'length-1 downto 0) := addr;
    end if;

    if cfg.has_prot and prot'length /= 0 then
      assert prot'length = prot_t'length
        report "Bad Prot vector passed"
        severity failure;
      ret.prot := prot;
    end if;

    if cfg.has_rme then
      ret.nse(0) := nse;
    end if;

    if cfg.auser_width /= 0 and auser'length /= 0 then
      assert cfg.auser_width = auser'length
        report "Bad AUSER vector passed"
        severity failure;
      ret.auser(auser'length-1 downto 0) := auser;
    end if;

    case phase is
      when PHASE_SETUP =>
        ret.enable := '0';
      when PHASE_ACCESS =>
        ret.enable := '1';
    end case;

    ret.sel := to_logic(valid);
    ret.write := '1';

    if bytes'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = bytes'length
        report "Bad data vector passed"
        severity failure;
      ret.wdata(0 to bytes'length-1) := reorder(bytes, order);
    end if;

    if strb'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = strb'length
        report "Bad strb vector passed"
        severity failure;
      ret.strb(0 to strb'length-1) := reorder_mask(strb, order);
    end if;
    
    return ret;
  end function;

  function write_transfer(cfg: config_t;
                          addr: unsigned := na_u;
                          value: unsigned := na_u;
                          strb: std_ulogic_vector := na_suv;
                          endian: endian_t := ENDIAN_LITTLE;
                          prot: prot_t := "000";
                          nse: std_ulogic := '0';
                          auser: std_ulogic_vector := na_suv;
                          wuser: std_ulogic_vector := na_suv;
                          phase: phase_t;
                          valid: boolean := true) return master_t
  is
  begin
    if endian = ENDIAN_LITTLE then
      return write_transfer(cfg => cfg,
                            addr => addr,
                            bytes => to_le(value),
                            strb => bitswap(strb),
                            order => BYTE_ORDER_INCREASING,
                            prot => prot,
                            nse => nse,
                            auser => auser,
                            wuser => wuser,
                            phase => phase,
                            valid => valid);
    else
      return write_transfer(cfg => cfg,
                            addr => addr,
                            bytes => to_be(value),
                            strb => strb,
                            order => BYTE_ORDER_INCREASING,
                            prot => prot,
                            nse => nse,
                            auser => auser,
                            wuser => wuser,
                            phase => phase,
                            valid => valid);
    end if;
  end function;

  function read_transfer(cfg: config_t;
                         addr: unsigned := na_u;
                         prot: prot_t := "000";
                         nse: std_ulogic := '0';
                         auser: std_ulogic_vector := na_suv;
                         phase: phase_t;
                         valid: boolean := true) return master_t
  is
    variable ret: master_t := transfer_idle(cfg);
  begin
    if cfg.address_width /= 0 and addr'length /= 0 then
      assert cfg.address_width = addr'length
        report "Bad Address vector passed"
        severity failure;
      ret.addr(addr'length-1 downto 0) := addr;
    end if;

    if cfg.has_prot and prot'length /= 0 then
      assert prot'length = prot_t'length
        report "Bad Prot vector passed"
        severity failure;
      ret.prot := prot;
    end if;

    if cfg.has_rme then
      ret.nse(0) := nse;
    end if;

    if cfg.auser_width /= 0 and auser'length /= 0 then
      assert cfg.auser_width = auser'length
        report "Bad AUSER vector passed"
        severity failure;
      ret.auser(auser'length-1 downto 0) := auser;
    end if;

    case phase is
      when PHASE_SETUP =>
        ret.enable := '0';
      when PHASE_ACCESS =>
        ret.enable := '1';
    end case;

    ret.sel := to_logic(valid);
    ret.write := '0';
    
    return ret;
  end function;

  function write_response(cfg: config_t;
                          error: boolean := false;
                          wakeup: boolean := false;
                          buser: std_ulogic_vector := na_suv;
                          ready: boolean := true) return slave_t
  is
    variable ret: slave_t := response_idle(cfg);
  begin
    if cfg.buser_width /= 0 and buser'length /= 0 then
      assert cfg.buser_width = buser'length
        report "Bad BUSER vector passed"
        severity failure;
      ret.buser(buser'length-1 downto 0) := buser;
    end if;

    if cfg.has_err then
      ret.slverr := to_logic(error);
    else
      assert not error
        report "Slave error will be ignored"
        severity warning;
    end if;

    if cfg.has_ready then
      ret.ready := to_logic(ready);
    else
      assert ready
        report "You cannot insert wait state with this configuration"
        severity failure;
      ret.ready := '1';
    end if;

    if cfg.has_wakeup then
      ret.wakeup := to_logic(wakeup);
    end if;

    return ret;
  end function;

  function read_response(cfg: config_t;
                         bytes: byte_string;
                         order: byte_order_t := BYTE_ORDER_INCREASING;
                         error: boolean := false;
                         wakeup: boolean := false;
                         ruser: std_ulogic_vector := na_suv;
                         ready: boolean := true) return slave_t
  is
    variable ret: slave_t := response_idle(cfg);
  begin
    if bytes'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = bytes'length
        report "Bad data vector passed"
        severity failure;
      ret.rdata(0 to bytes'length-1) := reorder(bytes, order);
    end if;

    if cfg.ruser_width /= 0 and ruser'length /= 0 then
      assert cfg.ruser_width = ruser'length
        report "Bad RUSER vector passed"
        severity failure;
      ret.ruser(ruser'length-1 downto 0) := ruser;
    end if;

    if cfg.has_err then
      ret.slverr := to_logic(error);
    else
      assert not error
        report "Slave error will be ignored"
        severity warning;
    end if;

    if cfg.has_ready then
      ret.ready := to_logic(ready);
    else
      assert ready
        report "You cannot insert wait state with this configuration"
        severity failure;
      ret.ready := '1';
    end if;

    if cfg.has_wakeup then
      ret.wakeup := to_logic(wakeup);
    end if;
    
    return ret;
  end function;

  function read_response(cfg: config_t;
                         value: unsigned := na_u;
                         endian: endian_t := ENDIAN_LITTLE;
                         error: boolean := false;
                         wakeup: boolean := false;
                         ruser: std_ulogic_vector := na_suv;
                         ready: boolean := true) return slave_t
  is
  begin
    if endian = ENDIAN_LITTLE then
      return read_response(cfg => cfg,
                           bytes => to_le(value),
                           order => BYTE_ORDER_INCREASING,
                           error => error,
                           wakeup => wakeup,
                           ruser => ruser,
                           ready => ready);
    else
      return read_response(cfg => cfg,
                           bytes => to_be(value),
                           order => BYTE_ORDER_INCREASING,
                           error => error,
                           wakeup => wakeup,
                           ruser => ruser,
                           ready => ready);
    end if;
  end function;

  procedure apb_write(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant addr: unsigned;
                      constant val: unsigned;
                      constant strb: std_ulogic_vector := "";
                      constant endian: endian_t := ENDIAN_LITTLE;
                      err: out boolean)
  is
  begin
    apb_o <= write_transfer(cfg,
                            addr => addr,
                            value => val,
                            strb => strb,
                            endian => endian,
                            phase => PHASE_SETUP,
                            valid => true);
    wait until rising_edge(clock);

    while true
    loop
      apb_o <= write_transfer(cfg,
                              addr => addr,
                              value => val,
                              strb => strb,
                              endian => endian,
                              phase => PHASE_ACCESS,
                              valid => true);

      wait until rising_edge(clock);
      if is_ready(cfg, apb_i) then
        err := is_error(cfg, apb_i);
        exit;
      end if;
    end loop;

    wait until falling_edge(clock);

    apb_o <= transfer_idle(cfg);
  end procedure;

  procedure apb_read(constant cfg: config_t;
                     signal clock: in std_ulogic;
                     signal apb_i: in slave_t;
                     signal apb_o: out master_t;
                     constant addr: unsigned;
                     val: out unsigned;
                     err: out boolean;
                     constant endian: endian_t := ENDIAN_LITTLE)
  is
  begin
    apb_o <= read_transfer(cfg,
                           addr => addr,
                           phase => PHASE_SETUP,
                           valid => true);
    wait until rising_edge(clock);

    while true
    loop
      apb_o <= read_transfer(cfg,
                             addr => addr,
                             phase => PHASE_ACCESS,
                             valid => true);

      wait until rising_edge(clock);
      if is_ready(cfg, apb_i) then
        err := is_error(cfg, apb_i);
        val := value(cfg, apb_i, endian);
        exit;
      end if;
    end loop;

    wait until falling_edge(clock);

    apb_o <= transfer_idle(cfg);
  end procedure;

  procedure apb_check(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant addr: unsigned;
                      constant val: unsigned := na_u;
                      constant err: boolean := false;
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant sev: severity_level := failure)
  is
    variable rvalue: unsigned(8 * (2**cfg.data_bus_width_l2) - 1 downto 0);
    variable rerr: boolean;
  begin
    apb_read(cfg => cfg,
             clock => clock, apb_i => apb_i, apb_o => apb_o,
             addr => addr,
             val => rvalue,
             endian => endian,
             err => rerr);

    assert err = rerr
      report "Response "&to_string(rerr)&" does not match expected value "&to_string(err)
      severity sev;

    if not err then
      assert std_match(val, rvalue)
        report "Response "&to_string(rvalue)&" does not match expected value "&to_string(val)
        severity sev;
    end if;
  end procedure;

  procedure apb_write(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      constant val: unsigned;
                      constant strb: std_ulogic_vector := "";
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant err: boolean := false;
                      constant sev: severity_level := failure)
  is
    variable rerr: boolean;
  begin
    apb_write(cfg => cfg,
              clock => clock, apb_i => apb_i, apb_o => apb_o,
              addr => to_unsigned(reg * (2 ** reg_lsb), cfg.address_width),
              val => val,
              strb => strb,
              endian => endian,
              err => rerr);

    assert err = rerr
      report "Error "&to_string(rerr)&" does not match expected value "&to_string(err)
      severity sev;
  end procedure;

  procedure apb_read(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal apb_i: in slave_t;
                      signal apb_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      val: out unsigned;
                      err: out boolean;
                      constant endian: endian_t := ENDIAN_LITTLE)
  is
  begin
    apb_read(cfg => cfg,
             clock => clock, apb_i => apb_i, apb_o => apb_o,
             addr => to_unsigned(reg * (2 ** reg_lsb), cfg.address_width),
             val => val,
             endian => endian,
             err => err);
  end procedure;

  procedure apb_check(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal apb_i: in slave_t;
                       signal apb_o: out master_t;
                       constant reg: integer;
                       constant reg_lsb: integer := 0;
                       constant val: unsigned := na_u;
                       constant err: boolean := false;
                       constant endian: endian_t := ENDIAN_LITTLE;
                       constant sev: severity_level := failure)
  is
  begin
    apb_check(cfg => cfg,
              clock => clock, apb_i => apb_i, apb_o => apb_o,
              addr => to_unsigned(reg * (2 ** reg_lsb), cfg.address_width),
              val => val,
              err => err,
              endian => endian,
              sev => sev);
  end procedure;
  
  
end package body apb;
