library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data, nsl_amba;
use nsl_math.arith.all;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

-- This package defines AXI4-MM configuration, signals and accessor
-- functions.  Signals are defined as records where all members are of
-- fixed width of the worst-case size.  Accessor functions will ensure
-- meaningless signals are never set to other value than "-" (dont
-- care) and all reads ignore signals that are not used by
-- configuration.  Any useful synthesis tools should propagate
-- constants and ignore useless parts.
package axi4_mm is

  -- Internal
  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');
  constant na_u: unsigned(1 to 0) := (others => '-');

  -- Arbitrary
  constant max_address_width_c: natural := 64;
  constant max_data_bus_width_l2_l2_c: natural := 3;
  constant max_user_width_c: natural := 64;

  -- Elementary data types
  constant max_id_width_c: natural := 64;
  constant max_len_width_c: natural := 8;
  constant max_data_byte_count_l2_c : natural := 2**max_data_bus_width_l2_l2_c-1;
  
  subtype addr_t is nsl_amba.address.address_t;
  subtype user_t is std_ulogic_vector(max_user_width_c - 1 downto 0);
  subtype strobe_t is std_ulogic_vector(0 to 2**max_data_byte_count_l2_c - 1);
  subtype data_t is byte_string(0 to 2**max_data_byte_count_l2_c-1);
  subtype region_t is std_ulogic_vector(4 - 1 downto 0);
  subtype id_t is std_ulogic_vector(max_id_width_c - 1 downto 0);
  subtype len_t is unsigned(max_len_width_c - 1 downto 0);
  subtype size_t is unsigned(3 - 1 downto 0);
  subtype cache_t is std_ulogic_vector(4 - 1 downto 0);
  subtype prot_t is std_ulogic_vector(3 - 1 downto 0);
  subtype qos_t is std_ulogic_vector(4 - 1 downto 0);
  subtype lock_t is std_ulogic_vector(0 downto 0);
  subtype burst_t is std_ulogic_vector(1 downto 0);
  subtype resp_t is std_ulogic_vector(1 downto 0);
  
  type burst_enum_t is (
    BURST_FIXED,
    BURST_INCR,
    BURST_WRAP
  );

  type lock_enum_t is (
    LOCK_NORMAL,
    LOCK_EXCLUSIVE
  );

  type resp_enum_t is (
    RESP_OKAY,
    RESP_EXOKAY,
    RESP_SLVERR,
    RESP_DECERR
  );

  -- AXI4 Configuration. This can be spawned by config() function below.
  type config_t is
  record
    address_width: natural range 1 to max_address_width_c;
    -- 0 to 7 maps to 1 to 128 bytes wide
    data_bus_width_l2: natural range 0 to 2**max_data_bus_width_l2_l2_c-1;
    user_width: natural range 0 to max_user_width_c;
    id_width: natural range 0 to max_id_width_c;
    len_width: natural range 0 to max_len_width_c;
    has_size: boolean;
    has_region: boolean;
    has_qos: boolean;
    has_cache: boolean;
    has_burst: boolean;
    has_lock: boolean;
  end record;

  -- Generates a configuration.  data_bus_width should be a multiple
  -- of 8, matching a power-of-two number of bytes.  Bus will be
  -- AXI4-Lite if no burst is possible (max_length = 1), and id,
  -- region, burst, cache and lock are disabled.
  function config(address_width: natural;
                  data_bus_width: natural; -- bits
                  user_width: natural := 0;
                  id_width: natural := 0;
                  max_length: natural := 1;
                  size: boolean := false;
                  region: boolean := false;
                  qos: boolean := false;
                  cache: boolean := false;
                  burst: boolean := false;
                  lock: boolean := false) return config_t;

  function is_lite(cfg: config_t) return boolean;

  -- Signal data types.

  -- Response used for every backpressure channel (either AW, W, B,
  -- RW, R channel).
  type handshake_t is
  record
    ready: std_ulogic;
  end record;

  -- Default idle handshake
  function handshake_defaults(cfg: config_t) return handshake_t;
  -- Set whether we accept a beat on matching channel
  function accept(cfg: config_t; ready: boolean) return handshake_t;
  -- Whethet handshake is ready
  function is_ready(cfg: config_t; ack: handshake_t) return boolean;

  -- Address command record, used for AW and AR channels from master.
  type address_t is
  record
    id: id_t;
    addr: addr_t;
    len_m1: len_t;
    size_l2: size_t;
    burst: burst_t;
    lock: lock_t;
    cache: cache_t;
    prot: prot_t;
    qos: qos_t;
    region: region_t;
    user: user_t;
    valid: std_ulogic;
  end record;

  -- Default idle address channel
  function address_defaults(cfg: config_t) return address_t;

  -- Spawn an address channel beat.  If any item enabled in
  -- configuration is not passed, default value is used.
  function address(cfg: config_t;
                   id: std_ulogic_vector := na_suv;
                   addr: unsigned := na_u;
                   len_m1: unsigned := na_u;
                   size_l2: unsigned := na_u;
                   burst: burst_enum_t := BURST_INCR;
                   lock: lock_enum_t := LOCK_NORMAL;
                   cache: std_ulogic_vector := na_suv;
                   prot: std_ulogic_vector := na_suv;
                   qos: std_ulogic_vector := na_suv;
                   region: std_ulogic_vector := na_suv;
                   user: std_ulogic_vector := na_suv;
                   valid: boolean := true) return address_t;

  -- Retrieve ID from address beat
  function id(cfg: config_t; addr: address_t) return std_ulogic_vector;
  -- Retrieve address from address beat, returned value has the length
  -- defined in configuration. Caller may restrict the returned
  -- address to use fewer bits by removing LSBs.
  function address(cfg: config_t; addr: address_t;
                   lsb: natural := 0) return unsigned;
  -- Retrieve length field of the address beat
  function length_m1(cfg: config_t; addr: address_t; w: natural) return unsigned;
  -- Retrieve size field of the address beat, encoded as in spec.
  function size_l2(cfg: config_t; addr: address_t) return unsigned;
  -- Retrieve burst field of the address beat or default value
  function burst(cfg: config_t; addr: address_t) return burst_enum_t;
  -- Retrieve lock field of the address beat or default value
  function lock(cfg: config_t; addr: address_t) return lock_enum_t;
  -- Retrieve cache field of the address beat or default value
  function cache(cfg: config_t; addr: address_t) return cache_t;
  -- Retrieve prot field of the address beat, or default value
  function prot(cfg: config_t; addr: address_t) return prot_t;
  -- Retrieve QoS field of the address beat, or default value
  function qos(cfg: config_t; addr: address_t) return qos_t;
  -- Retrieve region field of the address beat, or default value
  function region(cfg: config_t; addr: address_t) return region_t;
  -- Retrieve user field of the address beat
  function user(cfg: config_t; addr: address_t) return std_ulogic_vector;
  -- Tells whether beat is asserting valid
  function is_valid(cfg: config_t; addr: address_t) return boolean;

  -- Write data channel
  type write_data_t is
  record
    data: data_t;
    strb: strobe_t;
    last: std_ulogic;
    user: user_t;
    valid: std_ulogic;
  end record;

  -- Write data channel idle
  function write_data_defaults(cfg: config_t) return write_data_t;

  -- Write data beat using bytes as data vector.
  -- bytes and strb are in ascending order (as memory should be).
  function write_data(cfg: config_t;
                      bytes: byte_string;
                      strb: std_ulogic_vector := na_suv;
                      order: byte_order_t := BYTE_ORDER_INCREASING;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_t;

  -- Write data beat using unsigned as data vector.  Uses passed
  -- endianness for value serialization as bytes.  strb is in the same
  -- order as the value (strb bit matching the MSB is on the left).
  function write_data(cfg: config_t;
                      value: unsigned := na_u;
                      strb: std_ulogic_vector := na_suv;
                      endian: endian_t := ENDIAN_LITTLE;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_t;

  -- Retrieve the bytes of the write data beat. Returned byte_string
  -- is in given order
  function bytes(cfg: config_t; write_data: write_data_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;
  -- Retrieve the mask of the write data beat. Returned vector is in
  -- given byte order
  function strb(cfg: config_t; write_data: write_data_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  -- Retrieve the binary value as if the bus was carrying a numeric
  -- value.  Parse the bus as of endian passed.
  function value(cfg: config_t; write_data: write_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned;
  -- Retrieve the mask of the write data beat (equivalent to strb
  -- expanded as a byte mask). Returned vector is in given endianness
  function mask(cfg: config_t; write_data: write_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned;
  -- Retrieve whether beat is last in burst. Last is meaningless if
  -- bus configuration has no length field. In such case, last is
  -- ignored and implied to be true by this function.
  function is_last(cfg: config_t; write_data: write_data_t) return boolean;
  -- Retrieves user part of the write data beat. Returned vector has
  -- size defined in configuration
  function user(cfg: config_t; write_data: write_data_t) return std_ulogic_vector;
  -- Tells whether beat is asserting valid
  function is_valid(cfg: config_t; write_data: write_data_t) return boolean;

  -- Write response channel
  type write_response_t is
  record
    id: id_t;
    resp: resp_t;
    user: user_t;
    valid: std_ulogic;
  end record;

  -- Write response idle
  function write_response_defaults(cfg: config_t) return write_response_t;

  -- Spawns a write response beat.
  function write_response(cfg: config_t;
                          id: std_ulogic_vector := na_suv;
                          resp: resp_enum_t := RESP_OKAY;
                          user: std_ulogic_vector := na_suv;
                          valid: boolean := true) return write_response_t;

  -- Retrieve ID from write response beat
  function id(cfg: config_t; write_response: write_response_t) return std_ulogic_vector;
  -- Retrieve response from write response beat
  function resp(cfg: config_t; write_response: write_response_t) return resp_enum_t;
  -- Retrieves user part of the write response beat. Returned vector has
  -- size defined in configuration
  function user(cfg: config_t; write_response: write_response_t) return std_ulogic_vector;
  -- Tells whether beat is asserting valid
  function is_valid(cfg: config_t; write_response: write_response_t) return boolean;

  -- Read data channel.
  type read_data_t is
  record
    id: id_t;
    data: data_t;
    resp: resp_t;
    last: std_ulogic;
    user: user_t;
    valid: std_ulogic;
  end record;

  -- Read data idle
  function read_data_defaults(cfg: config_t) return read_data_t;

  -- Spawns a write response beat.  Use byte_string to carry
  -- data, in ascending order.
  function read_data(cfg: config_t;
                     id: std_ulogic_vector := na_suv;
                     bytes: byte_string := null_byte_string;
                     order: byte_order_t := BYTE_ORDER_INCREASING;
                     resp: resp_enum_t := RESP_OKAY;
                     user: std_ulogic_vector := na_suv;
                     last: boolean := false;
                     valid: boolean := true) return read_data_t;

  -- Spawns a write response beat.  Value is passed as an unsigned
  -- value, passed endianness is used to serialize the value to bytes.
  function read_data(cfg: config_t;
                     id: std_ulogic_vector := na_suv;
                     value: unsigned := na_u;
                     endian: endian_t := ENDIAN_LITTLE;
                     resp: resp_enum_t := RESP_OKAY;
                     user: std_ulogic_vector := na_suv;
                     last: boolean := false;
                     valid: boolean := true) return read_data_t;

  -- Retrieve ID from read response beat
  function id(cfg: config_t; read_data: read_data_t) return std_ulogic_vector;
  -- Retrieve the bytes of the read response data beat. Returned
  -- byte_string is in ascending order
  function bytes(cfg: config_t; read_data: read_data_t; order: byte_order_t:= BYTE_ORDER_INCREASING) return byte_string;
  -- Retrieve the binary value as if the bus was carrying a numeric
  -- value.  Parse the bus as of endian passed.
  function value(cfg: config_t; read_data: read_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned;
  -- Retrieve response from read response beat
  function resp(cfg: config_t; read_data: read_data_t) return resp_enum_t;
  -- Retrieve whether beat is last in burst. Last is meaningless if
  -- bus configuration has no length field. In such case, last is
  -- ignored and implied to be true by this function.
  function is_last(cfg: config_t; read_data: read_data_t) return boolean;
  -- Retrieves user part of the read data beat. Returned vector has
  -- size defined in configuration
  function user(cfg: config_t; read_data: read_data_t) return std_ulogic_vector;
  -- Tells whether beat is asserting valid
  function is_valid(cfg: config_t; read_data: read_data_t) return boolean;

  -- Master-driven meta-record. Can typically be used as port.
  --@-- grouped group:bus_t
  type master_t is
  record
    aw: address_t;
    w: write_data_t;
    b: handshake_t;
    ar: address_t;
    r: handshake_t;
  end record;

  -- Slave-driven meta-record. Can typically be used as port.
  --@-- grouped group:bus_t
  type slave_t is
  record
    aw: handshake_t;
    w: handshake_t;
    b: write_response_t;
    ar: handshake_t;
    r: read_data_t;
  end record;

  -- Bus meta-record, typically used for a signal.
  type bus_t is
  record
    --@-- grouped direction:forward
    m: master_t;
    --@-- grouped direction:reverse
    s: slave_t;
  end record;

  -- Vectors
  type master_vector is array (natural range <>) of master_t;
  type slave_vector is array (natural range <>) of slave_t;
  type bus_vector is array (natural range <>) of bus_t;

  -- Convertors between semantic enums and bit encoding
  function to_burst(cfg: config_t; b: burst_t) return burst_enum_t;
  function to_logic(cfg: config_t; b: burst_enum_t) return burst_t;
  function to_lock(cfg: config_t; l: lock_t) return lock_enum_t;
  function to_logic(cfg: config_t; l: lock_enum_t) return lock_t;
  function to_resp(cfg: config_t; r: resp_t) return resp_enum_t;
  function to_logic(cfg: config_t; r: resp_enum_t) return resp_t;

  -- Transaction state record.  This is a helper typically used in a
  -- slave implementation. It tracks the burst state and gives the
  -- relevant address, following burst wrapping mode as defined in
  -- spec.
  type transaction_t is
  record
    id: id_t;
    addr, saturation, const_mask: addr_t;
    len_m1: len_t;
    size_l2: size_t;
    burst: burst_enum_t;
    lock: lock_enum_t;
    cache: cache_t;
    prot: prot_t;
    qos: qos_t;
    region: region_t;
    user: user_t;
    valid: std_ulogic;
  end record;
  -- Initialize a transaction from an address beat (either read or write).
  function transaction(cfg: config_t; addr: address_t) return transaction_t;
  -- Iterate one step over a transaction.
  function step(cfg: config_t; txn: transaction_t) return transaction_t;

  -- Retrieve current ID from the transaction. Returned vector has the
  -- size defined in configuration.
  function id(cfg: config_t; txn: transaction_t) return std_ulogic_vector;
  -- Retrieve beat address from the transaction's current
  -- state. Returned vector has the size defined in configuration.
  -- Caller may override returned LSB position.
  function address(cfg: config_t; txn: transaction_t;
                   lsb: natural := 0) return unsigned;
  -- Retrieve size (beat word size).
  function size_l2(cfg: config_t; txn: transaction_t) return unsigned;
  -- Retrieve locking scheme of transaction.
  function lock(cfg: config_t; txn: transaction_t) return lock_enum_t;
  -- Retrieve cache mode of transaction.
  function cache(cfg: config_t; txn: transaction_t) return cache_t;
  -- Retrieve protection mode of transaction.
  function prot(cfg: config_t; txn: transaction_t) return prot_t;
  -- Retrieve qos mode of transaction.
  function qos(cfg: config_t; txn: transaction_t) return qos_t;
  -- Retrieve region info of transaction.
  function region(cfg: config_t; txn: transaction_t) return region_t;
  -- Retrieve user data of transaction (from address beat). Returned
  -- value has length defined in configuration.
  function user(cfg: config_t; txn: transaction_t) return std_ulogic_vector;
  -- Tells whether the transaction is currently running
  function is_valid(cfg: config_t; txn: transaction_t) return boolean;
  -- Tells whether the beat in transaction is the last one
  function is_last(cfg: config_t; txn: transaction_t) return boolean;
  -- Retrieves count of beats left to run in current transaction.
  function length_m1(cfg: config_t; txn: transaction_t) return unsigned;

  -- Pretty printers for bus records, useful for debugging test-benches
  function to_string(b: burst_enum_t) return string;
  function to_string(l: lock_enum_t) return string;
  function to_string(r: resp_enum_t) return string;
  function to_string(cfg: config_t) return string;
  function to_string(cfg: config_t; a: address_t) return string;
  function to_string(cfg: config_t; t: transaction_t) return string;
  function to_string(cfg: config_t; w: write_data_t) return string;
  function to_string(cfg: config_t; w: write_response_t) return string;
  function to_string(cfg: config_t; r: read_data_t) return string;
  function to_string(cfg: config_t; r: handshake_t) return string;

  -- Simulation helper function to issue a write transaction to an
  -- AXI4-Lite bus.
  procedure lite_write(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant addr: unsigned;
                       constant val: unsigned;
                       constant strb: std_ulogic_vector := "";
                       constant endian: endian_t := ENDIAN_LITTLE;
                       rsp: out resp_enum_t);
  -- Simulation helper function to issue a read transaction to an
  -- AXI4-Lite bus.
  procedure lite_read(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant addr: unsigned;
                      val: out unsigned;
                      rsp: out resp_enum_t;
                      constant endian: endian_t := ENDIAN_LITTLE);
  -- Simulation helper function to issue a read transaction to an
  -- AXI4-Lite bus and check return value matches (will use std_match
  -- to check return value). Checks response before value, if response
  -- is an expected error, value is meaningless.
  procedure lite_check(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant addr: unsigned;
                      constant val: unsigned := na_u;
                      constant rsp: resp_enum_t := RESP_OKAY;
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant sev: severity_level := failure);

  -- Same as previous using integer (register) addresses
  procedure lite_write(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant reg: integer;
                       constant reg_lsb: integer := 0;
                       constant val: unsigned;
                       constant strb: std_ulogic_vector := "";
                       constant endian: endian_t := ENDIAN_LITTLE;
                       constant rsp: resp_enum_t := RESP_OKAY;
                      constant sev: severity_level := failure);
  procedure lite_read(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      val: out unsigned;
                      rsp: out resp_enum_t;
                      constant endian: endian_t := ENDIAN_LITTLE);
  procedure lite_check(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      constant val: unsigned := na_u;
                      constant rsp: resp_enum_t := RESP_OKAY;
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant sev: severity_level := failure);

  procedure burst_write(constant cfg: config_t;
                        signal clock: in std_ulogic;
                        signal axi_i: in slave_t;
                        signal axi_o: out master_t;
                        constant addr: unsigned;
                        constant bytes: byte_string;
                        rsp: out resp_enum_t;
                        burst: burst_enum_t := BURST_INCR);
  procedure burst_read(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant addr: unsigned;
                       variable rdata: out byte_string;
                       rsp: out resp_enum_t;
                       burst: burst_enum_t := BURST_INCR);
  procedure burst_check(constant cfg: config_t;
                        signal clock: in std_ulogic;
                        signal axi_i: in slave_t;
                        signal axi_o: out master_t;
                        constant addr: unsigned;
                        constant data: byte_string;
                        constant rsp: resp_enum_t := RESP_OKAY;
                        constant burst: burst_enum_t := BURST_INCR;
                        constant sev: severity_level := failure);

  -- Packing tools
  --
  -- These are helpers to pack each component of an AXI4-MM to a vector
  -- This calculates the needed vector size for storing all the selected
  -- elements of the master signals.
  function address_vector_length(cfg: config_t) return natural;
  function write_data_vector_length(cfg: config_t) return natural;
  function write_response_vector_length(cfg: config_t) return natural;
  function read_data_vector_length(cfg: config_t) return natural;

  -- Packs an AXI4-MM beat (without the valid bit) to a bit vector
  function vector_pack(cfg: config_t; a: address_t) return std_ulogic_vector;
  function vector_pack(cfg: config_t; w: write_data_t) return std_ulogic_vector;
  function vector_pack(cfg: config_t; b: write_response_t) return std_ulogic_vector;
  function vector_pack(cfg: config_t; r: read_data_t) return std_ulogic_vector;

  -- Unpack an AXI-Stream mater interface using items given in elements.
  function address_vector_unpack(cfg: config_t; v: std_ulogic_vector;
                                 valid: boolean := true) return address_t;
  function write_data_vector_unpack(cfg: config_t; v: std_ulogic_vector;
                                   valid : boolean := true; last : boolean := false) return write_data_t;
  function write_response_vector_unpack(cfg: config_t; v: std_ulogic_vector;
                                        valid: boolean := true) return write_response_t;
  function read_data_vector_unpack(cfg: config_t; v: std_ulogic_vector;
                                   valid : boolean := true; last : boolean := false) return read_data_t;
  
  -- AXI4-MM transaction dumper.
  component axi4_mm_dumper is
    generic(
      config_c : config_t;
      prefix_c : string := "AXI4MM"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      master_i : in master_t;
      slave_i : in slave_t
      );
  end component;

  -- AXI4-Lite slave abstraction. It hides all the handshake to the
  -- bus.
  component axi4_mm_lite_slave is
    generic (
      config_c: config_t
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';

      axi_i: in master_t;
      axi_o: out slave_t;

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

  -- AXI4-Lite register map helper. It hides all details of AXI4-lite
  -- and only exposes a bunch of register designated by indexes. The
  -- whole register map has one endianness on the bus. Only writes of
  -- a full data bus width are permitted. Shorter writes will signal a
  -- SLVERR.
  component axi4_mm_lite_regmap is
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

      axi_i: in master_t;
      axi_o: out slave_t;

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

  -- Helper for receiving/sending multi-beat buffers in an abstract way.
  --
  -- Configuration should be created as a constant. It will be used
  -- throughout the calls related to transactor.
  --
  -- Same transactor can be used for reading and writing.
  -- - In either case, transactor state should be reset with reset().
  -- - During write
  --   - every cycle to aw, w and b channels should use output of
  --     address(), write_data() and write_response().
  --   - all cycles should give aw, w and b channels to write_step().
  --   - after is_write_last() returns true, no more call to
  --     write_step should be performed.
  -- - During read
  --   - every cycle to ar and r channels should use output of
  --     address(), read_data().
  --   - all cycles should give ar r channels to read_step().
  --   - after is_read_last() returns true, no more call to
  --     read_step should be performed.
  type transactor_config_t is
  record
    axi: config_t;
    byte_count: natural range 1 to data_t'length;
    strb: std_ulogic_vector(0 to data_t'length-1);
  end record;    

  type transactor_t is
  record
    addr: addr_t;
    data: data_t;
    strb: std_ulogic_vector(0 to data_t'length-1);
    burst_addr_pending: boolean;
    burst_data_pending: boolean;
    burst_resp_pending: boolean;
    beat_left: integer range 0 to data_t'length;
    resp: resp_enum_t;
  end record;

  function to_string(cfg: transactor_config_t)
    return string;
  function to_string(cfg: transactor_config_t; txn: transactor_t)
    return string;

  -- Create a transactor configuration.  This should be used to
  -- initialize a constant.
  --
  -- Byte count is the actual data size of the buffer to read or
  -- write.
  --
  -- On write, only some byte may be strobed. When passing strb bits
  -- here, undefined bits default to '1'.
  function transactor_config(cfg: config_t;
                             byte_count: natural;
                             strb: std_ulogic_vector := na_suv)
    return transactor_config_t;

  -- Retrieve current address of transactor
  function addr(cfg: transactor_config_t; txn: transactor_t)
    return unsigned;

  -- Prepares transactor to perform a read or a write.
  --
  -- After completion of a transaction, address is updated to aligned
  -- address after the buffer size unless you have address_rollback
  -- set while executing last step.
  function reset(cfg: transactor_config_t;
                 txn: transactor_t;
                 addr: unsigned := na_u;
                 bytes: byte_string := null_byte_string;
                 order: byte_order_t := BYTE_ORDER_INCREASING)
    return transactor_t;
  
  -- Tells whether write transaction is complete after this cycle
  function is_write_last(cfg: transactor_config_t;
                         txn: transactor_t;
                         wa: handshake_t;
                         w: handshake_t;
                         b: write_response_t)
    return boolean;

  -- Tells whether read transaction is complete after this cycle
  function is_read_last(cfg: transactor_config_t;
                        txn: transactor_t;
                        ra: handshake_t;
                        r: read_data_t)
    return boolean;

  -- This transitions one step depending on the state of the responses
  -- for a read transaction.
  --
  -- If we are at the last cycle of the transaction (i.e. receiving
  -- the last beat of data in the last burst), restart parameter will
  -- tell whether we should prepare the transactor for the next
  -- transaction.
  --
  -- If address_rollback is set, total size of transacted data is
  -- substracted back from address in a way we'll transact to the same
  -- address.
  --
  -- If transaction ended with an error, address rollback may not
  -- compute correct value. A full transactor reset should be done.
  function read_step(cfg: transactor_config_t; txn: transactor_t;
                     ra: handshake_t;
                     r: read_data_t;
                     restart : boolean := false;
                     address_rollback : boolean := false)
    return transactor_t;

  -- This transitions one step depending on the state of the responses
  -- for a write transaction.
  --
  -- If we are at the last cycle of the transaction (i.e. receiving
  -- the write response in the last burst), restart parameter will
  -- tell whether we should prepare the transactor for the next
  -- transaction.
  --
  -- If address_rollback is set, total size of transacted data is
  -- substracted back from address in a way we'll transact to the same
  -- address.
  --
  -- If transaction ended with an error, address rollback may not
  -- compute correct value. A full transactor reset should be done.
  function write_step(cfg: transactor_config_t; txn: transactor_t;
                      wa: handshake_t;
                      w: handshake_t;
                      b: write_response_t;
                      restart : boolean := false;
                      address_rollback : boolean := false)
    return transactor_t;

  -- This yields the address command suitable for next iteration.
  -- This should be set on relevant port (either ar or aw) as long as
  -- transaction is not complete.
  function address(cfg: transactor_config_t;
                   txn: transactor_t;
                   id: std_ulogic_vector := na_suv;
                   cache: std_ulogic_vector := na_suv;
                   prot: std_ulogic_vector := na_suv;
                   qos: std_ulogic_vector := na_suv;
                   region: std_ulogic_vector := na_suv;
                   user: std_ulogic_vector := na_suv)
    return address_t;

  -- This yields the read data handshake suitable for next iteration
  -- of read transaction.  This should be set on r port as long as
  -- transaction is not complete.  If transaction is a write, this
  -- should not be used.
  function read_data(cfg: transactor_config_t;
                     txn: transactor_t)
    return handshake_t;

  -- This yields the write data command suitable for next iteration of
  -- write transaction.  This should be set on w port as long as
  -- transaction is not complete.  If transaction is a read, this
  -- should not be used.
  function write_data(cfg: transactor_config_t;
                      txn: transactor_t;
                      user: std_ulogic_vector := na_suv)
    return write_data_t;

  -- This yields the write response handshake suitable for next
  -- iteration of write transaction.  This should be set on b port as
  -- long as transaction is not complete.  If transaction is a read,
  -- this should not be used.
  function write_response(cfg: transactor_config_t;
                          txn: transactor_t)
    return handshake_t;

  -- Retrieve the whole significant data of the transactor.
  function bytes(cfg: transactor_config_t;
                 txn: transactor_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;

  -- Retrieve the whole transaction error level.
  function resp(cfg: transactor_config_t;
                txn: transactor_t) return resp_enum_t;
  
  
end package;

package body axi4_mm is

  function to_burst(cfg: config_t; b: burst_t) return burst_enum_t
  is
  begin
    if cfg.has_burst and cfg.len_width /= 0 then
      case b is
        when "00" => return BURST_FIXED;
        when "10" => return BURST_WRAP;
        when others => return BURST_INCR;
      end case;
    else
      return BURST_INCR;
    end if;
  end function;

  function to_logic(cfg: config_t; b: burst_enum_t) return burst_t
  is
  begin
    if cfg.has_burst and cfg.len_width /= 0 then
      case b is
        when BURST_FIXED => return "00";
        when BURST_WRAP => return "10";
        when others => return "01";
      end case;
    else
      return "01";
    end if;
  end function;

  function to_lock(cfg: config_t; l: lock_t) return lock_enum_t
  is
  begin
    if cfg.has_lock then
      case l(l'left) is
        when '0' => return LOCK_NORMAL;
        when others => return LOCK_EXCLUSIVE;
      end case;
    else
      return LOCK_NORMAL;
    end if;
  end function;

  function to_logic(cfg: config_t; l: lock_enum_t) return lock_t
  is
  begin
    if cfg.has_lock then
      case l is
        when LOCK_NORMAL => return "0";
        when LOCK_EXCLUSIVE => return "1";
      end case;
    else
      return "0";
    end if;
  end function;

  function to_resp(cfg: config_t; r: resp_t) return resp_enum_t
  is
  begin
    case r is
      when "00" => return RESP_OKAY;
      when "01" => return RESP_EXOKAY;
      when "10" => return RESP_SLVERR;
      when others => return RESP_DECERR;
    end case;
  end function;

  function to_logic(cfg: config_t; r: resp_enum_t) return resp_t
  is
  begin
    case r is
      when RESP_OKAY => return "00";
      when RESP_EXOKAY => return "01";
      when RESP_SLVERR => return "10";
      when others => return "11";
    end case;
  end function;

  function id(cfg: config_t; addr: address_t) return std_ulogic_vector
  is
  begin
    return addr.id(cfg.id_width-1 downto 0);
  end function;

  function address(cfg: config_t; addr: address_t;
                   lsb: natural := 0) return unsigned
  is
  begin
    return addr.addr(cfg.address_width-1 downto lsb);
  end function;

  function length_m1(cfg: config_t; addr: address_t; w: natural) return unsigned
  is
  begin
    if cfg.len_width = 0 then
      return resize("0", w);
    else
      return resize(addr.len_m1(cfg.len_width-1 downto 0), w);
    end if;
  end function;

  function size_l2(cfg: config_t; addr: address_t) return unsigned
  is
  begin
    if cfg.has_size then
      return addr.size_l2;
    else
      return to_unsigned(cfg.data_bus_width_l2, size_t'length);
    end if;
  end function;

  function burst(cfg: config_t; addr: address_t) return burst_enum_t
  is
  begin
    if cfg.has_burst and cfg.len_width /= 0 then
      return to_burst(cfg, addr.burst);
    else
      return BURST_INCR;
    end if;
  end function;

  function lock(cfg: config_t; addr: address_t) return lock_enum_t
  is
  begin
    return to_lock(cfg, addr.lock);
  end function;

  function cache(cfg: config_t; addr: address_t) return cache_t
  is
  begin
    if cfg.has_cache then
      return addr.cache;
    else
      return "0000";
    end if;
  end function;

  function prot(cfg: config_t; addr: address_t) return prot_t
  is
  begin
    return addr.prot;
  end function;

  function qos(cfg: config_t; addr: address_t) return qos_t
  is
  begin
    if cfg.has_qos then
      return addr.qos;
    else
      return "0000";
    end if;
  end function;

  function region(cfg: config_t; addr: address_t) return region_t
  is
  begin
    if cfg.has_region then
      return addr.region;
    else
      return "0000";
    end if;
  end function;

  function user(cfg: config_t; addr: address_t) return std_ulogic_vector
  is
  begin
    return addr.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; addr: address_t) return boolean
  is
  begin
    return addr.valid = '1';
  end function;

  function is_ready(cfg: config_t; ack: handshake_t) return boolean
  is
  begin
    return ack.ready = '1';
  end function;

  function handshake_defaults(cfg: config_t) return handshake_t
  is
  begin
    return handshake_t'(ready => '0');
  end function; 

  function accept(cfg: config_t; ready: boolean) return handshake_t
  is
    variable ret: handshake_t := handshake_defaults(cfg);
  begin
    if ready then
      ret.ready := '1';
    end if;

    return ret;
  end function; 
       
  function bytes(cfg: config_t; write_data: write_data_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
  begin
    return reorder(write_data.data(0 to 2**cfg.data_bus_width_l2-1), order);
  end function;

  function strb(cfg: config_t; write_data: write_data_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
  begin
    return reorder_mask(write_data.strb(0 to 2**cfg.data_bus_width_l2-1), order);
  end function;

  function value(cfg: config_t; write_data: write_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
  begin
    return from_endian(bytes(cfg, write_data), endian);
  end function;

  function mask(cfg: config_t; write_data: write_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
    variable strb: std_ulogic_vector(0 to 2**cfg.data_bus_width_l2-1) := strb(cfg, write_data);
    variable ret: byte_string(0 to 2**cfg.data_bus_width_l2-1) := (others => x"00");
  begin
    -- Expand strb to mask
    for i in strb'range
    loop
      ret(i) := strb(i) & strb(i) & strb(i) & strb(i) & strb(i) & strb(i) & strb(i) & strb(i);
    end loop;
    return from_endian(ret, endian);
  end function;

  function is_last(cfg: config_t; write_data: write_data_t) return boolean
  is
  begin
    if cfg.len_width = 0 then
      return true;
    else
      return write_data.last = '1';
    end if;
  end function;

  function user(cfg: config_t; write_data: write_data_t) return std_ulogic_vector
  is
  begin
    return write_data.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; write_data: write_data_t) return boolean
  is
  begin
    return write_data.valid = '1';
  end function;

  function id(cfg: config_t; write_response: write_response_t) return std_ulogic_vector
  is
  begin
    return write_response.id(cfg.id_width-1 downto 0);
  end function;

  function resp(cfg: config_t; write_response: write_response_t) return resp_enum_t
  is
  begin
    return to_resp(cfg, write_response.resp);
  end function;

  function user(cfg: config_t; write_response: write_response_t) return std_ulogic_vector
  is
  begin
    return write_response.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; write_response: write_response_t) return boolean
  is
  begin
    return write_response.valid = '1';
  end function;

  function id(cfg: config_t; read_data: read_data_t) return std_ulogic_vector
  is
  begin
    return read_data.id(cfg.id_width-1 downto 0);
  end function;

  function bytes(cfg: config_t; read_data: read_data_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
  begin
    return reorder(read_data.data(0 to 2**cfg.data_bus_width_l2-1), order);
  end function;

  function value(cfg: config_t; read_data: read_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
  begin
    return from_endian(bytes(cfg, read_data), endian);
  end function;

  function resp(cfg: config_t; read_data: read_data_t) return resp_enum_t
  is
  begin
    return to_resp(cfg, read_data.resp);
  end function;

  function is_last(cfg: config_t; read_data: read_data_t) return boolean
  is
  begin
    if cfg.len_width = 0 then
      return true;
    else
      return read_data.last = '1';
    end if;
  end function;

  function user(cfg: config_t; read_data: read_data_t) return std_ulogic_vector
  is
  begin
    return read_data.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; read_data: read_data_t) return boolean
  is
  begin
    return read_data.valid = '1';
  end function;

  function address_defaults(cfg: config_t) return address_t
  is
    variable ret: address_t;
  begin
    ret.id := (others => '0');
    ret.addr := (others => '-');
    ret.len_m1 := (others => '0'); -- 1 actual beat
    ret.size_l2 := to_unsigned(cfg.data_bus_width_l2, size_t'length);
    ret.burst := to_logic(cfg, BURST_INCR);
    ret.lock := "0";
    ret.cache := (others => '0');
    ret.prot := (others => '0');
    ret.qos := (others => '0');
    ret.region := (others => '0');
    ret.user := (others => '-');
    ret.valid := '0';

    return ret;
  end function;
    
  function write_data_defaults(cfg: config_t) return write_data_t
  is
    variable ret: write_data_t;
  begin
    ret.data := (others => (dontcare_byte_c));
    ret.strb := (others => '1');
    if cfg.len_width = 0 then
      ret.last := '1';
    else
      ret.last := '0';
    end if;
    ret.user := (others => '-');
    ret.valid := '0';

    return ret;
  end function;

  function write_response_defaults(cfg: config_t) return write_response_t
  is
    variable ret: write_response_t;
  begin
    ret.id := (others => '0');
    ret.resp := "00";
    ret.user := (others => '-');
    ret.valid := '0';

    return ret;
  end function;

  function read_data_defaults(cfg: config_t) return read_data_t
  is
    variable ret: read_data_t;
  begin
    ret.id := (others => '0');
    ret.data := (others => (dontcare_byte_c));
    ret.resp := "00";
    if cfg.len_width = 0 then
      ret.last := '1';
    else
      ret.last := '0';
    end if;
    ret.user := (others => '-');
    ret.valid := '0';

    return ret;
  end function;

  
  function address(cfg: config_t;
                   id: std_ulogic_vector := na_suv;
                   addr: unsigned := na_u;
                   len_m1: unsigned := na_u;
                   size_l2: unsigned := na_u;
                   burst: burst_enum_t := BURST_INCR;
                   lock: lock_enum_t := LOCK_NORMAL;
                   cache: std_ulogic_vector := na_suv;
                   prot: std_ulogic_vector := na_suv;
                   qos: std_ulogic_vector := na_suv;
                   region: std_ulogic_vector := na_suv;
                   user: std_ulogic_vector := na_suv;
                   valid: boolean := true) return address_t
  is
    variable ret : address_t := address_defaults(cfg);
  begin
    if cfg.id_width /= 0 and id'length /= 0 then
      assert cfg.id_width = id'length
        report "Bad ID vector passed"
        severity failure;
      ret.id(id'length-1 downto 0) := id;
    end if;

    if cfg.address_width /= 0 and addr'length /= 0 then
      assert cfg.address_width = addr'length
        report "Bad Address vector passed"
        severity failure;
      ret.addr(addr'length-1 downto 0) := addr;
    end if;

    if cfg.len_width /= 0 and len_m1'length /= 0 then
      assert cfg.len_width = len_m1'length
        report "Bad Len value passed"
        severity failure;
      ret.len_m1(len_m1'length-1 downto 0) := len_m1;
    end if;
    
    if cfg.has_size and size_l2'length /= 0 then
      assert size_l2'length = size_t'length
        report "Bad Size value passed"
        severity failure;
      ret.size_l2 := size_l2;
    end if;
    
    if cfg.has_burst and cfg.len_width /= 0 then
      ret.burst := to_logic(cfg, burst);
    end if;

    if cfg.has_lock then
      ret.lock := to_logic(cfg, lock);
    end if;

    if cfg.has_cache and cache'length /= 0 then
      assert cache'length = cache_t'length
        report "Bad Cache vector passed"
        severity failure;
      ret.cache := cache;
    end if;

    if prot'length /= 0 then
      assert prot'length = prot_t'length
        report "Bad Prot vector passed"
        severity failure;
      ret.prot := prot;
    end if;

    if cfg.has_qos and qos'length /= 0 then
      assert qos'length = qos_t'length
        report "Bad Qos vector passed"
        severity failure;
      ret.qos := qos;
    end if;

    if cfg.has_region and region'length /= 0 then
      assert region'length = region_t'length
        report "Bad Region vector passed"
        severity failure;
      ret.region := region;
    end if;

    if cfg.user_width /= 0 and user'length /= 0 then
      assert cfg.user_width = user'length
        report "Bad USER vector passed"
        severity failure;
      ret.user(user'length-1 downto 0) := user;
    end if;

    ret.valid := to_logic(valid);

    return ret;
  end function;

  function write_data(cfg: config_t;
                      bytes: byte_string;
                      strb: std_ulogic_vector := na_suv;
                      order: byte_order_t := BYTE_ORDER_INCREASING;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_t
  is
    variable ret: write_data_t := write_data_defaults(cfg);
  begin
    if bytes'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = bytes'length
        report "Bad data vector passed"
        severity failure;
      ret.data(0 to bytes'length-1) := reorder(bytes, order);
    end if;

    if strb'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = strb'length
        report "Bad strb vector passed"
        severity failure;
      ret.strb(0 to strb'length-1) := reorder_mask(strb, order);
    end if;

    if cfg.user_width /= 0 and user'length /= 0 then
      assert cfg.user_width = user'length
        report "Bad USER vector passed"
        severity failure;
      ret.user(user'length-1 downto 0) := user;
    end if;

    ret.valid := to_logic(valid);
    ret.last := to_logic(last or cfg.len_width = 0);

    return ret;
  end function;

 
  function write_data(cfg: config_t;
                      value: unsigned := na_u;
                      strb: std_ulogic_vector := na_suv;
                      endian: endian_t := ENDIAN_LITTLE;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_t
  is
  begin
    if endian = ENDIAN_LITTLE then
      return write_data(cfg,
                        bytes => to_le(value),
                        strb => bitswap(strb),
                        order => BYTE_ORDER_INCREASING,
                        user => user,
                        last => last,
                        valid => valid);
    else
      return write_data(cfg,
                        bytes => to_be(value),
                        strb => strb,
                        order => BYTE_ORDER_INCREASING,
                        user => user,
                        last => last,
                        valid => valid);
    end if;
  end function;
  
  function write_response(cfg: config_t;
                          id: std_ulogic_vector := na_suv;
                          resp: resp_enum_t := RESP_OKAY;
                          user: std_ulogic_vector := na_suv;
                          valid: boolean := true) return write_response_t
  is
    variable ret: write_response_t := write_response_defaults(cfg);
  begin
    ret.resp := to_logic(cfg, resp);

    if cfg.id_width /= 0 and id'length /= 0 then
      assert cfg.id_width = id'length
        report "Bad ID vector passed"
        severity failure;
      ret.id(id'length-1 downto 0) := id;
    end if;

    if cfg.user_width /= 0 and user'length /= 0 then
      assert cfg.user_width = user'length
        report "Bad USER vector passed"
        severity failure;
      ret.user(user'length-1 downto 0) := user;
    end if;

    ret.valid := to_logic(valid);

    return ret;
  end function;

  function read_data(cfg: config_t;
                     id: std_ulogic_vector := na_suv;
                     bytes: byte_string := null_byte_string;
                     order: byte_order_t := BYTE_ORDER_INCREASING;
                     resp: resp_enum_t := RESP_OKAY;
                     user: std_ulogic_vector := na_suv;
                     last: boolean := false;
                     valid: boolean := true) return read_data_t
  is
    variable ret: read_data_t := read_data_defaults(cfg);
  begin
    if bytes'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = bytes'length
        report "Bad data vector passed"
        severity failure;
      ret.data(0 to bytes'length-1) := reorder(bytes, order);
    end if;

    if cfg.id_width /= 0 and id'length /= 0 then
      assert cfg.id_width = id'length
        report "Bad ID vector passed"
        severity failure;
      ret.id(id'length-1 downto 0) := id;
    end if;

    ret.resp := to_logic(cfg, resp);

    if cfg.user_width /= 0 and user'length /= 0 then
      assert cfg.user_width = user'length
        report "Bad USER vector passed"
        severity failure;
      ret.user(user'length-1 downto 0) := user;
    end if;

    ret.last := to_logic(last or cfg.len_width = 0);
    ret.valid := to_logic(valid);

    return ret;
  end function;

  function read_data(cfg: config_t;
                     id: std_ulogic_vector := na_suv;
                     value: unsigned := na_u;
                     endian: endian_t := ENDIAN_LITTLE;
                     resp: resp_enum_t := RESP_OKAY;
                     user: std_ulogic_vector := na_suv;
                     last: boolean := false;
                     valid: boolean := true) return read_data_t
  is
  begin
    return read_data(cfg,
                     id => id,
                     bytes => to_endian(value, endian),
                     order => BYTE_ORDER_INCREASING,
                     resp => resp,
                     user => user,
                     last => last,
                     valid => valid);
  end function;

  function address_const_mask(cfg: config_t; addr: address_t) return addr_t
  is
    variable ret: addr_t := (others => '0');
    constant sl2 : integer range 0 to 2**size_t'length-1 := to_integer(size_l2(cfg, addr));
    constant l: unsigned(3 downto 0) := length_m1(cfg, addr, 4);
  begin
    if burst(cfg, addr) = BURST_WRAP then
      ret := (others => '1');

      -- Only bursts of length 2, 4, 8, 16 are permitted for wrap mode.
      -- Do reverse lookup table to match address length (will be 0001, 0011,
      -- 0111 or 1111).
      for b in 0 to 3 -- MSB wins because processed last
      loop
        if l(b) = '1' then
          for i in 0 to b+sl2
          loop
            ret(i) := '0';
          end loop;
        end if;
      end loop;
    end if;

    -- Whatever the wrapping mode, do not go above address size
    ret(ret'left downto cfg.address_width) := (others => '1');
    -- Whatever the wrapping mode, do not cross 4k boundary
    ret(ret'left downto 12) := (others => '1');

    return ret;
  end function;

  function address_saturation_mask(cfg: config_t; addr: address_t) return addr_t
  is
    variable ret: addr_t := (others => '0');
    variable sl2 : integer range 0 to 2**size_t'length-1 := to_integer(size_l2(cfg, addr));
  begin
    for i in 0 to sl2-1
    loop
      ret(i) := '1';
    end loop;

    return ret;
  end function;

  function length_m1(cfg: config_t; txn: transaction_t) return unsigned
  is
  begin
    return txn.len_m1(cfg.len_width-1 downto 0);
  end function;

  function transaction(cfg: config_t; addr: address_t) return transaction_t
  is
    variable ret: transaction_t;
  begin
    ret.id := addr.id;
    ret.addr := addr.addr;
    ret.len_m1 := addr.len_m1;
    ret.size_l2 := addr.size_l2;
    ret.burst := burst(cfg, addr);
    ret.lock := lock(cfg, addr);
    ret.cache := addr.cache;
    ret.prot := addr.prot;
    ret.qos := addr.qos;
    ret.region := addr.region;
    ret.user := addr.user;
    ret.valid := addr.valid;

    ret.saturation := address_saturation_mask(cfg, addr);
    ret.const_mask := address_const_mask(cfg, addr);

    return ret;
  end function;

  function step(cfg: config_t; txn: transaction_t) return transaction_t
  is
    variable ret: transaction_t := txn;
    variable l : unsigned(cfg.len_width-1 downto 0) := length_m1(cfg, txn);
    constant cur_addr: unsigned(cfg.address_width-1 downto 0) := address(cfg, txn);
    constant sat: unsigned(cur_addr'range) := txn.saturation(cur_addr'range);
    constant cmask: unsigned(cur_addr'range) := txn.const_mask(cur_addr'range);
    constant addr1: addr_t := (others => '1');

    variable next_addr: unsigned(cur_addr'range);
  begin
    if cfg.len_width = 0 then
      ret.valid := '0';
      return ret;
    end if;

    if l = 0 then
      ret.valid := '0';
    else
      ret.len_m1(l'range) := l - 1;
    end if;

    case txn.burst is
      when BURST_FIXED =>
        null;

      when BURST_INCR | BURST_WRAP =>
        -- Saturate LSBs of address to just have to add 1 to roll over to next
        -- aligned address.
        next_addr := (cur_addr or sat) + 1;

        -- Keep bits over allowed wrapping boundary to old value
        -- Use mask_merge to keep '-' where needed.
        ret.addr(next_addr'range) := mask_merge(next_addr, cur_addr, cmask);
    end case;

    return ret;
  end function;

  function id(cfg: config_t; txn: transaction_t) return std_ulogic_vector
  is
  begin
    return txn.id(cfg.id_width-1 downto 0);
  end function;

  function address(cfg: config_t; txn: transaction_t;
                   lsb: natural := 0) return unsigned
  is
  begin
    return txn.addr(cfg.address_width-1 downto lsb);
  end function;

  function size_l2(cfg: config_t; txn: transaction_t) return unsigned
  is
  begin
    if cfg.has_size then
      return txn.size_l2;
    else
      return to_unsigned(cfg.data_bus_width_l2, size_t'length);
    end if;
  end function;

  function lock(cfg: config_t; txn: transaction_t) return lock_enum_t
  is
  begin
    return txn.lock;
  end function;

  function cache(cfg: config_t; txn: transaction_t) return cache_t
  is
  begin
    if cfg.has_cache then
      return txn.cache;
    else
      return "0000";
    end if;
  end function;

  function prot(cfg: config_t; txn: transaction_t) return prot_t
  is
  begin
    return txn.prot;
  end function;

  function qos(cfg: config_t; txn: transaction_t) return qos_t
  is
  begin
    if cfg.has_qos then
      return txn.qos;
    else
      return "0000";
    end if;
  end function;

  function region(cfg: config_t; txn: transaction_t) return region_t
  is
  begin
    if cfg.has_region then
      return txn.region;
    else
      return "0000";
    end if;
  end function;

  function user(cfg: config_t; txn: transaction_t) return std_ulogic_vector
  is
  begin
    return txn.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; txn: transaction_t) return boolean
  is
  begin
    return txn.valid = '1';
  end function;

  function is_last(cfg: config_t; txn: transaction_t) return boolean
  is
    constant l : unsigned := length_m1(cfg, txn);
  begin
    if cfg.len_width = 0 then
      return true;
    end if;

    return l = 0;
  end function;

  function config(address_width: natural;
                  data_bus_width: natural; -- bits
                  user_width: natural := 0;
                  id_width: natural := 0;
                  max_length: natural := 1;
                  size: boolean := false;
                  region: boolean := false;
                  qos: boolean := false;
                  cache: boolean := false;
                  burst: boolean := false;
                  lock: boolean := false) return config_t
  is
    variable ret: config_t;
  begin
    ret.address_width := address_width;
    ret.data_bus_width_l2 := log2(data_bus_width / 8);
    ret.user_width := user_width;
    ret.len_width := log2(max_length);
    ret.id_width := id_width;
    ret.has_size := size;
    ret.has_region := region;
    ret.has_cache := cache;
    ret.has_qos := qos;
    ret.has_burst := burst and ret.len_width /= 0;
    ret.has_lock := lock;
    return ret;
  end function;

  function is_lite(cfg: config_t) return boolean
  is
  begin
    return (cfg.data_bus_width_l2 = 2 or cfg.data_bus_width_l2 = 3)
      and cfg.len_width = 0
      and cfg.id_width = 0
      and not cfg.has_size
      and not cfg.has_region
      and not cfg.has_cache
      and not cfg.has_burst
      and not cfg.has_lock;
  end function;

  
  function to_string(b: burst_enum_t) return string
  is
  begin
    case b is
      when BURST_FIXED => return "Fixed";
      when BURST_INCR => return "Incr";
      when BURST_WRAP => return "Wrap";
    end case;
  end function;

  function to_string(l: lock_enum_t) return string
  is
  begin
    case l is
      when LOCK_NORMAL => return "No";
      when LOCK_EXCLUSIVE => return "Ex";
    end case;
  end function;

  function to_string(r: resp_enum_t) return string
  is
  begin
    case r is
      when RESP_OKAY => return "OK";
      when RESP_EXOKAY => return "EO";
      when RESP_SLVERR => return "SE";
      when RESP_DECERR => return "DE";
    end case;
  end function;

  function to_string(cfg: config_t) return string
  is
  begin
    return "<AXI4"
      &" A"&to_string(cfg.address_width)
      &" D"&to_string(8 * 2**cfg.data_bus_width_l2)
      &if_else(cfg.len_width>0, " L"&to_string(cfg.len_width), "")
      &if_else(cfg.user_width>0, " U"&to_string(cfg.user_width), "")
      &if_else(cfg.id_width>0, " I"&to_string(cfg.id_width), "")
      &" "
      &if_else(cfg.has_size, "S", "")
      &if_else(cfg.has_region, "R", "")
      &if_else(cfg.has_cache, "C", "")
      &if_else(cfg.has_burst and cfg.len_width /= 0, "B", "")
      &if_else(cfg.has_qos, "Q", "")
      &if_else(cfg.has_lock, "X", "")
      &">";
  end;

  function to_string(cfg: config_t; a: address_t) return string
  is
  begin
    if is_valid(cfg, a) then
      return "<Addr"
        &" @"&to_string(address(cfg, a))
        &if_else(cfg.len_width>0, "x"&to_string(to_integer(length_m1(cfg, a, max_len_width_c))+1), "")
        &" by "&to_string(2**to_integer(size_l2(cfg, a)))
        &if_else(cfg.len_width>0, " "&to_string(burst(cfg, a)), "")
        &if_else(cfg.has_lock, " "&to_string(lock(cfg, a)), "")
        &if_else(cfg.has_cache, " C:"&to_string(cache(cfg, a)), "")
        &if_else(cfg.has_qos, " Q:"&to_string(qos(cfg, a)), "")
        &if_else(cfg.has_region, " R:"&to_string(region(cfg, a)), "")
        &if_else(cfg.id_width>0, " I:"&to_string(id(cfg, a)), "")
        &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, a)), "")
        &">";
    else
      return "<Addr ->";
    end if;
  end;

  function to_string(cfg: config_t; t: transaction_t) return string
  is
  begin
    if is_valid(cfg, t) then
      return "<Txn"
        &" @"&to_string(address(cfg, t))
        &if_else(cfg.len_width>0, "x"&to_string(to_integer(length_m1(cfg, t))+1), "")
        &" by "&to_string(2**to_integer(size_l2(cfg, t)))
        &if_else(cfg.len_width>0, " "&to_string(t.burst), "")
        &if_else(cfg.has_lock, " "&to_string(lock(cfg, t)), "")
        &if_else(cfg.has_cache, " C:"&to_string(cache(cfg, t)), "")
        &if_else(cfg.has_qos, " Q:"&to_string(qos(cfg, t)), "")
        &if_else(cfg.has_region, " R:"&to_string(region(cfg, t)), "")
        &if_else(cfg.id_width>0, " I:"&to_string(id(cfg, t)), "")
        &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, t)), "")
        &if_else(cfg.len_width>0 and is_last(cfg, t), " last", "")
        &">";
    else
      return "<Txn ->";
    end if;
  end;

  function to_string(cfg: config_t; w: write_data_t) return string
  is
  begin
    if is_valid(cfg, w) then
      return "<WData"
        &" "&to_string(bytes(cfg, w), mask => strb(cfg, w), masked_out_value => "==")
        &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, w)), "")
        &if_else(cfg.len_width>0 and is_last(cfg, w), " last", "")
        &">";
    else
      return "<WData ->";
    end if;
  end;

  function to_string(cfg: config_t; w: write_response_t) return string
  is
  begin
    if is_valid(cfg, w) then
      return "<WRsp"
        &" "&to_string(resp(cfg, w))
        &if_else(cfg.id_width>0, " I:"&to_string(id(cfg, w)), "")
        &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, w)), "")
        &">";
    else
      return "<WRsp ->";
    end if;
  end;

  function to_string(cfg: config_t; r: read_data_t) return string
  is
  begin
    if is_valid(cfg, r) then
      return "<RRsp"
        &" "&to_string(bytes(cfg, r))
        &" "&to_string(resp(cfg, r))
        &if_else(cfg.id_width>0, " I:"&to_string(id(cfg, r)), "")
        &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, r)), "")
        &if_else(cfg.len_width>0 and is_last(cfg, r), " last", "")
        &">";
    else
      return "<WRsp ->";
    end if;
  end;

  function to_string(cfg: config_t; r: handshake_t) return string
  is
  begin
    return "<Hs "&if_else(is_ready(cfg, r), "OK", "Wait")&">";
  end function;

  procedure lite_write(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant addr: unsigned;
                       constant val: unsigned;
                       constant strb: std_ulogic_vector := "";
                       constant endian: endian_t := ENDIAN_LITTLE;
                       rsp: out resp_enum_t)
  is
    variable aw_done, w_done, b_done: boolean := false;
  begin
    assert is_lite(cfg)
      report "configuration is not lite"
      severity failure;
 
    axi_o.aw <= address(cfg, addr => addr);
    axi_o.w <= write_data(cfg, value => val, strb => strb, endian => endian);
    axi_o.b <= accept(cfg, true);
    
    while not (aw_done and w_done and b_done)
    loop
      wait until rising_edge(clock);
      if is_ready(cfg, axi_i.aw) then
        aw_done := true;
      end if;
      if is_ready(cfg, axi_i.w) then
        w_done := true;
      end if;
      if is_valid(cfg, axi_i.b) then
        b_done := true;
        rsp := resp(cfg, axi_i.b);
      end if;

      wait until falling_edge(clock);

      if aw_done then
        axi_o.aw <= address_defaults(cfg);
      end if;
      if w_done then
        axi_o.w <= write_data_defaults(cfg);
      end if;
      if b_done then
        axi_o.b <= handshake_defaults(cfg);
      end if;
    end loop;
  end procedure;

  procedure lite_read(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant addr: unsigned;
                      val: out unsigned;
                      rsp: out resp_enum_t;
                      constant endian: endian_t := ENDIAN_LITTLE)
  is
    variable ar_done, r_done: boolean := false;
  begin
    assert is_lite(cfg)
      report "configuration is not lite"
      severity failure;

    axi_o.ar <= address(cfg, addr => addr);
    axi_o.r <= accept(cfg, true);
    
    while not (ar_done and r_done)
    loop
      wait until rising_edge(clock);
      if is_ready(cfg, axi_i.ar) then
        ar_done := true;
      end if;
      if is_valid(cfg, axi_i.r) then
        r_done := true;
        val := value(cfg, axi_i.r, endian => endian);
        rsp := resp(cfg, axi_i.b);
      end if;

      wait until falling_edge(clock);

      if ar_done then
        axi_o.ar <= address_defaults(cfg);
      end if;
      if r_done then
        axi_o.r <= handshake_defaults(cfg);
      end if;
    end loop;
  end procedure;

  procedure lite_write(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant reg: integer;
                       constant reg_lsb: integer := 0;
                       constant val: unsigned;
                       constant strb: std_ulogic_vector := "";
                       constant endian: endian_t := ENDIAN_LITTLE;
                       constant rsp: resp_enum_t := RESP_OKAY;
                       constant sev: severity_level := failure)
  is
    variable rrsp: resp_enum_t;
  begin
    lite_write(cfg => cfg,
               clock => clock, axi_i => axi_i, axi_o => axi_o,
               addr => to_unsigned(reg * (2 ** reg_lsb), cfg.address_width),
               val => val,
               strb => strb,
               endian => endian,
               rsp => rrsp);

    assert rsp = rrsp
      report "Response "&to_string(rrsp)&" does not match expected value "&to_string(rsp)
      severity sev;
  end procedure;
  
  procedure lite_read(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      val: out unsigned;
                      rsp: out resp_enum_t;
                      constant endian: endian_t := ENDIAN_LITTLE)
  is
  begin
    lite_read(cfg => cfg,
              clock => clock, axi_i => axi_i, axi_o => axi_o,
              addr => to_unsigned(reg * (2 ** reg_lsb), cfg.address_width),
              val => val,
              endian => endian,
              rsp => rsp);
  end procedure;

  procedure lite_check(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant addr: unsigned;
                      constant val: unsigned := na_u;
                      constant rsp: resp_enum_t := RESP_OKAY;
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant sev: severity_level := failure)
  is
    variable rvalue: unsigned(8 * (2**cfg.data_bus_width_l2) - 1 downto 0);
    variable rrsp: resp_enum_t;
  begin
    lite_read(cfg => cfg,
              clock => clock, axi_i => axi_i, axi_o => axi_o,
              addr => addr,
              val => rvalue,
              endian => endian,
              rsp => rrsp);

    assert rsp = rrsp
      report "Response "&to_string(rrsp)&" does not match expected value "&to_string(rsp)
      severity sev;

    if rsp = RESP_OKAY then
      assert std_match(val, rvalue)
        report "Response "&to_string(rvalue)&" does not match expected value "&to_string(val)
        severity sev;
    end if;
  end procedure;

  procedure lite_check(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant reg: integer;
                      constant reg_lsb: integer := 0;
                      constant val: unsigned := na_u;
                      constant rsp: resp_enum_t := RESP_OKAY;
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant sev: severity_level := failure)
  is
  begin
    lite_check(cfg => cfg,
               clock => clock, axi_i => axi_i, axi_o => axi_o,
               addr => to_unsigned(reg * (2 ** reg_lsb), cfg.address_width),
               val => val,
               rsp => rsp,
               endian => endian,
               sev => sev);
  end procedure;

  function address_vector_length(cfg: config_t) return natural
  is
  begin
    return cfg.address_width
      + prot_t'length
      + if_else(cfg.has_size, size_t'length, 0)
      + if_else(cfg.has_burst and cfg.len_width /= 0, burst_t'length, 0)
      + if_else(cfg.has_cache, cache_t'length, 0)
      + cfg.len_width
      + if_else(cfg.has_lock, lock_t'length, 0)
      + cfg.id_width
      + if_else(cfg.has_qos, qos_t'length, 0)
      + if_else(cfg.has_region, region_t'length, 0)
      + cfg.user_width
      ;
  end function;

  procedure burst_write(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant addr: unsigned;
                       constant bytes: byte_string;
                       rsp: out resp_enum_t;
                       burst: burst_enum_t := BURST_INCR)
  is
    constant start_offset: integer := to_integer(addr) mod (2**cfg.data_bus_width_l2);
    constant stop_offset: integer := (start_offset + bytes'length) mod (2**cfg.data_bus_width_l2);
    constant pad_pre: byte_string(1 to start_offset) := (others => dontcare_byte_c);
    constant pad_post: byte_string(if_else(stop_offset = 0, 2**cfg.data_bus_width_l2, stop_offset)
                                   to 2**cfg.data_bus_width_l2-1) := (others => dontcare_byte_c);

    constant mask_pre: std_ulogic_vector(0 to pad_pre'length-1) := (others => '0');
    constant mask: std_ulogic_vector(0 to bytes'length-1) := (others => '1');
    constant mask_post: std_ulogic_vector(0 to pad_post'length-1) := (others => '0');

    constant actual_data_tmp: byte_string := pad_pre & bytes & pad_post;
    constant actual_mask_tmp: std_ulogic_vector := mask_pre & mask & mask_post;

    alias actual_data: byte_string(0 to actual_data_tmp'length-1) is actual_data_tmp;
    alias actual_mask: std_ulogic_vector(0 to actual_mask_tmp'length-1) is actual_mask_tmp;

    constant aligned_address : unsigned := resize(addr, cfg.address_width) and to_unsigned(2**cfg.data_bus_width_l2-1, cfg.address_width);

    constant w_count: natural := actual_data'length / (2**cfg.data_bus_width_l2);
    variable len_m1 : unsigned(cfg.len_width-1 downto 0) := to_unsigned(w_count - 1, cfg.len_width);

    variable aw_done, b_done, w_pending: boolean := false;
    variable w_index: natural := 0;
  begin
    assert cfg.has_burst
      report "Configuration has no burst capability"
      severity failure;
    
    assert actual_data'length mod (2**cfg.data_bus_width_l2) = 0
      report "Internal error, bad padding calculation"
      severity failure;

    assert actual_data'length <= 2 ** (cfg.len_width + cfg.data_bus_width_l2)
      report "Actual burst is too big for the bus length encoding"
      severity failure;
    
    axi_o.aw <= address(cfg, addr => addr, len_m1 => len_m1, burst => burst);
    axi_o.b <= accept(cfg, true);

    while not (aw_done and w_index = w_count and b_done)
    loop
      if w_index < w_count and not w_pending then
        axi_o.w <= write_data(cfg,
                              bytes => actual_data(w_index * 2**cfg.data_bus_width_l2 to (w_index+1) * 2**cfg.data_bus_width_l2 - 1),
                              strb => actual_mask(w_index * 2**cfg.data_bus_width_l2 to (w_index+1) * 2**cfg.data_bus_width_l2 - 1),
                              last => w_index = w_count - 1);
        w_pending := true;
      end if;

      wait until rising_edge(clock);
      if is_ready(cfg, axi_i.aw) then
        aw_done := true;
      end if;
      if is_ready(cfg, axi_i.w) and w_pending then
        w_pending := false;
        w_index := w_index + 1;
      end if;
      if is_valid(cfg, axi_i.b) then
        b_done := true;
        rsp := resp(cfg, axi_i.b);
      end if;

      wait until falling_edge(clock);

      if aw_done then
        axi_o.aw <= address_defaults(cfg);
      end if;
      if not w_pending then
        axi_o.w <= write_data_defaults(cfg);
      end if;
      if b_done then
        axi_o.b <= handshake_defaults(cfg);
      end if;
    end loop;
  end procedure;

  procedure burst_read(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant addr: unsigned;
                       variable rdata: out byte_string;
                       rsp: out resp_enum_t;
                       burst: burst_enum_t := BURST_INCR)
  is
    constant start_offset: integer := to_integer(addr) mod (2**cfg.data_bus_width_l2);
    constant stop_pad: integer := (- (start_offset + rdata'length)) mod (2**cfg.data_bus_width_l2);
    constant actual_data_length : integer := start_offset + rdata'length + stop_pad;

    variable actual_data: byte_string(0 to actual_data_length-1);
    
    constant aligned_address : unsigned := resize(addr, cfg.address_width) and to_unsigned(2**cfg.data_bus_width_l2-1, cfg.address_width);

    constant r_count: natural := actual_data'length / (2**cfg.data_bus_width_l2);
    variable len_m1 : unsigned(cfg.len_width-1 downto 0) := to_unsigned(r_count - 1, cfg.len_width);

    variable ar_done, r_pending: boolean := false;
    variable r_index: natural := 0;
  begin
    assert cfg.has_burst
      report "Configuration has no burst capability"
      severity failure;
    
    assert actual_data'length mod (2**cfg.data_bus_width_l2) = 0
      report "Internal error, bad padding calculation"
      severity failure;

    assert actual_data'length <= 2 ** (cfg.len_width + cfg.data_bus_width_l2)
      report "Actual burst is too big for the bus length encoding"
      severity failure;
    
    axi_o.ar <= address(cfg, addr => addr, len_m1 => len_m1, burst => burst);
    axi_o.r <= handshake_defaults(cfg);

    while not (ar_done and r_index = r_count)
    loop
      if r_index < r_count and not r_pending then
        axi_o.r <= accept(cfg, true);
        r_pending := true;
      end if;

      wait until rising_edge(clock);
      if is_ready(cfg, axi_i.ar) then
        ar_done := true;
      end if;
      if is_valid(cfg, axi_i.r) and r_pending then
        r_pending := false;

        actual_data(r_index * 2**cfg.data_bus_width_l2 to (r_index+1) * 2**cfg.data_bus_width_l2 - 1)
          := bytes(cfg, axi_i.r);
        rsp := resp(cfg, axi_i.r);
        
        r_index := r_index + 1;
      end if;

      wait until falling_edge(clock);

      if ar_done then
        axi_o.ar <= address_defaults(cfg);
      end if;
      if not r_pending then
        axi_o.r <= handshake_defaults(cfg);
      end if;
    end loop;

    rdata := actual_data(start_offset to start_offset + rdata'length-1);
  end procedure;

  procedure burst_check(constant cfg: config_t;
                        signal clock: in std_ulogic;
                        signal axi_i: in slave_t;
                        signal axi_o: out master_t;
                        constant addr: unsigned;
                        constant data: byte_string;
                        constant rsp: resp_enum_t := RESP_OKAY;
                        constant burst: burst_enum_t := BURST_INCR;
                        constant sev: severity_level := failure)
  is
    alias expected:byte_string(0 to data'length-1) is data;
    variable rdata: byte_string(0 to data'length-1);
    variable rrsp: resp_enum_t;
  begin
    burst_read(cfg, clock, axi_i, axi_o, addr, rdata, rrsp, burst);

    assert rsp = rrsp
      report "Response "&to_string(rrsp)&" does not match expected "&to_string(rsp)
      severity sev;

    if rsp = RESP_OKAY then
      assert rdata = expected
        report "Response data "&to_string(rdata)&" does not match expected "&to_string(expected)
        severity sev;
    end if;
  end procedure;

  function write_data_vector_length(cfg: config_t) return natural
  is
  begin
    return 8 * (2**cfg.data_bus_width_l2)
      + (2**cfg.data_bus_width_l2)
      + cfg.user_width
      ;
  end function;

  function write_response_vector_length(cfg: config_t) return natural
  is
  begin
    return resp_t'length
      + cfg.id_width
      + cfg.user_width
      ;
  end function;

  function read_data_vector_length(cfg: config_t) return natural
  is
  begin
    return 8 * (2**cfg.data_bus_width_l2)
      + resp_t'length
      + cfg.id_width
      + cfg.user_width
      ;
  end function;

  function vector_pack(cfg: config_t; a: address_t) return std_ulogic_vector
  is
    constant len_c : natural := address_vector_length(cfg);
    variable ret: std_ulogic_vector(len_c-1 downto 0);
  begin
    ret := ""
           & user(cfg, a)
           & if_else(cfg.has_region, region(cfg, a), "")
           & if_else(cfg.has_qos, qos(cfg, a), "")
           & id(cfg, a)
           & if_else(cfg.has_lock, to_logic(cfg, lock(cfg, a)), "")
           & std_ulogic_vector(length_m1(cfg, a, cfg.len_width))
           & if_else(cfg.has_cache, cache(cfg, a), "")
           & if_else(cfg.has_burst and cfg.len_width /= 0, to_logic(cfg, burst(cfg, a)), "")
           & if_else(cfg.has_size, std_ulogic_vector(size_l2(cfg, a)), "")
           & prot(cfg, a)
           & std_ulogic_vector(address(cfg, a))
           ;

    return ret;
  end function;

  function vector_pack(cfg: config_t; w: write_data_t) return std_ulogic_vector
  is
    constant len_c : natural := write_data_vector_length(cfg);
    variable ret: std_ulogic_vector(len_c-1 downto 0);
  begin
    ret := ""
           & user(cfg, w)
           & bitswap(strb(cfg, w))
           & std_ulogic_vector(value(cfg, w, ENDIAN_LITTLE))
           ;

    return ret;
  end function;
  
  function vector_pack(cfg: config_t; b: write_response_t) return std_ulogic_vector
  is
    constant len_c : natural := write_response_vector_length(cfg);
    variable ret: std_ulogic_vector(len_c-1 downto 0);
  begin
    ret := ""
           & user(cfg, b)
           & id(cfg, b)
           & to_logic(cfg, resp(cfg, b))
           ;

    return ret;
  end function;
  
  function vector_pack(cfg: config_t; r: read_data_t) return std_ulogic_vector
  is
    constant len_c : natural := read_data_vector_length(cfg);
    variable ret: std_ulogic_vector(len_c-1 downto 0);
  begin
    ret := ""
           & user(cfg, r)
           & id(cfg, r)
           & to_logic(cfg, resp(cfg, r))
           & std_ulogic_vector(value(cfg, r, ENDIAN_LITTLE))
           ;

    return ret;
  end function;

  function address_vector_unpack(cfg: config_t; v: std_ulogic_vector; valid: boolean := true) return address_t
  is
    constant len_c : natural := address_vector_length(cfg);
    alias vv : std_ulogic_vector(len_c-1 downto 0) is v;
    variable point: natural := 0;
    variable ret: address_t := address_defaults(cfg);
    variable id: std_ulogic_vector(cfg.id_width-1 downto 0);
    variable addr: unsigned(cfg.address_width-1 downto 0);
    variable len_m1: unsigned(cfg.len_width-1 downto 0);
    variable size_l2: unsigned(if_else(cfg.has_size, size_t'length, 0)-1 downto 0);
    variable burst: burst_enum_t := BURST_INCR;
    variable lock: lock_enum_t := LOCK_NORMAL;
    variable cache: std_ulogic_vector(if_else(cfg.has_cache, cache_t'length, 0)-1 downto 0);
    variable prot: prot_t;
    variable qos: std_ulogic_vector(if_else(cfg.has_qos, qos_t'length, 0)-1 downto 0);
    variable region: std_ulogic_vector(if_else(cfg.has_region, region_t'length, 0)-1 downto 0);
    variable user: std_ulogic_vector(cfg.user_width-1 downto 0);
  begin
    assert vv'length = len_c
      report "Bad vector length"
      severity failure;

    addr := unsigned(vv(point + addr'length - 1 downto point));
    point := point + addr'length;
    prot := vv(point + prot'length - 1 downto point);
    point := point + prot'length;
    size_l2 := unsigned(vv(point + size_l2'length - 1 downto point));
    point := point + size_l2'length;

    if cfg.has_burst and cfg.len_width /= 0 then
      burst := to_burst(cfg, vv(point + burst_t'length - 1 downto point));
      point := point + burst_t'length;
    end if;

    cache := vv(point + cache'length - 1 downto point);
    point := point + cache'length;
    len_m1 := unsigned(vv(point + len_m1'length - 1 downto point));
    point := point + len_m1'length;

    if cfg.has_lock then
      lock := to_lock(cfg, vv(point + lock_t'length - 1 downto point));
      point := point + lock_t'length;
    end if;

    id := vv(point + id'length - 1 downto point);
    point := point + id'length;
    qos := vv(point + qos'length - 1 downto point);
    point := point + qos'length;
    region := vv(point + region'length - 1 downto point);
    point := point + region'length;
    user := vv(point + user'length - 1 downto point);
    point := point + user'length;

    assert point = len_c
      report "Internal error"
      severity failure;

    return address(cfg,
                   id => id,
                   addr => addr,
                   len_m1 => len_m1,
                   size_l2 => size_l2,
                   burst => burst,
                   lock => lock,
                   cache => cache,
                   prot => prot,
                   qos => qos,
                   region => region,
                   user => user,
                   valid => valid);
  end function;

  function write_data_vector_unpack(cfg: config_t; v: std_ulogic_vector;
                                   valid : boolean := true; last : boolean := false) return write_data_t
  is
    constant len_c : natural := write_data_vector_length(cfg);
    alias vv : std_ulogic_vector(len_c-1 downto 0) is v;
    variable point: natural := 0;
    variable value: unsigned(8*(2**cfg.data_bus_width_l2)-1 downto 0);
    variable strb: std_ulogic_vector(2**cfg.data_bus_width_l2-1 downto 0);
    variable user: std_ulogic_vector(cfg.user_width-1 downto 0);
  begin
    assert vv'length = len_c
      report "Bad vector length"
      severity failure;

    value := unsigned(vv(point + 8 * (2**cfg.data_bus_width_l2) - 1 downto point));
    point := point + value'length;
    strb := vv(point + (2**cfg.data_bus_width_l2) - 1 downto point);
    point := point + strb'length;
    user := vv(point + cfg.user_width - 1 downto point);
    point := point + user'length;

    assert point = len_c
      report "Internal error"
      severity failure;

    return write_data(cfg,
                      value => value,
                      strb => strb,
                      endian => ENDIAN_LITTLE,
                      user => user,
                      last => last,
                      valid => valid);
  end function;

  function write_response_vector_unpack(cfg: config_t; v: std_ulogic_vector; valid: boolean := true) return write_response_t
  is
    constant len_c : natural := write_response_vector_length(cfg);
    alias vv : std_ulogic_vector(len_c-1 downto 0) is v;
    variable point: natural := 0;
    variable resp: resp_enum_t;
    variable id: std_ulogic_vector(cfg.id_width-1 downto 0);
    variable user: std_ulogic_vector(cfg.user_width-1 downto 0);
  begin
    assert vv'length = len_c
      report "Bad vector length"
      severity failure;

    resp := to_resp(cfg, vv(point + resp_t'length - 1 downto point));
    point := point + resp_t'length;
    id := vv(point + cfg.id_width - 1 downto point);
    point := point + id'length;
    user := vv(point + cfg.user_width - 1 downto point);
    point := point + user'length;

    assert point = len_c
      report "Internal error"
      severity failure;

    return write_response(cfg,
                          id => id,
                          resp => resp,
                          user => user,
                          valid => valid);
  end function;

  function read_data_vector_unpack(cfg: config_t; v: std_ulogic_vector;
                                   valid : boolean := true; last : boolean := false) return read_data_t
  is
    constant len_c : natural := read_data_vector_length(cfg);
    alias vv : std_ulogic_vector(len_c-1 downto 0) is v;
    variable point: natural := 0;
    variable value: unsigned(8*(2**cfg.data_bus_width_l2)-1 downto 0);
    variable resp: resp_enum_t;
    variable id: std_ulogic_vector(cfg.id_width-1 downto 0);
    variable user: std_ulogic_vector(cfg.user_width-1 downto 0);
  begin
    assert vv'length = len_c
      report "Bad vector length"
      severity failure;

    value := unsigned(vv(point + 8 * (2**cfg.data_bus_width_l2) - 1 downto point));
    point := point + value'length;
    resp := to_resp(cfg, vv(point + resp_t'length - 1 downto point));
    point := point + resp_t'length;
    id := vv(point + cfg.id_width - 1 downto point);
    point := point + id'length;
    user := vv(point + cfg.user_width - 1 downto point);
    point := point + user'length;

    assert point = len_c
      report "Internal error"
      severity failure;

    return read_data(cfg,
                     id => id,
                     value => value,
                     endian => ENDIAN_LITTLE,
                     resp => resp,
                     user => user,
                     last => last,
                     valid => valid);
  end function;


  function to_string(cfg: transactor_config_t)
    return string
  is

  begin
    return "<Trx "
      & to_string(cfg.axi)
      & " " & to_string(cfg.byte_count) & " bytes, strb="
      & to_string(cfg.strb(0 to cfg.byte_count-1))
      & ">";
  end function;
  
  function to_string(cfg: transactor_config_t; txn: transactor_t)
    return string
  is
    constant bytes_per_beat: natural := 2**cfg.axi.data_bus_width_l2;
    constant max_beat_per_burst: natural := 2**cfg.axi.len_width;
    constant total_beat_count : natural := (cfg.byte_count + bytes_per_beat - 1) / bytes_per_beat;
    constant beat_index : natural := total_beat_count - txn.beat_left;
  begin
    return "<Txn beat "&to_string(beat_index)
      & "/" & to_string(total_beat_count)
      & " Pending: "
      & if_else(txn.burst_addr_pending, "@", "")
      & if_else(txn.burst_data_pending, "D", "")
      & if_else(txn.burst_resp_pending, "R", "")
      & ">";
  end function;

  function transactor_config(cfg: config_t;
                             byte_count: natural;
                             strb: std_ulogic_vector := na_suv)
    return transactor_config_t
  is
    constant strb_pad : strobe_t := (others => '1');
    constant strb_all : std_ulogic_vector(0 to strb_pad'length+strb'length-1) := strb & strb_pad;
  begin
    return transactor_config_t'(
      axi => cfg,
      byte_count => byte_count,
      strb => strb_all(0 to strobe_t'length-1)
      );
  end function;

  function addr(cfg: transactor_config_t; txn: transactor_t)
    return unsigned
  is
  begin
    return txn.addr(cfg.axi.address_width-1 downto 0);
  end function;

  function reset(cfg: transactor_config_t;
                 txn: transactor_t;
                 addr: unsigned := na_u;
                 bytes: byte_string := null_byte_string;
                 order: byte_order_t := BYTE_ORDER_INCREASING)
    return transactor_t
  is
    constant bytes_per_beat: natural := 2**cfg.axi.data_bus_width_l2;
    constant total_byte_count : natural := mod_up(cfg.byte_count, bytes_per_beat);
    constant total_beat_count : natural := total_byte_count / bytes_per_beat;

    variable ret : transactor_t := txn;

    constant data_pad : data_t := (others => dontcare_byte_c);
    constant data_all : byte_string(0 to data_pad'length+bytes'length-1) := bytes & data_pad;
  begin
    if addr'length /= 0 then
      ret.addr := (others => '-');
      ret.addr(cfg.axi.address_width-1 downto 0)
        := resize(addr, cfg.axi.address_width);
      ret.addr(cfg.axi.data_bus_width_l2-1 downto 0) := (others => '0');
    end if;

    if bytes'length /= 0 then
      ret.data := (others => dontcare_byte_c);
      ret.data(0 to total_byte_count - 1) := data_all(0 to total_byte_count - 1);
      ret.burst_resp_pending := true;
    end if;

    ret.strb := cfg.strb;
    ret.burst_addr_pending := true;
    ret.burst_data_pending := true;
    ret.beat_left := total_beat_count - 1;
    ret.resp := RESP_OKAY;

    return ret;
  end function;

  function is_write_last(cfg: transactor_config_t;
                         txn: transactor_t;
                         wa: handshake_t;
                         w: handshake_t;
                         b: write_response_t)
    return boolean
  is
  begin
    return (not txn.burst_addr_pending or is_ready(cfg.axi, wa))
      and (not txn.burst_data_pending or is_ready(cfg.axi, w))
      and (not txn.burst_resp_pending or is_valid(cfg.axi, b))
      and (txn.beat_left = 0 or txn.resp /= RESP_OKAY);
  end function;

  function is_read_last(cfg: transactor_config_t;
                        txn: transactor_t;
                        ra: handshake_t;
                        r: read_data_t)
    return boolean
  is
  begin
    return (not txn.burst_addr_pending or is_ready(cfg.axi, ra))
      and (not txn.burst_data_pending or (is_valid(cfg.axi, r) and is_last(cfg.axi, r)))
      and (txn.beat_left = 0 or txn.resp /= RESP_OKAY);
  end function;

  function read_step(cfg: transactor_config_t; txn: transactor_t;
                     ra: handshake_t;
                     r: read_data_t;
                     restart : boolean := false;
                     address_rollback: boolean := false)
    return transactor_t
  is
    constant bytes_per_beat: natural := 2**cfg.axi.data_bus_width_l2;
    constant total_beat_count : natural := (cfg.byte_count + bytes_per_beat - 1) / bytes_per_beat;
    constant total_byte_count : natural := total_beat_count * bytes_per_beat;
    constant strb_pad: std_ulogic_vector(0 to bytes_per_beat-1) := (others => '-');
    constant burst_last : boolean := is_last(cfg.axi, r);

    variable rin : transactor_t := txn;
    variable addr_done, data_done : boolean := false;
  begin
    if not txn.burst_addr_pending then
      addr_done := true;
    elsif is_ready(cfg.axi, ra) then
      rin.burst_addr_pending := false;
      addr_done := true;
    end if;

    if not txn.burst_data_pending then
      data_done := true;
    elsif is_valid(cfg.axi, r) then
      rin.data(0 to total_byte_count-1) := txn.data(bytes_per_beat to total_byte_count-1) & bytes(cfg.axi, r);
      rin.strb(0 to total_byte_count-1) := txn.strb(bytes_per_beat to total_byte_count-1) & strb_pad;
      rin.addr(cfg.axi.address_width-1 downto 0) := addr(cfg, txn) + bytes_per_beat;

      if txn.resp = RESP_OKAY then
        rin.resp := resp(cfg.axi, r);
      end if;

      if txn.beat_left /= 0 then
        rin.beat_left := txn.beat_left - 1;
      end if;

      if burst_last then
        data_done := true;
        rin.burst_data_pending := false;
      end if;
    end if;

    if addr_done and data_done then
      if txn.resp /= RESP_OKAY or resp(cfg.axi, r) /= RESP_OKAY then
        -- Dont restart, kill pending words
        rin.beat_left := 0;
      elsif txn.beat_left /= 0 then
        rin.burst_addr_pending := true;
      elsif restart then
        if address_rollback then
          rin.addr(cfg.axi.address_width-1 downto 0)
            := addr(cfg, txn) + bytes_per_beat - total_byte_count;
        end if;
        rin.strb := cfg.strb;
        rin.burst_addr_pending := true;
        rin.burst_data_pending := true;
        rin.beat_left := total_beat_count - 1;
      end if;
    end if;

    return rin;
  end function;

  -- This transitions one step depending on the state of the responses
  -- for a write transaction.
  function write_step(cfg: transactor_config_t; txn: transactor_t;
                      wa: handshake_t;
                      w: handshake_t;
                      b: write_response_t;
                      restart : boolean := false;
                      address_rollback: boolean := false)
    return transactor_t
  is
    constant bytes_per_beat: natural := 2**cfg.axi.data_bus_width_l2;
    constant total_beat_count : natural := (cfg.byte_count + bytes_per_beat - 1) / bytes_per_beat;
    constant total_byte_count : natural := total_beat_count * bytes_per_beat;
    constant max_beat_per_burst: natural := 2**cfg.axi.len_width;

    constant data_pad: byte_string(0 to bytes_per_beat-1) := (others => dontcare_byte_c);
    constant strb_pad: std_ulogic_vector(0 to bytes_per_beat-1) := (others => '-');
    constant burst_last : boolean := (txn.beat_left mod max_beat_per_burst) = 0;

    variable rin : transactor_t := txn;
    variable addr_done, resp_done, data_done : boolean := false;
  begin
    if not txn.burst_addr_pending then
      addr_done := true;
    elsif is_ready(cfg.axi, wa) then
      rin.burst_addr_pending := false;
      addr_done := true;
    end if;

    if not txn.burst_data_pending then
      data_done := true;
    elsif is_ready(cfg.axi, w) then
      rin.data(0 to total_byte_count-1) := txn.data(bytes_per_beat to total_byte_count-1) & data_pad;
      rin.strb(0 to total_byte_count-1) := txn.strb(bytes_per_beat to total_byte_count-1) & strb_pad;
      rin.addr(cfg.axi.address_width-1 downto 0) := addr(cfg, txn) + bytes_per_beat;

      if txn.beat_left /= 0 then
        rin.beat_left := txn.beat_left - 1;
      end if;

      if burst_last then
        data_done := true;
        rin.burst_data_pending := false;
      end if;
    end if;

    if not txn.burst_resp_pending then
      resp_done := true;
    elsif is_valid(cfg.axi, b) then
      resp_done := true;
      rin.burst_resp_pending := false;
      rin.resp := resp(cfg.axi, b);
    end if;

    if addr_done and data_done and resp_done then
      if resp(cfg.axi, b) /= RESP_OKAY then
        -- Dont restart, kill pending words
        rin.beat_left := 0;
      elsif txn.beat_left /= 0 then
        rin.burst_addr_pending := true;
        rin.burst_data_pending := true;
        rin.burst_resp_pending := true;
      elsif restart then
        if address_rollback then
          rin.addr(cfg.axi.address_width-1 downto 0)
            := addr(cfg, txn) - total_byte_count;
        end if;
        rin.strb := cfg.strb;
        rin.burst_addr_pending := true;
        rin.burst_data_pending := true;
        rin.burst_resp_pending := true;
        rin.beat_left := total_beat_count - 1;
      end if;
    end if;

    return rin;
  end function;

  function address(cfg: transactor_config_t;
                   txn: transactor_t;
                   id: std_ulogic_vector := na_suv;
                   cache: std_ulogic_vector := na_suv;
                   prot: std_ulogic_vector := na_suv;
                   qos: std_ulogic_vector := na_suv;
                   region: std_ulogic_vector := na_suv;
                   user: std_ulogic_vector := na_suv)
    return address_t
  is
  begin
    return address(
      cfg.axi,
      addr => addr(cfg, txn),
      -- Hack: This automagically gives the right value because of
      -- truncation.
      len_m1 => to_unsigned(txn.beat_left, cfg.axi.len_width),
      cache => cache,
      prot => prot,
      qos => qos,
      region => region,
      user => user,
      valid => txn.burst_addr_pending);
  end function;

  function read_data(cfg: transactor_config_t;
                     txn: transactor_t)
    return handshake_t
  is
  begin
    return accept(cfg.axi, ready => txn.burst_data_pending);
  end function;

  function write_data(cfg: transactor_config_t;
                      txn: transactor_t;
                      user: std_ulogic_vector := na_suv)
    return write_data_t
  is
    constant bytes_per_beat: natural := 2**cfg.axi.data_bus_width_l2;
    constant max_beat_per_burst: natural := 2**cfg.axi.len_width;
    constant burst_last : boolean := (txn.beat_left mod max_beat_per_burst) = 0;
  begin
    return write_data(cfg.axi,
                      bytes => txn.data(0 to bytes_per_beat-1),
                      strb => txn.strb(0 to bytes_per_beat-1),
                      user => user,
                      valid => txn.burst_data_pending,
                      last => burst_last);
  end function;

  function write_response(cfg: transactor_config_t;
                          txn: transactor_t)
    return handshake_t
  is
  begin
    return accept(cfg.axi, ready => txn.burst_resp_pending);
  end function;

  function bytes(cfg: transactor_config_t;
                 txn: transactor_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
  begin
    return reorder(txn.data(0 to cfg.byte_count-1), order);
  end function;

  function resp(cfg: transactor_config_t;
                txn: transactor_t) return resp_enum_t
  is
  begin
    return txn.resp;
  end function;
  

  
end package body axi4_mm;
