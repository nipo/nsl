library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data;
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

  -- Arbitrary
  constant max_address_width_c: natural := 64;
  constant max_data_bus_width_l2_l2_c: natural := 3;
  constant max_user_width_c: natural := 64;

  -- Elementary data types
  constant region_width_c: natural := 4;
  constant max_id_width_c: natural := 64;
  constant max_len_width_c: natural := 8;

  constant size_width_c: natural := 3;
  constant cache_width_c: natural := 4;
  constant prot_width_c: natural := 3;
  constant qos_width_c: natural := 4;

  constant max_data_byte_count_l2_c : natural := 2**max_data_bus_width_l2_l2_c-1;
  
  subtype addr_t is unsigned(max_address_width_c - 1 downto 0);
  subtype user_t is std_ulogic_vector(max_user_width_c - 1 downto 0);
  subtype strobe_t is std_ulogic_vector(0 to 2**max_data_byte_count_l2_c - 1);
  subtype data_t is byte_string(0 to 2**max_data_byte_count_l2_c-1);
  subtype region_t is std_ulogic_vector(region_width_c - 1 downto 0);
  subtype id_t is std_ulogic_vector(max_id_width_c - 1 downto 0);
  subtype len_t is unsigned(max_len_width_c - 1 downto 0);
  subtype size_t is unsigned(size_width_c - 1 downto 0);
  subtype cache_t is std_ulogic_vector(cache_width_c - 1 downto 0);
  subtype prot_t is std_ulogic_vector(prot_width_c - 1 downto 0);
  subtype qos_t is std_ulogic_vector(qos_width_c - 1 downto 0);
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
    lock: std_ulogic;
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
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_t;

  -- Write data beat using unsigned as data vector.  Uses passed
  -- endianness for value, strb always uses ascending order.
  function write_data(cfg: config_t;
                      value: unsigned := na_u;
                      endian: endian_t := ENDIAN_LITTLE;
                      strb: std_ulogic_vector := na_suv;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_t;

  -- Retrieve the bytes of the write data beat. Returned byte_string
  -- is in ascending order
  function bytes(cfg: config_t; write_data: write_data_t) return byte_string;
  -- Retrieve the binary value as if the bus was carrying a numeric
  -- value.  Parse the bus as of endian passed.
  function value(cfg: config_t; write_data: write_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned;
  -- Retrieve the mask of the write data beat. Returned vector is in
  -- ascending order
  function strb(cfg: config_t; write_data: write_data_t) return std_ulogic_vector;
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
  function bytes(cfg: config_t; read_data: read_data_t) return byte_string;
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
  type master_t is
  record
    aw: address_t;
    w: write_data_t;
    b: handshake_t;
    ar: address_t;
    r: handshake_t;
  end record;

  -- Slave-driven meta-record. Can typically be used as port.
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
    m: master_t;
    s: slave_t;
  end record;

  -- Vectors
  type master_vector is array (natural range <>) of master_t;
  type slave_vector is array (natural range <>) of slave_t;
  type bus_vector is array (natural range <>) of bus_t;
  type address_vector is array (natural range <>) of addr_t;


  -- Convertors between semantic enums and bit encoding
  function to_burst(cfg: config_t; b: burst_t) return burst_enum_t;
  function to_logic(cfg: config_t; b: burst_enum_t) return burst_t;
  function to_lock(cfg: config_t; l: std_ulogic) return lock_enum_t;
  function to_logic(cfg: config_t; l: lock_enum_t) return std_ulogic;
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
    lock: std_ulogic;
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

  -- Parse an address. Address may contain don't care bits ('-').
  -- Moreover, a mask may be added after the address to ignore LSBs
  -- (by specifying count of useful bits).
  --
  -- Address may be either:
  -- - a binary string, it can be either a bit value (MSB first) or a
  --   VHDL hex value (e.g. x"1234", in such case, this helper will
  --   receive binary string). Bit literal may contain '-'.
  -- - a hex string, prefixed by x like "x1234". In such case, '-' in
  --   the string marks a full nibble as don't care.
  --
  -- After address, a mask in the form "/n" with n a number of bits
  -- can be added.
  --
  -- Examples:
  -- - x"dead0000" is x"dead0000"
  -- - "xdead0000" is x"dead0000"
  -- - "xdead00--" is x"dead00"&"--------"
  -- - "xdead0000/24" is x"dead00"&"--------"
  function address_parse(cfg:config_t; addr:string) return addr_t;

  -- Create an array of addresses from 1 to 16 items in length.
  -- First null string in arguments d1 to d15 marks the end of the
  -- array.
  function routing_table(cfg: config_t;
                         d0:string;
                         d1, d2, d3, d4, d5, d6, d7,
                         d8, d9, d10, d11, d12, d13, d14, d15: string := "") return address_vector;

  -- Internal
  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');
  constant na_u: unsigned(1 to 0) := (others => '-');


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

  -- Simulation helper function to issue a write transaction to an
  -- AXI4-Lite bus.
  procedure lite_write(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant addr: unsigned;
                       constant val: unsigned;
                       rsp: out resp_enum_t;
                       constant endian: endian_t := ENDIAN_LITTLE;
                       constant mask: std_ulogic_vector := "");
  -- Simulation helper function to issue a read transaction to an
  -- AXI4-Lite bus.
  procedure lite_read(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal axi_i: in slave_t;
                      signal axi_o: out master_t;
                      constant addr: unsigned;
                      val: out unsigned;
                      rsp: out resp_enum_t;
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant mask: std_ulogic_vector := "");

  -- AXI4-MM RAM with concurrent read and write channels.  It supports
  -- bursting and requires a dual-port block RAM
  component axi4_mm_ram is
    generic(
      config_c : config_t;
      byte_size_l2_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i : in master_t;
      axi_o : out slave_t
      );
  end component;

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
      -- Write data acceptance from user
      w_ready_i : in std_ulogic := '1';
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

  -- AXI4-Lite RAM, using a one-port block RAM.
  component axi4_mm_lite_ram is
    generic (
      config_c: config_t;
      byte_size_l2_c: natural := 12
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';

      axi_i: in master_t;
      axi_o: out slave_t
      );
  end component;
  
end package;

package body axi4_mm is

  function nibble_parse(nibble: character) return unsigned
  is
  begin
    case nibble is
      when '0' => return x"0";
      when '1' => return x"1";
      when '2' => return x"2";
      when '3' => return x"3";
      when '4' => return x"4";
      when '5' => return x"5";
      when '6' => return x"6";
      when '7' => return x"7";
      when '8' => return x"8";
      when '9' => return x"9";
      when 'a'|'A' => return x"a";
      when 'b'|'B' => return x"b";
      when 'c'|'C' => return x"c";
      when 'd'|'D' => return x"d";
      when 'e'|'E' => return x"e";
      when 'f'|'F' => return x"f";
      when '-' => return "----";
      when others => return "XXXX";
    end case;
  end function;

  function bin_address_parse(cfg:config_t; addr:string) return addr_t
  is
    alias bits: string(addr'length-1 downto 0) is addr;
    variable b: character;
    variable ret : addr_t := (others => '0');
  begin
    for i in bits'left downto bits'right
    loop
      b := bits(i);

      case b is
        when '0' => ret := ret(ret'high-1 downto 0) & '0';
        when '1' => ret := ret(ret'high-1 downto 0) & '1';
        when '-' => ret := ret(ret'high-1 downto 0) & '-';
        when '_' | ' ' =>  next;
        when others =>
          assert false
            report "Bad character '"&b&"' in address, ignored"
            severity warning;
      end case;
    end loop;
    ret(ret'high downto cfg.address_width) := (others => '-');
    return ret;
  end function;

  function hex_address_parse(cfg:config_t; addr:string) return addr_t
  is
    alias nibbles: string(addr'length-1 downto 0) is addr;
    variable nibble: character;
    variable ret : addr_t := (others => '0');
  begin
    for i in nibbles'left downto nibbles'right
    loop
      nibble := nibbles(i);
      if nibble = '_' or nibble = ' ' then
        next;
      end if;
      ret := ret(ret'high-4 downto 0) & nibble_parse(nibble);
    end loop;
    ret(ret'high downto cfg.address_width) := (others => '-');
    return ret;
  end function;

  function address_parse(cfg:config_t; addr:string) return addr_t
  is
    variable ret : addr_t := (others => '-');
    variable slash_index : integer := -1;
    variable start : integer := 0;
    variable stop : integer := addr'length-1;
    variable hex_mode : boolean := false;
    variable ignored_lsbs : integer := 0;
    alias a : string(0 to addr'length-1) is addr;
  begin
    slash_index := strchr(addr, '/');
    if slash_index >= 0 then
      stop := slash_index-1;
      ignored_lsbs := cfg.address_width - integer'value(a(slash_index+1 to a'right));
    end if;
    
    if a(0) = 'x' then
      ret := hex_address_parse(cfg, a(1 to stop));
    else
      ret := bin_address_parse(cfg, a(0 to stop));
    end if;

    if ignored_lsbs /= 0 then
      ret(ignored_lsbs-1 downto 0) := (others => '-');
    end if;

    ret(ret'high downto cfg.address_width) := (others => '-');

    return ret;
  end function;
  
  function routing_table(cfg: config_t;
                         d0: string;
                         d1, d2, d3, d4, d5, d6, d7,
                         d8, d9, d10, d11, d12, d13, d14, d15: string := "") return address_vector
  is
    variable ret: address_vector(0 to 15) := (others => (others => '-'));
  begin
    ret(0) := address_parse(cfg, d0);
    if d1'length = 0 then return ret(0 to 0); end if;
    ret(1) := address_parse(cfg, d1);
    if d2'length = 0 then return ret(0 to 1); end if;
    ret(2) := address_parse(cfg, d2);
    if d3'length = 0 then return ret(0 to 2); end if;
    ret(3) := address_parse(cfg, d3);
    if d4'length = 0 then return ret(0 to 3); end if;
    ret(4) := address_parse(cfg, d4);
    if d5'length = 0 then return ret(0 to 4); end if;
    ret(5) := address_parse(cfg, d5);
    if d6'length = 0 then return ret(0 to 5); end if;
    ret(6) := address_parse(cfg, d6);
    if d7'length = 0 then return ret(0 to 6); end if;
    ret(7) := address_parse(cfg, d7);
    if d8'length = 0 then return ret(0 to 7); end if;
    ret(8) := address_parse(cfg, d8);
    if d9'length = 0 then return ret(0 to 8); end if;
    ret(9) := address_parse(cfg, d9);
    if d10'length = 0 then return ret(0 to 9); end if;
    ret(10) := address_parse(cfg, d10);
    if d11'length = 0 then return ret(0 to 10); end if;
    ret(11) := address_parse(cfg, d11);
    if d12'length = 0 then return ret(0 to 11); end if;
    ret(12) := address_parse(cfg, d12);
    if d13'length = 0 then return ret(0 to 12); end if;
    ret(13) := address_parse(cfg, d13);
    if d14'length = 0 then return ret(0 to 13); end if;
    ret(14) := address_parse(cfg, d14);
    if d15'length = 0 then return ret(0 to 14); end if;
    ret(15) := address_parse(cfg, d15);
    return ret(0 to 15);
  end function;

  function to_burst(cfg: config_t; b: burst_t) return burst_enum_t
  is
  begin
    if cfg.has_burst then
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
    if cfg.has_burst then
      case b is
        when BURST_FIXED => return "00";
        when BURST_WRAP => return "10";
        when others => return "01";
      end case;
    else
      return "01";
    end if;
  end function;

  function to_lock(cfg: config_t; l: std_ulogic) return lock_enum_t
  is
  begin
    if cfg.has_lock then
      case l is
        when '0' => return LOCK_NORMAL;
        when others => return LOCK_EXCLUSIVE;
      end case;
    else
      return LOCK_NORMAL;
    end if;
  end function;

  function to_logic(cfg: config_t; l: lock_enum_t) return std_ulogic
  is
  begin
    if cfg.has_lock then
      case l is
        when LOCK_NORMAL => return '0';
        when LOCK_EXCLUSIVE => return '1';
      end case;
    else
      return '0';
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
      return resize("1", w);
    else
      return resize(addr.len_m1(cfg.len_width-1 downto 0), w);
    end if;
  end function;

  function size_l2(cfg: config_t; addr: address_t) return unsigned
  is
  begin
    if cfg.has_size then
      return addr.size_l2(size_width_c-1 downto 0);
    else
      return to_unsigned(cfg.data_bus_width_l2, size_width_c);
    end if;
  end function;

  function burst(cfg: config_t; addr: address_t) return burst_enum_t
  is
  begin
    if cfg.has_burst then
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
       
  function bytes(cfg: config_t; write_data: write_data_t) return byte_string
  is
  begin
    return write_data.data(0 to 2**cfg.data_bus_width_l2-1);
  end function;

  function value(cfg: config_t; write_data: write_data_t; endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
  begin
    return from_endian(bytes(cfg, write_data), endian);
  end function;

  function strb(cfg: config_t; write_data: write_data_t) return std_ulogic_vector
  is
  begin
    return write_data.strb(0 to 2**cfg.data_bus_width_l2-1);
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

  function bytes(cfg: config_t; read_data: read_data_t) return byte_string
  is
  begin
    return read_data.data(0 to 2**cfg.data_bus_width_l2-1);
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
    ret.size_l2 := to_unsigned(cfg.data_bus_width_l2, size_width_c);
    ret.burst := to_logic(cfg, BURST_INCR);
    ret.lock := '0';
    ret.cache := (others => '0');
    ret.prot := (others => '-');
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
      assert size_l2'length = size_width_c
        report "Bad Size value passed"
        severity failure;
      ret.size_l2 := size_l2;
    end if;
    
    if cfg.has_burst then
      ret.burst := to_logic(cfg, burst);
    end if;

    if cfg.has_lock then
      ret.lock := to_logic(cfg, lock);
    end if;

    if cfg.has_cache and cache'length /= 0 then
      assert cache'length = cache_width_c
        report "Bad Cache vector passed"
        severity failure;
      ret.cache := cache;
    end if;

    if prot'length /= 0 then
      assert prot'length = prot_width_c
        report "Bad Prot vector passed"
        severity failure;
      ret.prot := prot;
    end if;

    if cfg.has_qos and qos'length /= 0 then
      assert qos'length = qos_width_c
        report "Bad Qos vector passed"
        severity failure;
      ret.qos := qos;
    end if;

    if cfg.has_region and region'length /= 0 then
      assert region'length = region_width_c
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
      ret.data(0 to bytes'length-1) := bytes;
    end if;

    if strb'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = strb'length
        report "Bad strobe vector passed"
        severity failure;
      ret.strb(0 to strb'length-1) := strb;
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
                      endian: endian_t := ENDIAN_LITTLE;
                      strb: std_ulogic_vector := na_suv;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_t
  is
  begin
    return write_data(cfg, to_endian(value, endian), strb, user, last, valid);
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
      ret.data(0 to bytes'length-1) := bytes;
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
    return read_data(cfg, id, to_endian(value, endian), resp, user, last, valid);
  end function;

  function address_const_mask(cfg: config_t; addr: address_t) return addr_t
  is
    variable ret: addr_t := (others => '0');
    constant sl2 : integer range 0 to 2**size_width_c-1 := to_integer(size_l2(cfg, addr));
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
    variable sl2 : integer range 0 to 2**size_width_c-1 := to_integer(size_l2(cfg, addr));
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
    ret.lock := addr.lock;
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
      return txn.size_l2(size_width_c-1 downto 0);
    else
      return to_unsigned(cfg.data_bus_width_l2, size_width_c);
    end if;
  end function;

  function lock(cfg: config_t; txn: transaction_t) return lock_enum_t
  is
  begin
    return to_lock(cfg, txn.lock);
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
                  cache: boolean := false;
                  burst: boolean := false;
                  lock: boolean := false) return config_t
  is
    variable ret: config_t;
  begin
    ret.address_width := address_width;
    ret.data_bus_width_l2 := nsl_math.arith.log2(data_bus_width / 8);
    ret.user_width := user_width;
    ret.len_width := nsl_math.arith.log2(max_length);
    ret.id_width := id_width;
    ret.has_size := size;
    ret.has_region := region;
    ret.has_cache := cache;
    ret.has_burst := burst;
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
      &if_else(cfg.has_size, " S", "")
      &if_else(cfg.has_region, " R", "")
      &if_else(cfg.has_cache, " C", "")
      &if_else(cfg.has_burst, " B", "")
      &if_else(cfg.has_lock, " X", "")
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
        &" "&to_string(bytes(cfg, w))
        &" S:"&to_string(strb(cfg, w))
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

  procedure lite_write(constant cfg: config_t;
                       signal clock: in std_ulogic;
                       signal axi_i: in slave_t;
                       signal axi_o: out master_t;
                       constant addr: unsigned;
                       constant val: unsigned;
                       rsp: out resp_enum_t;
                       constant endian: endian_t := ENDIAN_LITTLE;
                       constant mask: std_ulogic_vector := "")
  is
    variable aw_done, w_done, b_done: boolean := false;
  begin
    assert is_lite(cfg)
      report "configuration is not lite"
      severity failure;
 
    axi_o.ar <= address_defaults(cfg);
    axi_o.r <= handshake_defaults(cfg);
    axi_o.aw <= address(cfg, addr => addr);
    axi_o.w <= write_data(cfg, value => val, endian => endian, strb => mask);
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
                      constant endian: endian_t := ENDIAN_LITTLE;
                      constant mask: std_ulogic_vector := "")
  is
    variable ar_done, r_done: boolean := false;
  begin
    assert is_lite(cfg)
      report "configuration is not lite"
      severity failure;

    axi_o.aw <= address_defaults(cfg);
    axi_o.b <= handshake_defaults(cfg);
    axi_o.w <= write_data_defaults(cfg);
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
  
end package body axi4_mm;
