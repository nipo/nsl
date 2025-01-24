library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data, work;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

-- This package defines AXI4-Stream bus signals and accessors.
--
-- As this is cumbersome (and not yet really portable) to have
-- generics in packages for VHDL, do this another way:
--
-- Package defines the worst case of 64-bit srtobe, id, dest, user.
-- Signals will convey this worst case.  Then modules may use only a
-- subset.  In order to agree on the subset they use, encapsutate
-- parameters and pass them as generics to every component.
--
-- By using accessors for setting and for extracting useful data out
-- of bus signals, we ensure bits that are not used in the current
-- configuration are never set / read, leaving opportunity to
-- optimizer to strip them.
package axi4_stream is

  -- Arbitrary
  constant max_data_width_c: natural := 64;
  constant max_id_width_c: natural := 64;
  constant max_dest_width_c: natural := 64;
  constant max_user_width_c: natural := 64;
  
  subtype strobe_t is std_ulogic_vector(0 to max_data_width_c - 1);
  subtype data_t is byte_string(0 to max_data_width_c - 1);
  subtype user_t is std_ulogic_vector(max_user_width_c - 1 downto 0);
  subtype id_t is std_ulogic_vector(max_id_width_c - 1 downto 0);
  subtype dest_t is std_ulogic_vector(max_dest_width_c - 1 downto 0);

  -- Configuration parameters for an AXI-Stream interface
  type config_t is
  record
    data_width: natural range 0 to max_data_width_c;
    user_width: natural range 0 to max_user_width_c;
    id_width: natural range 0 to max_id_width_c;
    dest_width: natural range 0 to max_dest_width_c;
    has_keep: boolean;
    has_strobe: boolean;
    has_ready: boolean;
    has_last: boolean;
  end record;

  -- Configuration parameters factory with sensible defaults
  function config(
    bytes: natural range 0 to max_data_width_c;
    user: natural range 0 to max_user_width_c := 0;
    id: natural range 0 to max_id_width_c := 0;
    dest: natural range 0 to max_dest_width_c := 0;
    keep: boolean := false;
    strobe: boolean := false;
    ready: boolean := true;
    last: boolean := false) return config_t;

  -- Master-driven interface
  type master_t is
  record
    id: id_t;
    data: data_t;
    strobe: strobe_t;
    keep: strobe_t;
    dest: dest_t;
    user: user_t;
    valid: std_ulogic;
    last: std_ulogic;
  end record;

  -- Slave-driven interface
  type slave_t is
  record
    ready: std_ulogic;
  end record;

  -- Bus
  type bus_t is
  record
    m: master_t;
    s: slave_t;
  end record;

  type master_vector is array (natural range <>) of master_t;
  type slave_vector is array (natural range <>) of slave_t;
  type bus_vector is array (natural range <>) of bus_t;

  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');

  function is_valid(cfg: config_t; m: master_t) return boolean;
  function is_last(cfg: config_t; m: master_t; default: boolean := true) return boolean;
  function is_ready(cfg: config_t; s: slave_t) return boolean;
  function bytes(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;
  function value(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return unsigned;
  function strobe(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  function keep(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  function user(cfg: config_t; m: master_t) return std_ulogic_vector;
  function id(cfg: config_t; m: master_t) return std_ulogic_vector;
  function dest(cfg: config_t; m: master_t) return std_ulogic_vector;

  function transfer_defaults(cfg: config_t) return master_t;

  function transfer(cfg: config_t;
                    bytes: byte_string;
                    strobe: std_ulogic_vector := na_suv;
                    keep: std_ulogic_vector := na_suv;
                    order: byte_order_t := BYTE_ORDER_INCREASING;
                    id: std_ulogic_vector := na_suv;
                    user: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid : boolean := true;
                    last : boolean := false) return master_t;

  function transfer(cfg: config_t;
                    value: unsigned;
                    endian: endian_t := ENDIAN_LITTLE;
                    id: std_ulogic_vector := na_suv;
                    user: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid : boolean := true;
                    last : boolean := false) return master_t;

  function accept(cfg: config_t;
                  ready : boolean := false) return slave_t;

  function transfer(cfg: config_t;
                    src_cfg: config_t;
                    src: master_t) return master_t;

  function transfer(cfg: config_t;
                    src: master_t;
                    force_valid : boolean := false;
                    force_last : boolean := false;
                    valid : boolean := false;
                    last : boolean := false) return master_t;

  -- AXI-Stream packing tools
  --
  -- These are helpers to pack a subset of the AXI-Stream master
  -- signals to a vector.
  
  -- This calculates the needed vector size for storing all the selected
  -- elements of the master signals.
  --
  -- Elements may be any group of characters among "idskouvl" ('o' is for dest).
  function vector_length(cfg: config_t;
                         elements: string) return natural;

  -- Pack an AXI-Stream mater interface using items given in elements.
  function vector_pack(cfg: config_t;
                       elements: string;
                       m: master_t) return std_ulogic_vector;

  -- Unpack an AXI-Stream mater interface using items given in elements.
  function vector_unpack(cfg: config_t;
                         elements: string;
                         v: std_ulogic_vector) return master_t;
  
  -- Input configuration must not have "last", output configuration
  -- must have "last". Input and output configuration should have all
  -- other parameters equal.
  --
  -- This component will flush packet after either max_packet_length_c
  -- count of transfers or when input is idle more than max_idle_c
  -- clock cycles.
  component axi4_stream_flusher is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      max_packet_length_c : natural;
      max_idle_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- In and out configs shall be identical apart from data width.
  -- There should be an integer factor from in to out, either by
  -- division or multiplication.
  component axi4_stream_width_adapter is
    generic(
      in_config_c : config_t;
      out_config_c : config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;
  
  component axi4_stream_dumper is
    generic(
      config_c : config_t;
      prefix_c : string := "AXIS"
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      bus_i : in bus_t
      );
  end component;

  component axi4_stream_header_inserter is
    generic(
      config_c : config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      header_i : in byte_string;
      header_strobe_o : out std_ulogic;
      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  component axi4_stream_header_extractor is
    generic(
      config_c : config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      header_o : out byte_string;
      header_strobe_o : out std_ulogic;
      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  
  function to_string(cfg: config_t) return string;
  function to_string(cfg: config_t; a: master_t) return string;
  function to_string(cfg: config_t; a: slave_t) return string;

  -- Simulation helper function to issue a write transaction to an
  -- AXI4-Stream bus.
  procedure send(constant cfg: config_t;
                 signal clock: in std_ulogic;
                 signal stream_i: in slave_t;
                 signal stream_o: out master_t;
                 constant beat: master_t);

  procedure send(constant cfg: config_t;
                 signal clock: in std_ulogic;
                 signal stream_i: in slave_t;
                 signal stream_o: out master_t;
                 constant bytes: byte_string;
                 constant strobe: std_ulogic_vector := na_suv;
                 constant keep: std_ulogic_vector := na_suv;
                 constant order: byte_order_t := BYTE_ORDER_INCREASING;
                 constant id: std_ulogic_vector := na_suv;
                 constant user: std_ulogic_vector := na_suv;
                 constant dest: std_ulogic_vector := na_suv;
                 constant valid : boolean := true;
                 constant last : boolean := false);

  procedure receive(constant cfg: config_t;
                    signal clock: in std_ulogic;
                    signal stream_i: in master_t;
                    signal stream_o: out slave_t;
                    variable beat: out master_t);

  procedure packet_send(constant cfg: config_t;
                        signal clock: in std_ulogic;
                        signal stream_i: in slave_t;
                        signal stream_o: out master_t;
                        constant packet: byte_string;
                        constant strobe: std_ulogic_vector := na_suv;
                        constant keep: std_ulogic_vector := na_suv;
                        constant id: std_ulogic_vector := na_suv;
                        constant user: std_ulogic_vector := na_suv;
                        constant dest: std_ulogic_vector := na_suv);

  procedure packet_receive(constant cfg: config_t;
                           signal clock: in std_ulogic;
                           signal stream_i: in master_t;
                           signal stream_o: out slave_t;
                           variable packet : out byte_stream;
                           variable id : out std_ulogic_vector;
                           variable user : out std_ulogic_vector;
                           variable dest : out std_ulogic_vector);

  -- Beat manipulation functions
  --
  -- Shift data vector low, inserting bytes / strobe / keep in the
  -- high-order
  function shift_low(cfg: config_t;
                     beat: master_t;
                     count: natural;
                     bytes: byte_string := null_byte_string;
                     strobe: std_ulogic_vector := na_suv;
                     keep: std_ulogic_vector := na_suv) return master_t;
  -- Shift data vector high, inserting bytes / strobe / keep in the
  -- low-order
  function shift_high(cfg: config_t;
                      beat: master_t;
                      count: natural;
                      bytes: byte_string := null_byte_string;
                      strobe: std_ulogic_vector := na_suv;
                      keep: std_ulogic_vector := na_suv) return master_t;
  

  -- Helper for receiving/sending multi-beat buffers in an abstract way
  type buffer_config_t is
  record
    stream_config: config_t;
    data_width: natural range 1 to data_t'length;
    part_count: natural range 1 to data_t'length;
  end record;    

  type buffer_t is
  record
    data: data_t;
    to_go: integer range 0 to data_t'length;
  end record;

  function to_string(cfg: buffer_config_t) return string;
  function to_string(cfg: buffer_config_t; b: buffer_t) return string;

  -- This spawns a buffer configuration from a stream configuration and buffer
  -- width. It is an error if byte count is not a multiple of stream data width.
  function buffer_config(cfg: config_t; byte_count: natural) return buffer_config_t;
  -- Tells whether buffer will be complete after one shift operation is performed
  function is_last(cfg: buffer_config_t; b: buffer_t) return boolean;
  -- Yields an buffer context with (optional data) and a reset counter of shifts
  -- This can be used before either sending or receiving.
  function reset(cfg: buffer_config_t;
                 b: byte_string := null_byte_string;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return buffer_t;
  -- Shifts one step of the buffer by ingressing (optional) data
  -- vector. Counts one step less to do. If not given, dontcares are
  -- used. This can be used for either sending or receiving.
  function shift(cfg: buffer_config_t;
                 b: buffer_t;
                 data: byte_string := null_byte_string) return buffer_t;
  -- Ingresses one beat from master interface to the buffer. Returns future
  -- buffer value.
  function shift(cfg: buffer_config_t; b: buffer_t; beat: master_t) return buffer_t;
  -- Yields next data chunk from current buffer state.
  function next_bytes(cfg: buffer_config_t; b: buffer_t) return byte_string;
  -- Yields next strb mask from current buffer state.
  function next_strb(cfg: buffer_config_t; b: buffer_t) return std_ulogic_vector;
  -- Yields master interface from current buffer contents.  Last is
  -- only taken into account when beat is the last one of the buffer
  -- sending / receiving, otherwise, it is forcibly set to false.
  -- Semantically, this allows user to send extra data after the
  -- buffer contents if needed.
  function next_beat(cfg: buffer_config_t; b: buffer_t;
                     id: std_ulogic_vector := na_suv;
                     user: std_ulogic_vector := na_suv;
                     dest: std_ulogic_vector := na_suv;
                     last : boolean := true) return master_t;
  -- Retrieves the full buffer
  function bytes(cfg: buffer_config_t; b: buffer_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;

end package;

package body axi4_stream is

  function is_valid(cfg: config_t; m: master_t) return boolean
  is
  begin
    return m.valid = '1';
  end function;

  function is_last(cfg: config_t; m: master_t; default: boolean := true) return boolean
  is
  begin
    if cfg.has_last then
      return m.last = '1';
    else
      return default;
    end if;
  end function;

  function is_ready(cfg: config_t; s: slave_t) return boolean
  is
  begin
    if cfg.has_ready then
      return s.ready = '1';
    else
      return true;
    end if;
  end function;

  function bytes(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
  begin
    if order = BYTE_ORDER_INCREASING then
      return m.data(0 to cfg.data_width-1);
    else
      return reverse(m.data(0 to cfg.data_width-1));
    end if;
  end function;

  function value(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
  begin
    return from_endian(bytes(cfg, m), endian);
  end function;

  function strobe(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
  begin
    if not cfg.has_strobe then
      return keep(cfg, m);
    end if;

    return reorder_mask(m.strobe(0 to cfg.data_width-1), order);
  end function;

  function keep(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
    constant default: std_ulogic_vector(cfg.data_width-1 downto 0) := (others => '1');
  begin
    if not cfg.has_keep then
      return default;
    end if;

    return reorder_mask(m.keep(0 to cfg.data_width-1), order);
  end function;

  function user(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return m.user(cfg.user_width-1 downto 0);
  end function;

  function id(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return m.id(cfg.id_width-1 downto 0);
  end function;

  function dest(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return m.dest(cfg.dest_width-1 downto 0);
  end function;

  function transfer_defaults(cfg: config_t) return master_t
  is
    variable ret: master_t;
  begin
    ret.keep := (others => '-');
    ret.keep(0 to cfg.data_width-1) := (others => '1');
    ret.strobe := (others => '-');
    ret.strobe(0 to cfg.data_width-1) := (others => '1');
    ret.data := (others => (others => '-'));
    ret.user := (others => '-');
    ret.dest := (others => '-');
    ret.id := (others => '-');
    ret.valid := '0';

    if not cfg.has_last then
      ret.last := '-';
    else
      ret.last := '1';
    end if;

    return ret;
  end function;

  function transfer(cfg: config_t;
                    bytes: byte_string;
                    strobe: std_ulogic_vector := na_suv;
                    keep: std_ulogic_vector := na_suv;
                    order: byte_order_t := BYTE_ORDER_INCREASING;
                    id: std_ulogic_vector := na_suv;
                    user: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid : boolean := true;
                    last : boolean := false) return master_t
  is
    variable ret: master_t := transfer_defaults(cfg);
  begin
    if cfg.has_keep and cfg.data_width /= 0 then
      if keep'length /= 0 then
        assert keep'length = cfg.data_width
          report "Bad keep length"
          severity failure;
        if order = BYTE_ORDER_INCREASING then
          ret.keep(0 to cfg.data_width-1) := keep;
        else
          ret.keep(0 to cfg.data_width-1) := bitswap(keep);
        end if;
      else
        ret.keep(0 to cfg.data_width-1) := (others => '1');
      end if;
    end if;

    if cfg.has_strobe and cfg.data_width /= 0 then
      if strobe'length /= 0 then
        assert strobe'length = cfg.data_width
          report "Bad strobe length"
          severity failure;
        if order = BYTE_ORDER_INCREASING then
          ret.strobe(0 to cfg.data_width-1) := strobe;
        else
          ret.strobe(0 to cfg.data_width-1) := bitswap(strobe);
        end if;
      else
        ret.strobe(0 to cfg.data_width-1) := (others => '1');
      end if;
    end if;

    if cfg.data_width /= 0 then
      assert bytes'length = cfg.data_width
        report "Bad data length"
        severity failure;
      if order = BYTE_ORDER_INCREASING then
        ret.data(0 to cfg.data_width-1) := bytes;
      else
        ret.data(0 to cfg.data_width-1) := reverse(bytes);
      end if;
    end if;

    if cfg.user_width /= 0 then
      assert user'length = cfg.user_width
        report "Bad user length"
        severity failure;
      ret.user(cfg.user_width-1 downto 0) := user;
    end if;

    if cfg.dest_width /= 0 then
      assert dest'length = cfg.dest_width
        report "Bad dest length"
        severity failure;
      ret.dest(cfg.dest_width-1 downto 0) := dest;
    end if;

    if cfg.id_width /= 0 then
      assert id'length = cfg.id_width
        report "Bad id length"
        severity failure;
      ret.id(cfg.id_width-1 downto 0) := id;
    end if;

    if valid then
      ret.valid := '1';
    end if;

    if cfg.has_last then
      if last then
        ret.last := '1';
      else
        ret.last := '0';
      end if;
    end if;

    return ret;
  end function;

  function transfer(cfg: config_t;
                    value: unsigned;
                    endian: endian_t := ENDIAN_LITTLE;
                    id: std_ulogic_vector := na_suv;
                    user: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid : boolean := true;
                    last : boolean := false) return master_t
  is
  begin
    return transfer(cfg => cfg,
                    bytes => to_endian(value, endian),
                    id => id,
                    user => user,
                    dest => dest,
                    valid => valid,
                    last => last);
  end function; 

  function transfer(cfg: config_t;
                    src_cfg: config_t;
                    src: master_t) return master_t
  is
    variable ret: master_t := transfer_defaults(cfg);
    constant id_w : integer := nsl_math.arith.min(cfg.id_width, src_cfg.id_width);
    constant user_w : integer := nsl_math.arith.min(cfg.user_width, src_cfg.user_width);
    constant dest_w : integer := nsl_math.arith.min(cfg.dest_width, src_cfg.dest_width);
  begin
    assert src_cfg.data_width <= cfg.data_width
      report "Can only copy transfer to larger width"
      severity failure;

    if cfg.has_keep then
      ret.keep(0 to cfg.data_width-1) := (others => '0');
      ret.keep(0 to src_cfg.data_width-1) := keep(src_cfg, src);
    end if;
    if cfg.has_strobe then
      ret.strobe(0 to cfg.data_width-1) := (others => '0');
      ret.strobe(0 to src_cfg.data_width-1) := strobe(src_cfg, src);
    end if;
    ret.data(0 to src_cfg.data_width-1) := bytes(src_cfg, src);

    ret.id(cfg.id_width-1 downto 0) := (others => '0');
    ret.id(id_w-1 downto 0) := src.id(id_w-1 downto 0);
    ret.user(cfg.user_width-1 downto 0) := (others => '0');
    ret.user(user_w-1 downto 0) := src.user(user_w-1 downto 0);
    ret.dest(cfg.dest_width-1 downto 0) := (others => '0');
    ret.dest(dest_w-1 downto 0) := src.dest(dest_w-1 downto 0);
    ret.valid := src.valid;
    if cfg.has_last then
      ret.last := to_logic(is_last(src_cfg, src));
    end if;

    return ret;
  end function;

  function transfer(cfg: config_t;
                    src: master_t;
                    force_valid : boolean := false;
                    force_last : boolean := false;
                    valid : boolean := false;
                    last : boolean := false) return master_t
  is
    variable ret: master_t := src;
  begin
    if force_valid then
      ret.valid := to_logic(valid);
    end if;

    if force_last and cfg.has_last then
      ret.last := to_logic(last);
    end if;

    return ret;
  end function;

  function accept(cfg: config_t;
                  ready : boolean := false) return slave_t
  is
    variable ret : slave_t;
  begin
    if not cfg.has_ready then
      ret.ready := '-';
    elsif ready then
      ret.ready := '1';
    else
      ret.ready := '0';
    end if;

    return ret;
  end function;

  function config(
    bytes: natural range 0 to max_data_width_c;
    user: natural range 0 to max_user_width_c := 0;
    id: natural range 0 to max_id_width_c := 0;
    dest: natural range 0 to max_dest_width_c := 0;
    keep: boolean := false;
    strobe: boolean := false;
    ready: boolean := true;
    last: boolean := false) return config_t
  is
  begin
    return config_t'(
      data_width => bytes,
      user_width => user,
      id_width => id,
      dest_width => dest,
      has_keep => keep,
      has_strobe => strobe,
      has_ready => ready,
      has_last => last
      );
  end function;

  function vector_length(cfg: config_t;
                         elements: string) return natural
  is
    variable ret : natural := 0;
  begin
    ret := ret + if_else(strchr(elements, 'i') = -1, 0, cfg.id_width);
    ret := ret + if_else(strchr(elements, 'd') = -1, 0, cfg.data_width * 8);
    ret := ret + if_else(strchr(elements, 's') /= -1 and cfg.has_strobe, cfg.data_width, 0);
    ret := ret + if_else(strchr(elements, 'k') /= -1 and cfg.has_keep, cfg.data_width, 0);
    ret := ret + if_else(strchr(elements, 'o') = -1, 0, cfg.dest_width);
    ret := ret + if_else(strchr(elements, 'u') = -1, 0, cfg.user_width);
    ret := ret + if_else(strchr(elements, 'v') = -1, 0, 1);
    ret := ret + if_else(strchr(elements, 'l') /= -1 and cfg.has_last, 1, 0);
    return ret;
  end function;
  
  function vector_pack(cfg: config_t;
                       elements: string;
                       m: master_t) return std_ulogic_vector
  is
    constant s: natural := vector_length(cfg, elements);
    variable ret : std_ulogic_vector(0 to s-1);
    variable point : natural range 0 to s := 0;
  begin
    for ei in elements'range
    loop
      case elements(ei) is
        when 'i' =>
          ret(point to point+cfg.id_width-1) := id(cfg, m);
          point := point + cfg.id_width;
        when 'd' =>
          ret(point to point+cfg.data_width*8-1) := std_ulogic_vector(value(cfg, m, ENDIAN_BIG));
          point := point + cfg.data_width * 8;
        when 's' =>
          if cfg.has_strobe then
            ret(point to point+cfg.data_width-1) := strobe(cfg, m);
            point := point + cfg.data_width;
          end if;
        when 'k' =>
          if cfg.has_keep then
            ret(point to point+cfg.data_width-1) := keep(cfg, m);
            point := point + cfg.data_width;
          end if;
        when 'o' =>
          ret(point to point+cfg.dest_width-1) := dest(cfg, m);
          point := point + cfg.dest_width;
        when 'u' =>
          ret(point to point+cfg.user_width-1) := user(cfg, m);
          point := point + cfg.user_width;
        when 'v' =>
          ret(point) := to_logic(is_valid(cfg, m));
          point := point + 1;
        when 'l' =>
          if cfg.has_last then
            ret(point) := to_logic(is_last(cfg, m));
            point := point + 1;
          end if;
        when others =>
          assert false
            report "Bad key, must be one of [idskouvl]"
            severity failure;
      end case;
    end loop;

    assert ret'length = point
      report "Final size does not match vector. Using a key twice ?"
      severity failure;

    return ret;
  end function;

  function vector_unpack(cfg: config_t;
                         elements: string;
                         v: std_ulogic_vector) return master_t
  is
    constant s: natural := vector_length(cfg, elements);
    alias vv : std_ulogic_vector(0 to s-1) is v;
    variable point : natural range 0 to s := 0;
    variable ret : master_t := transfer_defaults(cfg);
  begin
    assert vv'length = s
      report "Bad vector length for packing elements"
      severity failure;

    for ei in elements'range
    loop
      case elements(ei) is
        when 'i' =>
          ret.id(cfg.id_width-1 downto 0) := vv(point to point+cfg.id_width-1);
          point := point + cfg.id_width;
        when 'd' =>
          ret.data(0 to cfg.data_width-1) := to_be(unsigned(vv(point to point+cfg.data_width*8-1)));
          point := point + cfg.data_width * 8;
        when 's' =>
          if cfg.has_strobe then
            ret.strobe(0 to cfg.data_width-1) := vv(point to point+cfg.data_width-1);
            point := point + cfg.data_width;
          end if;
        when 'k' =>
          if cfg.has_keep then
            ret.keep(0 to cfg.data_width-1) := vv(point to point+cfg.data_width-1);
            point := point + cfg.data_width;
          end if;
        when 'o' =>
          ret.dest(cfg.dest_width-1 downto 0) := vv(point to point+cfg.dest_width-1);
          point := point + cfg.dest_width;
        when 'u' =>
          ret.user(cfg.user_width-1 downto 0) := vv(point to point+cfg.user_width-1);
          point := point + cfg.user_width;
        when 'v' =>
          ret.valid := vv(point);
          point := point + 1;
        when 'l' =>
          if cfg.has_last then
            ret.last := vv(point);
            point := point + 1;
          end if;
        when others =>
          assert false
            report "Bad key, must be one of [idskouvl]"
            severity failure;
      end case;
    end loop;

    assert vv'length = point
      report "Final size does not match vector. Using a key twice ?"
      severity failure;

    return ret;
  end function;

  function to_string(cfg: config_t) return string
  is
  begin
    return "<AXI4S"
      &" D"&to_string(cfg.data_width)
      &if_else(cfg.dest_width>0, " O"&to_string(cfg.dest_width), "")
      &if_else(cfg.user_width>0, " U"&to_string(cfg.user_width), "")
      &if_else(cfg.id_width>0, " I"&to_string(cfg.id_width), "")
      &if_else(cfg.has_last, " L", "")
      &if_else(cfg.has_keep, " K", "")
      &if_else(cfg.has_strobe, " S", "")
      &if_else(cfg.has_ready, " R", "")
      &">";
  end function;
  
  function to_string(cfg: config_t; a: master_t) return string
  is
  begin
    return "<AXISm"
      &" "&to_string(masked(bytes(cfg, a), strobe(cfg, a)), mask => keep(cfg, a), masked_out_value => "==")
      &if_else(cfg.id_width>0, " I:"&to_string(id(cfg, a)), "")
      &if_else(cfg.user_width>0, " U:"&to_string(user(cfg, a)), "")
      &if_else(cfg.dest_width>0, " O:"&to_string(dest(cfg, a)), "")
      &if_else(is_last(cfg, a), " last", "")
      &">";
  end function;

  function to_string(cfg: config_t; a: slave_t) return string
  is
  begin
    return "<AXISs"
      &if_else(is_ready(cfg, a), " ready", " stall")
      &">";
  end function;

  procedure send(constant cfg: config_t;
                 signal clock: in std_ulogic;
                 signal stream_i: in slave_t;
                 signal stream_o: out master_t;
                 constant beat: master_t)
  is
    variable done: boolean := false;
  begin
    assert is_valid(cfg, beat)
      report "Cannot send a non-valid beat"
      severity failure;
    
    stream_o <= beat;
    while not done
      loop
      wait until rising_edge(clock);
      done := is_ready(cfg, stream_i);

      wait until falling_edge(clock);
    end loop;

    stream_o <= transfer_defaults(cfg);
  end procedure;

  procedure send(constant cfg: config_t;
                 signal clock: in std_ulogic;
                 signal stream_i: in slave_t;
                 signal stream_o: out master_t;
                 constant bytes: byte_string;
                 constant strobe: std_ulogic_vector := na_suv;
                 constant keep: std_ulogic_vector := na_suv;
                 constant order: byte_order_t := BYTE_ORDER_INCREASING;
                 constant id: std_ulogic_vector := na_suv;
                 constant user: std_ulogic_vector := na_suv;
                 constant dest: std_ulogic_vector := na_suv;
                 constant valid : boolean := true;
                 constant last : boolean := false)
  is
  begin
    send(cfg, clock, stream_i, stream_o, transfer(cfg,
                                                  bytes => bytes,
                                                  strobe => strobe,
                                                  keep => keep,
                                                  order => order,
                                                  id => id,
                                                  user => user,
                                                  dest => dest,
                                                  valid => valid,
                                                  last => last));
  end procedure;

  procedure receive(constant cfg: config_t;
                    signal clock: in std_ulogic;
                    signal stream_i: in master_t;
                    signal stream_o: out slave_t;
                    variable beat: out master_t)
  is
    variable done: boolean := false;
  begin
    stream_o <= accept(cfg, true);
    
    while not done
    loop
      wait until rising_edge(clock);
      if is_valid(cfg, stream_i) then
        done := true;
        beat := stream_i;
      end if;

      wait until falling_edge(clock);
      if done then
        stream_o <= accept(cfg, false);
      end if;
    end loop;
  end procedure;

  function shift_low(cfg: config_t;
                     beat: master_t;
                     count: natural;
                     bytes: byte_string := null_byte_string;
                     strobe: std_ulogic_vector := na_suv;
                     keep: std_ulogic_vector := na_suv) return master_t
  is
    constant data_dontcare_c : byte_string(0 to count-1) := (others => dontcare_byte_c);
    constant en_dontcare_c : std_ulogic_vector(0 to count-1) := (others => '-');
    constant en_ones_c : std_ulogic_vector(0 to count-1) := (others => '1');
    variable d : byte_string(0 to cfg.data_width-1) := (others => dontcare_byte_c);
    variable k : std_ulogic_vector(0 to cfg.data_width-1);
    variable s : std_ulogic_vector(0 to cfg.data_width-1);
  begin
    d := work.axi4_stream.bytes(cfg, beat);
    k := work.axi4_stream.keep(cfg, beat);
    s := work.axi4_stream.strobe(cfg, beat);

    if bytes'length /= 0 then
      assert bytes'length = count
        report "Bad data vector passed"
        severity failure;
      d := d(count to d'right) & bytes;
    else
      d := d(count to d'right) & data_dontcare_c;
    end if;

    if not cfg.has_keep then
      k := k(count to k'right) & en_dontcare_c;
    elsif keep'length /= 0 then
      assert keep'length = count
        report "Bad keep vector passed"
        severity failure;
      k := k(count to k'right) & keep;
    else
      k := k(count to k'right) & en_ones_c;
    end if;

    if not cfg.has_strobe then
      s := s(count to s'right) & en_dontcare_c;
    elsif strobe'length /= 0 then
      assert strobe'length = count
        report "Bad strobe vector passed"
        severity failure;
      s := s(count to s'right) & strobe;
    else
      s := s(count to s'right) & en_ones_c;
    end if;

    return transfer(cfg,
                    bytes => d,
                    strobe => s,
                    keep => k,
                    id => id(cfg, beat),
                    user => user(cfg, beat),
                    dest => dest(cfg, beat),
                    valid => is_valid(cfg, beat),
                    last => is_last(cfg, beat));
  end function;
  
  function shift_high(cfg: config_t;
                      beat: master_t;
                      count: natural;
                      bytes: byte_string := null_byte_string;
                      strobe: std_ulogic_vector := na_suv;
                      keep: std_ulogic_vector := na_suv) return master_t
  is
    constant data_dontcare_c : byte_string(0 to count-1) := (others => dontcare_byte_c);
    constant en_dontcare_c : std_ulogic_vector(0 to count-1) := (others => '-');
    constant en_ones_c : std_ulogic_vector(0 to count-1) := (others => '1');
    variable d : byte_string(0 to cfg.data_width-1);
    variable k : std_ulogic_vector(0 to cfg.data_width-1);
    variable s : std_ulogic_vector(0 to cfg.data_width-1);
  begin
    d := work.axi4_stream.bytes(cfg, beat);
    k := work.axi4_stream.keep(cfg, beat);
    s := work.axi4_stream.strobe(cfg, beat);

    if bytes'length /= 0 then
      assert bytes'length = count
        report "Bad data vector passed"
        severity failure;
      d := bytes & d(0 to d'right-count);
    else
      d := data_dontcare_c & d(0 to d'right-count);
    end if;

    if not cfg.has_keep then
      k := en_dontcare_c & k(0 to k'right-count);
    elsif keep'length /= 0 then
      assert keep'length = count
        report "Bad keep vector passed"
        severity failure;
      k := keep & k(0 to k'right-count);
    else
      k := en_ones_c & k(0 to k'right-count);
    end if;

    if not cfg.has_strobe then
      s := s(0 to s'right-count) & en_dontcare_c;
    elsif strobe'length /= 0 then
      assert strobe'length = count
        report "Bad strobe vector passed"
        severity failure;
      s := strobe & s(0 to s'right-count);
    else
      s := en_ones_c & s(0 to s'right-count);
    end if;

    return transfer(cfg,
                    bytes => d,
                    strobe => s,
                    keep => k,
                    id => id(cfg, beat),
                    user => user(cfg, beat),
                    dest => dest(cfg, beat),
                    valid => is_valid(cfg, beat),
                    last => is_last(cfg, beat));
  end function;

  procedure packet_send(constant cfg: config_t;
                        signal clock: in std_ulogic;
                        signal stream_i: in slave_t;
                        signal stream_o: out master_t;
                        constant packet: byte_string;
                        constant strobe: std_ulogic_vector := na_suv;
                        constant keep: std_ulogic_vector := na_suv;
                        constant id: std_ulogic_vector := na_suv;
                        constant user: std_ulogic_vector := na_suv;
                        constant dest: std_ulogic_vector := na_suv)
  is
    constant padding_len: integer := (-packet'length) mod cfg.data_width;
    constant padding: byte_string(1 to padding_len) := (others => dontcare_byte_c);
    constant data: byte_string(0 to packet'length+padding_len-1) := packet & padding;
    variable data_strobe: std_ulogic_vector(0 to data'length-1) := (others => '0');
    variable data_keep: std_ulogic_vector(0 to data'length-1) := (others => '0');
    variable index : natural;
  begin
    if strobe'length /= 0 then
      data_strobe(0 to strobe'length-1) := strobe;
    else
      data_strobe(0 to packet'length-1) := (others => '1');
    end if;

    if keep'length /= 0 then
      data_keep(0 to keep'length-1) := keep;
    else
      data_keep(0 to packet'length-1) := (others => '1');
    end if;

    index := 0;
    while index < data'length
    loop
      send(cfg, clock, stream_i, stream_o,
           bytes => data(index to index + cfg.data_width - 1),
           strobe => data_strobe(index to index + cfg.data_width - 1),
           keep => data_keep(index to index + cfg.data_width - 1),
           id => id,
           user => user,
           dest => dest,
           valid => true,
           last => index >= data'length - cfg.data_width);
      index := index + cfg.data_width;
    end loop;
  end procedure;

  procedure packet_receive(constant cfg: config_t;
                           signal clock: in std_ulogic;
                           signal stream_i: in master_t;
                           signal stream_o: out slave_t;
                           variable packet : out byte_stream;
                           variable id : out std_ulogic_vector;
                           variable user : out std_ulogic_vector;
                           variable dest : out std_ulogic_vector)
  is
    variable r: byte_stream;
    variable beat: master_t;
    variable d: byte_string(0 to cfg.data_width-1);
    variable s, k: std_ulogic_vector(0 to cfg.data_width-1);
    variable first: boolean := false;
  begin
    clear(r);

    while true
    loop
      receive(cfg, clock, stream_i, stream_o, beat);

      d := bytes(cfg, beat);
      s := strobe(cfg, beat);
      k := keep(cfg, beat);

      for i in d'range
      loop
        if k(i) = '1' then
          if s(i) = '1' then
            write(r, d(i));
          else
            write(r, dontcare_byte_c);
          end if;
        end if;
      end loop;
      
      if first then
        first := false;

        id := work.axi4_stream.id(cfg, beat)(0 to id'length-1);
        user := work.axi4_stream.user(cfg, beat)(0 to user'length-1);
        dest := work.axi4_stream.dest(cfg, beat)(0 to dest'length-1);
      end if;

      if is_last(cfg, beat) then
        exit;
      end if;
    end loop;

    packet := r;
  end procedure;

  function to_string(cfg: buffer_config_t) return string
  is
  begin
    return "<Buffer for "&to_string(cfg.stream_config) &" by " & to_string(cfg.data_width) & ">";
  end function;

  function to_string(cfg: buffer_config_t; b: buffer_t) return string
  is
  begin
    return "<Buffer "
      &" "&to_string(bytes(cfg, b))
      &" to go: " & to_string(b.to_go)
      &if_else(is_last(cfg, b), " last", "")
      &">";
  end function;
  
  function buffer_config(cfg: config_t; byte_count: natural) return buffer_config_t
  is
  begin
    return buffer_config_t'(
      stream_config => cfg,
      data_width => byte_count,
      part_count => (byte_count + cfg.data_width - 1) / cfg.data_width
      );
  end function;
  
  function is_last(cfg: buffer_config_t; b: buffer_t) return boolean
  is
  begin
    assert b.to_go < cfg.part_count severity failure;
    return b.to_go = 0;
  end function;

  function reset(cfg: buffer_config_t;
                 b: byte_string := null_byte_string;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return buffer_t
  is
    constant dc_pad: byte_string(b'length to data_t'length - 1) := (others => dontcare_byte_c);
  begin
    return buffer_t'(
      data => reorder(b, order) & dc_pad,
      to_go => cfg.part_count - 1
      );
  end function;

  function shift(cfg: buffer_config_t;
                 b: buffer_t;
                 data: byte_string := null_byte_string) return buffer_t
  is
    variable ret: buffer_t;
    constant pad: byte_string(0 to cfg.stream_config.data_width-1) := (others => dontcare_byte_c);
  begin
    if data'length = 0 then
      ret.data(0 to cfg.part_count * cfg.stream_config.data_width - 1)
        := b.data(cfg.stream_config.data_width to cfg.part_count * cfg.stream_config.data_width - 1) & pad;
    else
      ret.data(0 to cfg.part_count * cfg.stream_config.data_width - 1)
        := b.data(cfg.stream_config.data_width to cfg.part_count * cfg.stream_config.data_width - 1) & data;
    end if;
    if b.to_go /= 0 then
      ret.to_go := b.to_go - 1;
    else
      ret.to_go := cfg.part_count - 1;
    end if;
    return ret;
  end function;

  function shift(cfg: buffer_config_t; b: buffer_t; beat: master_t) return buffer_t
  is
  begin
    return shift(cfg, b, bytes(cfg.stream_config, beat));
  end function;

  function next_bytes(cfg: buffer_config_t; b: buffer_t) return byte_string
  is
  begin
    return b.data(0 to cfg.stream_config.data_width-1);
  end function;

  function next_strb(cfg: buffer_config_t; b: buffer_t) return std_ulogic_vector
  is
    constant full: std_ulogic_vector(0 to cfg.stream_config.data_width-1) := (others => '1');
    constant partial_off: std_ulogic_vector(cfg.data_width to cfg.part_count * cfg.stream_config.data_width-1) := (others => '0');
    constant partial_on: std_ulogic_vector(partial_off'length to full'length-1) := (others => '1');
  begin
    if cfg.stream_config.has_strobe and is_last(cfg, b) then
      return partial_on & partial_off;
    end if;

    return full;
  end function;

  function next_beat(cfg: buffer_config_t; b: buffer_t;
                     id: std_ulogic_vector := na_suv;
                     user: std_ulogic_vector := na_suv;
                     dest: std_ulogic_vector := na_suv;
                     last : boolean := true) return master_t
  is
  begin
    return transfer(cfg.stream_config,
                    bytes => next_bytes(cfg, b),
                    strobe => next_strb(cfg, b),
                    id => id,
                    user => user,
                    dest => dest,
                    valid => true,
                    last => last and is_last(cfg, b));
  end function;

  function bytes(cfg: buffer_config_t; b: buffer_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
  begin
    return reorder(b.data(0 to cfg.data_width-1), order);
  end function;

end package body axi4_stream;
