library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data;
use nsl_logic.bool.all;
use nsl_logic.logic.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

package axi4_mm is

  -- Arbitrary
  constant max_address_width_c: natural := 64;
  constant max_data_bus_width_l2_l2_c: natural := 3;
  constant max_user_width_c: natural := 64;

  constant region_width_c: natural := 4;
  constant max_id_width_c: natural := 64;
  constant max_len_width_c: natural := 8;

  constant size_width_c: natural := 3;
  constant cache_width_c: natural := 4;
  constant prot_width_c: natural := 3;
  constant qos_width_c: natural := 4;
  
  subtype address_t is unsigned(max_address_width_c - 1 downto 0);
  subtype user_t is std_ulogic_vector(max_user_width_c - 1 downto 0);
  subtype strobe_t is std_ulogic_vector(2**max_data_bus_width_l2_l2_c - 1 downto 0);
  subtype data_t is byte_string(2**max_data_bus_width_l2_l2_c-1 downto 0);
  subtype region_t is std_ulogic_vector(region_width_c - 1 downto 0);
  subtype id_t is std_ulogic_vector(max_id_width_c - 1 downto 0);
  subtype len_t is unsigned(max_len_width_c - 1 downto 0);
  subtype size_t is unsigned(size_width_c - 1 downto 0);
  subtype cache_t is std_ulogic_vector(cache_width_c - 1 downto 0);
  subtype prot_t is std_ulogic_vector(prot_width_c - 1 downto 0);
  subtype qos_t is std_ulogic_vector(qos_width_c - 1 downto 0);
  subtype burst_t is std_ulogic_vector(1 downto 0);
  subtype resp_t is std_ulogic_vector(1 downto 0);
  
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

  function to_burst(cfg: config_t; b: burst_t) return burst_enum_t;
  function to_logic(cfg: config_t; b: burst_enum_t) return burst_t;
  function to_lock(cfg: config_t; l: std_ulogic) return lock_enum_t;
  function to_logic(cfg: config_t; l: lock_enum_t) return std_ulogic;
  function to_resp(cfg: config_t; r: resp_t) return resp_enum_t;
  function to_logic(cfg: config_t; r: resp_enum_t) return resp_t;

  type ack_t is
  record
    ready: std_ulogic;
  end record;

  type address_m_t is
  record
    id: id_t;
    addr: address_t;
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

  function address_defaults(cfg: config_t) return address_m_t;
  
  type transaction_t is
  record
    id: id_t;
    addr, saturation, const_mask: address_t;
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
  function transaction(cfg: config_t; addr: address_m_t) return transaction_t;
  function step(cfg: config_t; txn: transaction_t) return transaction_t;

  function id(cfg: config_t; txn: transaction_t) return std_ulogic_vector;
  function address(cfg: config_t; txn: transaction_t;
                   lsb: natural := 0) return unsigned;
  function size_l2(cfg: config_t; txn: transaction_t) return unsigned;
  function lock(cfg: config_t; txn: transaction_t) return lock_enum_t;
  function cache(cfg: config_t; txn: transaction_t) return cache_t;
  function prot(cfg: config_t; txn: transaction_t) return prot_t;
  function qos(cfg: config_t; txn: transaction_t) return qos_t;
  function region(cfg: config_t; txn: transaction_t) return region_t;
  function user(cfg: config_t; txn: transaction_t) return std_ulogic_vector;
  function is_valid(cfg: config_t; txn: transaction_t) return boolean;
  function is_last(cfg: config_t; txn: transaction_t) return boolean;
  function length_m1(cfg: config_t; txn: transaction_t) return unsigned;
  
  subtype address_s_t is ack_t;

  type write_data_m_t is
  record
    data: data_t;
    strb: strobe_t;
    last: std_ulogic;
    user: user_t;
    valid: std_ulogic;
  end record;

  function write_data_defaults(cfg: config_t) return write_data_m_t;

  subtype write_data_s_t is ack_t;

  type write_response_s_t is
  record
    id: id_t;
    resp: resp_t;
    user: user_t;
    valid: std_ulogic;
  end record;

  function write_response_defaults(cfg: config_t) return write_response_s_t;

  subtype write_response_m_t is ack_t;

  type read_data_s_t is
  record
    id: id_t;
    data: data_t;
    resp: resp_t;
    last: std_ulogic;
    user: user_t;
    valid: std_ulogic;
  end record;

  function read_data_defaults(cfg: config_t) return read_data_s_t;

  subtype read_data_m_t is ack_t;

  type m_t is
  record
    aw: address_m_t;
    w: write_data_m_t;
    b: write_response_m_t;
    ar: address_m_t;
    r: read_data_m_t;
  end record;

  type s_t is
  record
    aw: address_s_t;
    w: write_data_s_t;
    b: write_response_s_t;
    ar: address_s_t;
    r: read_data_s_t;
  end record;

  type bus_t is
  record
    m: m_t;
    s: s_t;
  end record;

  type m_vector is array (natural range <>) of m_t;
  type s_vector is array (natural range <>) of s_t;
  type bus_vector is array (natural range <>) of bus_t;

  constant na_suv: std_ulogic_vector := (1 to 0 => '-');
  constant na_u: unsigned := (1 to 0 => '-');

  function is_ready(cfg: config_t; ack: ack_t) return boolean;

  function id(cfg: config_t; addr: address_m_t) return std_ulogic_vector;
  function address(cfg: config_t; addr: address_m_t;
                   lsb: natural := 0) return unsigned;
  function length_m1(cfg: config_t; addr: address_m_t; w: natural) return unsigned;
  function size_l2(cfg: config_t; addr: address_m_t) return unsigned;
  function burst(cfg: config_t; addr: address_m_t) return burst_enum_t;
  function lock(cfg: config_t; addr: address_m_t) return lock_enum_t;
  function cache(cfg: config_t; addr: address_m_t) return cache_t;
  function prot(cfg: config_t; addr: address_m_t) return prot_t;
  function qos(cfg: config_t; addr: address_m_t) return qos_t;
  function region(cfg: config_t; addr: address_m_t) return region_t;
  function user(cfg: config_t; addr: address_m_t) return std_ulogic_vector;
  function is_valid(cfg: config_t; addr: address_m_t) return boolean;

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
                   valid: boolean := true) return address_m_t;
                     
  function data(cfg: config_t; write_data: write_data_m_t) return byte_string;
  function strb(cfg: config_t; write_data: write_data_m_t) return std_ulogic_vector;
  function is_last(cfg: config_t; write_data: write_data_m_t) return boolean;
  function user(cfg: config_t; write_data: write_data_m_t) return std_ulogic_vector;
  function is_valid(cfg: config_t; write_data: write_data_m_t) return boolean;

  function write_data(cfg: config_t;
                      data: byte_string;
                      strb: std_ulogic_vector := na_suv;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_m_t;

  function id(cfg: config_t; write_response: write_response_s_t) return std_ulogic_vector;
  function resp(cfg: config_t; write_response: write_response_s_t) return resp_enum_t;
  function user(cfg: config_t; write_response: write_response_s_t) return std_ulogic_vector;
  function is_valid(cfg: config_t; write_response: write_response_s_t) return boolean;

  function write_response(cfg: config_t;
                          id: std_ulogic_vector := na_suv;
                          resp: resp_enum_t := RESP_OKAY;
                          user: std_ulogic_vector := na_suv;
                          valid: boolean := true) return write_response_s_t;

  function id(cfg: config_t; read_data: read_data_s_t) return std_ulogic_vector;
  function data(cfg: config_t; read_data: read_data_s_t) return byte_string;
  function resp(cfg: config_t; read_data: read_data_s_t) return resp_enum_t;
  function is_last(cfg: config_t; read_data: read_data_s_t) return boolean;
  function user(cfg: config_t; read_data: read_data_s_t) return std_ulogic_vector;
  function is_valid(cfg: config_t; read_data: read_data_s_t) return boolean;

  function read_data(cfg: config_t;
                     id: std_ulogic_vector := na_suv;
                     data: byte_string := null_byte_string;
                     resp: resp_enum_t := RESP_OKAY;
                     user: std_ulogic_vector := na_suv;
                     last: boolean := false;
                     valid: boolean := true) return read_data_s_t;

  function to_string(b: burst_enum_t) return string;
  function to_string(l: lock_enum_t) return string;
  function to_string(r: resp_enum_t) return string;
  function to_string(cfg: config_t) return string;
  function to_string(cfg: config_t; a: address_m_t) return string;
  function to_string(cfg: config_t; t: transaction_t) return string;
  function to_string(cfg: config_t; w: write_data_m_t) return string;
  function to_string(cfg: config_t; w: write_response_s_t) return string;
  function to_string(cfg: config_t; r: read_data_s_t) return string;
  
end package;

package body axi4_mm is

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

  function id(cfg: config_t; addr: address_m_t) return std_ulogic_vector
  is
  begin
    return addr.id(cfg.id_width-1 downto 0);
  end function;

  function address(cfg: config_t; addr: address_m_t;
                   lsb: natural := 0) return unsigned
  is
  begin
    return addr.addr(cfg.address_width-1 downto lsb);
  end function;

  function length_m1(cfg: config_t; addr: address_m_t; w: natural) return unsigned
  is
  begin
    if cfg.len_width = 0 then
      return resize("1", w);
    else
      return resize(addr.len_m1(cfg.len_width-1 downto 0), w);
    end if;
  end function;

  function size_l2(cfg: config_t; addr: address_m_t) return unsigned
  is
  begin
    if cfg.has_size then
      return addr.size_l2(size_width_c-1 downto 0);
    else
      return to_unsigned(cfg.data_bus_width_l2, size_width_c);
    end if;
  end function;

  function burst(cfg: config_t; addr: address_m_t) return burst_enum_t
  is
  begin
    if cfg.has_burst then
      return to_burst(cfg, addr.burst);
    else
      return BURST_INCR;
    end if;
  end function;

  function lock(cfg: config_t; addr: address_m_t) return lock_enum_t
  is
  begin
    return to_lock(cfg, addr.lock);
  end function;

  function cache(cfg: config_t; addr: address_m_t) return cache_t
  is
  begin
    if cfg.has_cache then
      return addr.cache;
    else
      return "0000";
    end if;
  end function;

  function prot(cfg: config_t; addr: address_m_t) return prot_t
  is
  begin
    return addr.prot;
  end function;

  function qos(cfg: config_t; addr: address_m_t) return qos_t
  is
  begin
    if cfg.has_qos then
      return addr.qos;
    else
      return "0000";
    end if;
  end function;

  function region(cfg: config_t; addr: address_m_t) return region_t
  is
  begin
    if cfg.has_region then
      return addr.region;
    else
      return "0000";
    end if;
  end function;

  function user(cfg: config_t; addr: address_m_t) return std_ulogic_vector
  is
  begin
    return addr.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; addr: address_m_t) return boolean
  is
  begin
    return addr.valid = '1';
  end function;

  function is_ready(cfg: config_t; ack: ack_t) return boolean
  is
  begin
    return ack.ready = '1';
  end function;

  function data(cfg: config_t; write_data: write_data_m_t) return byte_string
  is
  begin
    return write_data.data(2**cfg.data_bus_width_l2-1 downto 0);
  end function;

  function strb(cfg: config_t; write_data: write_data_m_t) return std_ulogic_vector
  is
  begin
    return write_data.strb(2**cfg.data_bus_width_l2-1 downto 0);
  end function;

  function is_last(cfg: config_t; write_data: write_data_m_t) return boolean
  is
  begin
    return write_data.last = '1';
  end function;

  function user(cfg: config_t; write_data: write_data_m_t) return std_ulogic_vector
  is
  begin
    return write_data.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; write_data: write_data_m_t) return boolean
  is
  begin
    return write_data.valid = '1';
  end function;

  function id(cfg: config_t; write_response: write_response_s_t) return std_ulogic_vector
  is
  begin
    return write_response.id(cfg.id_width-1 downto 0);
  end function;

  function resp(cfg: config_t; write_response: write_response_s_t) return resp_enum_t
  is
  begin
    return to_resp(cfg, write_response.resp);
  end function;

  function user(cfg: config_t; write_response: write_response_s_t) return std_ulogic_vector
  is
  begin
    return write_response.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; write_response: write_response_s_t) return boolean
  is
  begin
    return write_response.valid = '1';
  end function;

  function id(cfg: config_t; read_data: read_data_s_t) return std_ulogic_vector
  is
  begin
    return read_data.id(cfg.id_width-1 downto 0);
  end function;

  function data(cfg: config_t; read_data: read_data_s_t) return byte_string
  is
  begin
    return read_data.data(2**cfg.data_bus_width_l2-1 downto 0);
  end function;

  function resp(cfg: config_t; read_data: read_data_s_t) return resp_enum_t
  is
  begin
    return to_resp(cfg, read_data.resp);
  end function;

  function is_last(cfg: config_t; read_data: read_data_s_t) return boolean
  is
  begin
    return read_data.last = '1';
  end function;

  function user(cfg: config_t; read_data: read_data_s_t) return std_ulogic_vector
  is
  begin
    return read_data.user(cfg.user_width-1 downto 0);
  end function;

  function is_valid(cfg: config_t; read_data: read_data_s_t) return boolean
  is
  begin
    return read_data.valid = '1';
  end function;

  function address_defaults(cfg: config_t) return address_m_t
  is
    variable ret: address_m_t;
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
    
  function write_data_defaults(cfg: config_t) return write_data_m_t
  is
    variable ret: write_data_m_t;
  begin
    ret.data := (others => (dontcare_byte_c));
    ret.strb := (others => '1');
    ret.last := '0';
    ret.user := (others => '-');
    ret.valid := '0';

    return ret;
  end function;

  function write_response_defaults(cfg: config_t) return write_response_s_t
  is
    variable ret: write_response_s_t;
  begin
    ret.id := (others => '0');
    ret.resp := "00";
    ret.user := (others => '-');
    ret.valid := '0';

    return ret;
  end function;

  function read_data_defaults(cfg: config_t) return read_data_s_t
  is
    variable ret: read_data_s_t;
  begin
    ret.id := (others => '0');
    ret.data := (others => (dontcare_byte_c));
    ret.resp := "00";
    ret.last := '0';
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
                   valid: boolean := true) return address_m_t
  is
    variable ret : address_m_t := address_defaults(cfg);
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
                      data: byte_string;
                      strb: std_ulogic_vector := na_suv;
                      user: std_ulogic_vector := na_suv;
                      last: boolean := false;
                      valid: boolean := true) return write_data_m_t
  is
    variable ret: write_data_m_t := write_data_defaults(cfg);
  begin
    if data'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = data'length
        report "Bad data vector passed"
        severity failure;
      ret.data(data'length-1 downto 0) := data;
    end if;

    if strb'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = strb'length
        report "Bad strobe vector passed"
        severity failure;
      ret.strb(strb'length-1 downto 0) := strb;
    end if;

    if cfg.user_width /= 0 and user'length /= 0 then
      assert cfg.user_width = user'length
        report "Bad USER vector passed"
        severity failure;
      ret.user(user'length-1 downto 0) := user;
    end if;

    ret.valid := to_logic(valid);
    ret.last := to_logic(last);

    return ret;
  end function;

  function write_response(cfg: config_t;
                          id: std_ulogic_vector := na_suv;
                          resp: resp_enum_t := RESP_OKAY;
                          user: std_ulogic_vector := na_suv;
                          valid: boolean := true) return write_response_s_t
  is
    variable ret: write_response_s_t := write_response_defaults(cfg);
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
                     data: byte_string := null_byte_string;
                     resp: resp_enum_t := RESP_OKAY;
                     user: std_ulogic_vector := na_suv;
                     last: boolean := false;
                     valid: boolean := true) return read_data_s_t
  is
    variable ret: read_data_s_t := read_data_defaults(cfg);
  begin
    if data'length /= 0 then
      assert 2**cfg.data_bus_width_l2 = data'length
        report "Bad data vector passed"
        severity failure;
      ret.data(data'length-1 downto 0) := data;
    end if;

    ret.resp := to_logic(cfg, resp);

    if cfg.user_width /= 0 and user'length /= 0 then
      assert cfg.user_width = user'length
        report "Bad USER vector passed"
        severity failure;
      ret.user(user'length-1 downto 0) := user;
    end if;

    ret.last := to_logic(last);
    ret.valid := to_logic(valid);

    return ret;
  end function;

  function address_const_mask(cfg: config_t; addr: address_m_t) return address_t
  is
    variable ret: address_t := (others => '0');
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

  function address_saturation_mask(cfg: config_t; addr: address_m_t) return address_t
  is
    variable ret: address_t := (others => '0');
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

  function transaction(cfg: config_t; addr: address_m_t) return transaction_t
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
    constant addr1: address_t := (others => '1');

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

  function to_string(cfg: config_t; a: address_m_t) return string
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
        &if_else(is_last(cfg, t), " last", "")
        &">";
    else
      return "<Txn ->";
    end if;
  end;

  function to_string(cfg: config_t; w: write_data_m_t) return string
  is
  begin
    if is_valid(cfg, w) then
      return "<WData"
        &" "&to_string(data(cfg, w))
        &" S:"&to_string(strb(cfg, w))
        &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, w)), "")
        &if_else(w.last = '1', " last", "")
        &">";
    else
      return "<WData ->";
    end if;
  end;

  function to_string(cfg: config_t; w: write_response_s_t) return string
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

  function to_string(cfg: config_t; r: read_data_s_t) return string
  is
  begin
    if is_valid(cfg, r) then
      return "<RRsp"
        &" "&to_string(resp(cfg, r))
        &if_else(cfg.id_width>0, " I:"&to_string(id(cfg, r)), "")
        &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, r)), "")
        &if_else(r.last = '1', " last", "")
        &">";
    else
      return "<WRsp ->";
    end if;
  end;
  
end package body axi4_mm;