library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data, work;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_data.prbs.all;

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
  -- ARM DUI-0534B defines ID_WIDTH + DEST_WIDTH <= 24, so each of then cannot
  -- go above by itself.
  constant max_id_width_c: natural := 24;
  constant max_dest_width_c: natural := 24;
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

  -- Error feedback
  type error_feedback_t is
  record
    error : std_ulogic ; -- Error inserted or not
    pkt_toggle : std_ulogic; -- toggle when new pkt
    pkt_index_ko : unsigned(15 downto 0);
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
  -- This component will flush packet after either max_packet_length_m1_i+1
  -- beats of transfers or when input is idle more than max_idle_c
  -- clock cycles.
  component axi4_stream_flusher is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      max_packet_length_size_l2_c : natural;
      max_idle_c : natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      max_packet_length_m1_i : unsigned(max_packet_length_size_l2_c-1 downto 0) := (others => '1');

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
  
  -- This dumps a stream to console as it is probed.
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

  -- This implements AXI4-stream protocol assertions as defined in
    -- This implements AXI4-stream protocol assertions as defined in
  -- ARM's DUI 0534-B.
  component axi4_stream_protocol_assertions is
    generic(
      config_c : config_t;
      prefix_c : string := "AXIS";
      MAXWAITS : integer := 16
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      bus_i : in bus_t
      );
  end component;

  -- This component gates the stream going through it to a lower pace
  -- than line rate with a probability of going through of
  -- probability_c.  Internally, it uses a PRBS to generate numbers of
  -- width probability_denom_l2_c that are compared against
  -- probability_c.
  component axi4_stream_pacer is
    generic(
      config_c : config_t;
      probability_denom_l2_c : natural range 1 to 31 := 7;
      probability_c : real := 0.95
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

  -- This inserts a header of fixed size to the stream. Header is
  -- inserted at every begin of packet. Module waits for at least one
  -- packet beat to appear on input port before inserting a header.
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

  -- This extracts a header of fixed size from the stream. Header is
  -- diverted to signals and extra data in a packet are forwarded to
  -- the output.
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

  -- This injects errors into the AXI stream, either randomly or in a
  -- controlled way depending on mode_c.
  -- It provides feedback with the error beat, the packet byte index,
  -- and an error trigger signal.
  component axi4_stream_error_inserter is
    generic(
      config_c : config_t;
      probability_denom_l2_c : natural range 1 to 31 := 7;
      probability_c : real := 0.95;
      mode_c : string := "RANDOM";
      mtu_c : integer := 1500
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
  
      insert_error_i : in boolean := false;
      byte_index_i : in integer range 0 to config_c.data_width := 0;
  
      in_i : in master_t;
      in_o : out slave_t;
  
      out_o : out master_t;
      out_i : in slave_t;
  
      feed_back_o : out error_feedback_t
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
                           variable dest : out std_ulogic_vector;
                           constant ready_toggle : boolean := false);

  procedure packet_receive(constant cfg: config_t;
                           signal clock: in std_ulogic;
                           signal stream_i: in master_t;
                           signal stream_o: out slave_t;
                           variable packet : out byte_string;
                           variable id : out std_ulogic_vector;
                           variable user : out std_ulogic_vector;
                           variable dest : out std_ulogic_vector;
                           constant ready_toggle : boolean := false);

  procedure packet_check(constant cfg: config_t;
                         signal clock: in std_ulogic;
                         signal stream_i: in master_t;
                         signal stream_o: out slave_t;
                         constant packet : byte_string;
                         constant id : std_ulogic_vector := na_suv;
                         constant user : std_ulogic_vector := na_suv;
                         constant dest : std_ulogic_vector := na_suv);

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
  

  -- Helper for receiving/sending multi-beat buffers in an abstract way.
  -- See function buffer_config() below.
  type buffer_config_t is
  record
    stream_config: config_t;
    data_width: natural range 1 to data_t'length;
    beat_count: natural range 1 to data_t'length;
  end record;    

  type buffer_t is
  record
    data: data_t;
    strobe: strobe_t;
    beats_to_go: integer range 0 to data_t'length;
    beat_count: integer range 0 to data_t'length;
  end record;

  function to_string(cfg: buffer_config_t) return string;
  function to_string(cfg: buffer_config_t; b: buffer_t) return string;

  -- This spawns a buffer configuration from a stream configuration
  -- and buffer width.  cfg is backend stream configuration,
  -- byte_count is the buffer byte size. If this is not a multiple of
  -- stream's data byte count, stream will read/write using an integer
  -- count of beats.  Reading will drop incoming data, writing will
  -- send keep=false or strb=false bytes (or padding data if keep
  -- and/or strb are not supported).
  function buffer_config(cfg: config_t; byte_count: natural) return buffer_config_t;
  -- Tells whether buffer will be complete after one shift operation is performed
  function is_last(cfg: buffer_config_t; b: buffer_t) return boolean;
  -- Tells whether buffer will be complete after one shift operation is
  -- performed taking inputs into account
  function is_last(cfg: buffer_config_t; b: buffer_t; beat: master_t) return boolean;
  -- Tells whether we get a last condition from input stream but buffer is
  -- incomplete, in such case, we need to realign buffer.
  function should_align(cfg: buffer_config_t; b: buffer_t; beat: master_t) return boolean;
  -- Yields a buffer context ready for receiving at most the config size.
  function reset(cfg: buffer_config_t) return buffer_t;
  -- Yields a buffer context ready to send data.
  function reset(cfg: buffer_config_t;
                 data: byte_string;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return buffer_t;
  -- Yields a buffer context ready to send first (beat_count_m1+1) beats of
  -- data in passed vector of arbitrary size. data argument must be at most as
  -- big as cfg.data_width.
  function reset(cfg: buffer_config_t;
                 data: byte_string;
                 beat_count_m1: natural;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return buffer_t;
  -- Yields a combination of resetting buffer and a shift using received beat.
  -- This is useful to do a read/write buffer.
  function reset(cfg: buffer_config_t; b: buffer_t; beat: master_t) return buffer_t;
  -- Iteratively realign a buffer to get first beat at the LSB of data vector.
  function realign(cfg: buffer_config_t; b: buffer_t) return buffer_t;
  -- Tell count of transmitted beats before realignment
  function beat_count(cfg: buffer_config_t; b: buffer_t) return natural;
  -- Shifts one step of the buffer by ingressing (optional) data
  -- vector. Counts one step less to do. If not given, dontcares are
  -- used. This can be used for either sending or receiving.
  function shift(cfg: buffer_config_t;
                 b: buffer_t;
                 data: byte_string := null_byte_string;
                 strobe: std_ulogic_vector := na_suv) return buffer_t;
  -- Ingresses one beat from master interface to the buffer. Returns future
  -- buffer value.
  function shift(cfg: buffer_config_t; b: buffer_t; beat: master_t) return buffer_t;
  -- Yields master interface from current buffer contents.  Last is
  -- only taken into account when beat is the last one of the buffer
  -- sending / receiving, otherwise, it is forcibly set to false.
  -- Semantically, this allows user to send extra data after the
  -- buffer contents if needed.  Can modulate strobe and/or keep bits if last
  -- buffer beat is shorter than stream width.
  function next_beat(cfg: buffer_config_t; b: buffer_t;
                     id: std_ulogic_vector := na_suv;
                     user: std_ulogic_vector := na_suv;
                     dest: std_ulogic_vector := na_suv;
                     last : boolean := true;
                     modulate_strb: boolean := true;
                     modulate_keep: boolean := false) return master_t;
  -- Retrieves the full buffer
  function bytes(cfg: buffer_config_t; b: buffer_t; order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;
  -- Retrieves the full strobe vector for the buffer (if relevant)
  function strobe(cfg: buffer_config_t; b: buffer_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;

  -- Typical realigned rx path should be
  --
  -- case r.state is
  -- ....
  --   when ST_INIT =>
  --     rin.buf <= reset(buffer_cfg_c);
  --     rin.state <= ST_RX;
  --
  --   when ST_RX =>
  --     if is_valid(stream_cfg_c, stream_i) then
  --       rin.at_eos <= is_last(stream_cfg_c, stream_i);
  --       rin.buf <= shift(buffer_cfg_c, r.buf, stream_i);
  --       if should_align(buffer_cfg_c, r.buf, stream_i) then
  --         rin.state <= ST_REALIGN;
  --       elif is_last(buffer_cfg_c, r.buf) then
  --         rin.state <= ST_USE_BUFFER;
  --       end if;
  --     end if;
  --
  --  when ST_REALIGN =>
  --     rin.buf <= realign(buffer_cfg_c, r.buf);
  --     if is_last(buffer_cfg_c, r.buf) then
  --       rin.state <= ST_USE_BUFFER;
  --     end if;
  --
  --  when ST_USE_BUFFER =>
  --     size := beat_count(buffer_cfg_c, r.buf) * stream_cfg_c.data_width;
  --     data := bytes(buffer_cfg_c, r.buf);
  --     -- Do somehting with data(0 to size-1);


  -- A posted AXI4-Stream Frame
  type frame_t is
  record
    id: id_t;
    data: byte_stream;
    dest: dest_t;
    user: user_t;
    ts: time;
  end record;

  -- Writes a frame to signals, takes ownership of frame buffer
  procedure frame_put(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal stream_i: in slave_t;
                      signal stream_o: out master_t;
                      variable frm: frame_t);
  
  -- Reads a frame from signals
  procedure frame_get(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal stream_i: in master_t;
                      signal stream_o: out slave_t;
                      variable frm: out frame_t);

  -- Factory function for a frame
impure function frame(
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv)
    return frame_t;

  -- Frame queue for testbenches
  type frame_queue_item_t;
  type frame_queue_t is access frame_queue_item_t;
  
  type frame_queue_item_t is
  record
    chain: frame_queue_t;
    frame: frame_t;
  end record;
  
  type frame_queue_root_item_t is
  record
    head: frame_queue_t;
  end record;

  type frame_queue_root_t is access frame_queue_root_item_t;

  -- Initializes a frame queue
  procedure frame_queue_init(
    variable root: inout frame_queue_root_t);

  -- Appends a frame to a queue
  procedure frame_queue_put(
    variable root: frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv);

  -- Appends a frame to a queue, takes ownership of frame's buffer
  procedure frame_queue_put(
    variable root: in frame_queue_root_t;
    variable frm: in frame_t);

  -- Appends a frame to two queues, takes ownership of frame's buffer
  procedure frame_queue_put2(
    variable a, b: in frame_queue_root_t;
    variable frm: in frame_t);
  procedure frame_queue_put2(
    variable a, b: in frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv);

  -- Waits for a frame to be present on a queue.
  -- Polls for queue every dt. After timeout, raises a sev error
  procedure frame_queue_get(
    variable root: frame_queue_root_t;
    variable frm: out frame_t;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure);

  -- Waits for a frame to be present on a queue.
  -- When it is present, asserts for equality with passed reference data.
  -- Polls for queue every dt. After timeout, raises a sev error
  procedure frame_queue_check(
    variable root: frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure);

  -- Waits for a frame to be present on a queue.
  -- When it is present, asserts for equality with passed reference data.
  -- Polls for queue every dt. After timeout, raises a sev error.
  -- Takes ownership of frame's data vector.
  procedure frame_queue_check(
    variable root: in frame_queue_root_t;
    variable frm: in frame_t;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure);

  -- Sends a frame on master queue and expects exactly matching frame on slave
  -- queue.
  procedure frame_queue_check_io(
    variable root_master: in frame_queue_root_t;
    variable root_slave: in frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure);

  -- Sends a frame on master queue and expects exactly matching frame on slave
  -- queue.
  procedure frame_queue_check_io(
    variable root_master: in frame_queue_root_t;
    variable root_slave: in frame_queue_root_t;
    variable frm: in frame_t;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure);
  
  -- Master-side procedure. Takes frames from a queue and puts them to
  -- signals.  Never returns
  procedure frame_queue_master(constant cfg: config_t;
                               variable root: in frame_queue_root_t;
                               signal clock: in std_ulogic;
                               signal stream_i: in slave_t;
                               signal stream_o: out master_t;
                               timeout : in time := 100 us;
                               dt : in time := 10 ns);

  -- Waits for a queue to be empty
  procedure frame_queue_drain(constant cfg: config_t;
                              variable root: in frame_queue_root_t;
                              dt : in time := 10 ns;
                              timeout : in time := 100 us;
                              sev: severity_level := failure);
  
  -- Slave-side procedure. Takes frames from signals and puts them to
  -- a queue.  Never returns
  procedure frame_queue_slave(constant cfg: config_t;
                              variable root: in frame_queue_root_t;
                              signal clock: in std_ulogic;
                              signal stream_i: in master_t;
                              signal stream_o: out slave_t;
                               dt : in time := 10 ns);

  -- A queue-only procedure that checks two queues for equality
  procedure frame_queue_assert_equal(constant cfg: config_t;
                                     variable a, b: in frame_queue_root_t;
                                     sev: severity_level := failure);
  
end package;

package body axi4_stream is

  function dontcare_pad(v: std_ulogic_vector;
                        w: integer)
    return std_ulogic_vector
  is
    alias xv: std_ulogic_vector(v'length-1 downto 0) is v;
    constant v_s : integer := nsl_math.arith.min(v'length, w);
    constant minxv: std_ulogic_vector(v_s-1 downto 0) := xv(v_s-1 downto 0);
    variable ret: std_ulogic_vector(w-1 downto 0) := (others => '-');
  begin
    ret(minxv'length-1 downto 0) := minxv;
    return ret;
  end function;
  
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
      return keep(cfg, m, order);
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
    assert id + dest <= 24
      report "ID_WIDTH + DEST_WIDTH may not be above 24 per ARM DUI 0534B"
      severity failure;

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
                           variable dest : out std_ulogic_vector;
                           constant ready_toggle : boolean := false)
  is
    variable r: byte_stream;
    variable beat: master_t;
    variable d: byte_string(0 to cfg.data_width-1);
    variable s, k: std_ulogic_vector(0 to cfg.data_width-1);
    variable first: boolean := false;
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
  begin
    assert cfg.has_last
      report "Packet_receive with a byte stream cannot support unframed interface"
      severity failure;

    clear(r);
    stream_o <= accept(cfg, false);
    
    while true
    loop
      state_v := prbs_forward(state_v, prbs31, cfg.data_width);
      if ready_toggle and state_v(0) = '1' then
        wait until rising_edge(clock);
        wait until falling_edge(clock);
        next;
      end if;

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

  procedure packet_receive(constant cfg: config_t;
                           signal clock: in std_ulogic;
                           signal stream_i: in master_t;
                           signal stream_o: out slave_t;
                           variable packet : out byte_string;
                           variable id : out std_ulogic_vector;
                           variable user : out std_ulogic_vector;
                           variable dest : out std_ulogic_vector;
                           constant ready_toggle : boolean := false)
  is
    variable r: byte_string(0 to packet'length-1);
    variable beat: master_t;
    variable d: byte_string(0 to cfg.data_width-1);
    variable s, k: std_ulogic_vector(0 to cfg.data_width-1);
    variable first: boolean := false;
    variable should_be_last: boolean;
    variable offset: integer := 0;
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
  begin
    assert cfg.has_keep or (packet'length mod cfg.data_width = 0)
      report "Testing for a short packet with no keep will always fail"
      severity note;

    while offset < r'length
    loop
      state_v := prbs_forward(state_v, prbs31, cfg.data_width);
      if ready_toggle and state_v(0) = '1' then
        wait until rising_edge(clock);
        wait until falling_edge(clock);
        next;
      end if;

      should_be_last := offset + d'length >= r'length;

      receive(cfg, clock, stream_i, stream_o, beat);

      d := bytes(cfg, beat);
      s := strobe(cfg, beat);
      k := keep(cfg, beat);

      for i in d'range
      loop
        if k(i) = '1' then
          assert offset + i < r'length
            report "Extra data at end of packet"
            severity failure;

          if s(i) = '1' then
            r(offset + i) := d(i);
          else
            r(offset + i) := dontcare_byte_c;
          end if;
        end if;
      end loop;
      
      if first then
        first := false;

        id := work.axi4_stream.id(cfg, beat)(0 to id'length-1);
        user := work.axi4_stream.user(cfg, beat)(0 to user'length-1);
        dest := work.axi4_stream.dest(cfg, beat)(0 to dest'length-1);
      end if;

      if cfg.has_last then
        assert should_be_last = is_last(cfg, beat)
          report "At offset "&to_string(offset)&", last is "&if_else(should_be_last, "", "not ")&"expected, but was "&if_else(is_last(cfg, beat), "", "un")&"asserted. Expected payload length: "&to_string(r'length)
          severity failure;
      end if;

      offset := offset + d'length;
    end loop;

    packet := r;
  end procedure;

  procedure packet_check(constant cfg: config_t;
                         signal clock: in std_ulogic;
                         signal stream_i: in master_t;
                         signal stream_o: out slave_t;
                         constant packet : byte_string;
                         constant id : std_ulogic_vector := na_suv;
                         constant user : std_ulogic_vector := na_suv;
                         constant dest : std_ulogic_vector := na_suv)
  is
    variable rid : std_ulogic_vector(cfg.id_width-1 downto 0);
    variable ruser : std_ulogic_vector(cfg.user_width-1 downto 0);
    variable rdest : std_ulogic_vector(cfg.dest_width-1 downto 0);
    variable rdata : byte_string(0 to packet'length-1);
  begin
    packet_receive(cfg, clock, stream_i, stream_o, rdata, rid, ruser, rdest);

    if id'length /= 0 then
      assert std_match(id, rid)
        report "Bad ID, had "&to_string(rid)&", expected "&to_string(id)
        severity failure;
    end if;
    
    if user'length /= 0 then
      assert std_match(user, ruser)
        report "Bad USER, had "&to_string(ruser)&", expected "&to_string(user)
        severity failure;
    end if;

    if dest'length /= 0 then
      assert std_match(dest, rdest)
        report "Bad DEST, had "&to_string(rdest)&", expected "&to_string(dest)
        severity failure;
    end if;

    assert std_match(packet, rdata)
        report "Bad data, had "&to_string(rdata)&", expected "&to_string(packet)
        severity failure;
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
      &" "&to_string(b.data(0 to cfg.beat_count * cfg.stream_config.data_width -1))
      &" trx: " & to_string(b.beat_count)
      &" to go: " & to_string(b.beats_to_go)
      &" strb: " & to_hex_string(b.strobe(0 to cfg.beat_count * cfg.stream_config.data_width -1))
      &if_else(is_last(cfg, b), " last", "")
      &">";
  end function;
  
  function buffer_config(cfg: config_t; byte_count: natural) return buffer_config_t
  is
  begin
    return buffer_config_t'(
      stream_config => cfg,
      data_width => byte_count,
      beat_count => (byte_count + cfg.data_width - 1) / cfg.data_width
      );
  end function;
  
  function is_last(cfg: buffer_config_t; b: buffer_t) return boolean
  is
  begin
    assert b.beats_to_go < cfg.beat_count severity failure;
    return b.beats_to_go = 0;
  end function;

  function is_last(cfg: buffer_config_t; b: buffer_t; beat: master_t) return boolean
  is
  begin
    return is_valid(cfg.stream_config, beat) and (is_last(cfg, b) or is_last(cfg.stream_config, beat));
  end function;

  function should_align(cfg: buffer_config_t; b: buffer_t; beat: master_t) return boolean
  is
  begin
    return is_valid(cfg.stream_config, beat) and not is_last(cfg, b) and is_last(cfg.stream_config, beat);
  end function;

  function reset(cfg: buffer_config_t;
                 data: byte_string;
                 beat_count_m1: natural;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return buffer_t
  is
    constant dc_pad: byte_string(data'length to data_t'length - 1) := (others => dontcare_byte_c);
    constant strobe_val: std_ulogic_vector(0 to data'length - 1) := (others => '1');
    constant strobe_pad: std_ulogic_vector(data'length to strobe_t'length - 1) := (others => '0');
  begin
    assert data'length <= cfg.data_width
      report "Passed buffer is too big"
      severity failure;
    return buffer_t'(
      data => reorder(data, order) & dc_pad,
      strobe => strobe_val & strobe_pad,
      beats_to_go => beat_count_m1,
      beat_count => 0
      );
  end function;

  function reset(cfg: buffer_config_t;
                 data: byte_string;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return buffer_t
  is
  begin
    assert data'length /= 0
      report "Cannot pass null data vector"
      severity failure;
    return reset(cfg, data, beat_count_m1 => (data'length - 1) / cfg.stream_config.data_width, order => order);
  end function;

  function reset(cfg: buffer_config_t) return buffer_t
  is
  begin
    return reset(cfg, null_byte_string, beat_count_m1 => cfg.beat_count-1);
  end function;

  function reset(cfg: buffer_config_t; b: buffer_t; beat: master_t) return buffer_t
  is
  begin
    assert is_valid(cfg.stream_config, beat)
      report "Beat must be valid"
      severity failure;
    assert is_last(cfg, b)
      report "buffer must be in the last cycle"
      severity failure;
    return reset(cfg, bytes(cfg, shift(cfg, b, beat)));
  end function;

  function shift(cfg: buffer_config_t;
                 b: buffer_t;
                 data: byte_string := null_byte_string;
                 strobe: std_ulogic_vector := na_suv) return buffer_t
  is
    variable ret: buffer_t;
    constant sval: std_ulogic_vector(0 to cfg.stream_config.data_width-1) := (others => '1');
    constant strb: std_ulogic_vector := if_else(strobe'length /= 0, strobe, sval);
    constant pad: byte_string(0 to cfg.stream_config.data_width-1) := (others => dontcare_byte_c);
    constant spad: std_ulogic_vector(0 to cfg.stream_config.data_width-1) := (others => '0');
  begin
    assert data'length = strobe'length or strobe'length = 0
      report "Must pass same length data/strobe vectors, or no strobe at all"
      severity failure;
    if data'length = 0 then
      ret.data(0 to cfg.beat_count * cfg.stream_config.data_width - 1)
        := b.data(cfg.stream_config.data_width to cfg.beat_count * cfg.stream_config.data_width - 1) & pad;
      ret.strobe(0 to cfg.beat_count * cfg.stream_config.data_width - 1)
        := b.strobe(cfg.stream_config.data_width to cfg.beat_count * cfg.stream_config.data_width - 1) & spad;
    else
      ret.data(0 to cfg.beat_count * cfg.stream_config.data_width - 1)
        := b.data(cfg.stream_config.data_width to cfg.beat_count * cfg.stream_config.data_width - 1) & data;
      ret.strobe(0 to cfg.beat_count * cfg.stream_config.data_width - 1)
        := b.strobe(cfg.stream_config.data_width to cfg.beat_count * cfg.stream_config.data_width - 1) & strb;
    end if;

    if b.beats_to_go /= 0 then
      ret.beats_to_go := b.beats_to_go - 1;
      ret.beat_count := b.beat_count + 1;
    else
      ret.beats_to_go := cfg.beat_count - 1;
      ret.beat_count := 0;
    end if;
    return ret;
  end function;

  function shift(cfg: buffer_config_t; b: buffer_t; beat: master_t) return buffer_t
  is
  begin
    return shift(cfg, b, bytes(cfg.stream_config, beat), strobe(cfg.stream_config, beat));
  end function;

  function next_bytes(cfg: buffer_config_t; b: buffer_t) return byte_string
  is
  begin
    return b.data(0 to cfg.stream_config.data_width-1);
  end function;

  function next_strobes(cfg: buffer_config_t; b: buffer_t) return std_ulogic_vector
  is
  begin
    return b.strobe(0 to cfg.stream_config.data_width-1);
  end function;

  function next_beat(cfg: buffer_config_t; b: buffer_t;
                     id: std_ulogic_vector := na_suv;
                     user: std_ulogic_vector := na_suv;
                     dest: std_ulogic_vector := na_suv;
                     last : boolean := true;
                     modulate_strb: boolean := true;
                     modulate_keep: boolean := false) return master_t
  is
  begin
    return transfer(cfg.stream_config,
                    bytes => next_bytes(cfg, b),
                    strobe => if_else(modulate_strb, next_strobes(cfg, b), ""),
                    keep => if_else(modulate_keep, next_strobes(cfg, b), ""),
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

  function strobe(cfg: buffer_config_t; b: buffer_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
  begin
    return reorder_mask(b.strobe(0 to cfg.data_width-1), order);
  end function;

  function realign(cfg: buffer_config_t; b: buffer_t) return buffer_t
  is
    variable ret: buffer_t;
    constant pad: byte_string(0 to cfg.stream_config.data_width-1) := (others => dontcare_byte_c);
    constant spad: std_ulogic_vector(0 to cfg.stream_config.data_width-1) := (others => '0');
  begin
    ret.data(0 to cfg.beat_count * cfg.stream_config.data_width - 1)
      := b.data(cfg.stream_config.data_width to cfg.beat_count * cfg.stream_config.data_width - 1) & pad;
    ret.strobe(0 to cfg.beat_count * cfg.stream_config.data_width - 1)
      := b.strobe(cfg.stream_config.data_width to cfg.beat_count * cfg.stream_config.data_width - 1) & spad;
    if b.beats_to_go /= 0 then
      ret.beats_to_go := b.beats_to_go - 1;
      ret.beat_count := b.beat_count;
    else
      ret.beats_to_go := b.beat_count - 1;
      ret.beat_count := 0;
    end if;
    return ret;
  end function;
  
  function beat_count(cfg: buffer_config_t; b: buffer_t) return natural
  is
  begin
    return b.beat_count;
  end function;

impure function frame(
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv)
    return frame_t
  is
    variable ret: frame_t;
  begin
    ret.data := new byte_string(0 to data'length-1);
    ret.data.all := data;
    ret.id := dontcare_pad(id, max_id_width_c);
    ret.user := dontcare_pad(user, max_user_width_c);
    ret.dest := dontcare_pad(dest, max_dest_width_c);
    ret.ts := now;
    return ret;
  end function;

  procedure frame_clone(
    variable ret: out frame_t;
    variable frm: in frame_t)
  is
    variable r : frame_t;
  begin
    r.data := new byte_string(0 to frm.data'length-1);
    r.data.all := frm.data.all;
    r.id := dontcare_pad(frm.id, max_id_width_c);
    r.user := dontcare_pad(frm.user, max_user_width_c);
    r.dest := dontcare_pad(frm.dest, max_dest_width_c);
    r.ts := frm.ts;
    ret := r;
  end procedure;

  procedure frame_put(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal stream_i: in slave_t;
                      signal stream_o: out master_t;
                      variable frm: frame_t)
  is
    variable f : frame_t := frm;
  begin
    packet_send(cfg, clock, stream_i, stream_o, f.data.all,
                dest => f.dest(cfg.dest_width-1 downto 0),
                user => f.user(cfg.user_width-1 downto 0),
                id => f.id(cfg.id_width-1 downto 0));
    deallocate(f.data);
  end procedure;

  procedure frame_get(constant cfg: config_t;
                      signal clock: in std_ulogic;
                      signal stream_i: in master_t;
                      signal stream_o: out slave_t;
                      variable frm: out frame_t)
  is
    variable packet : byte_stream;
    variable id : std_ulogic_vector(cfg.id_width-1 downto 0);
    variable user : std_ulogic_vector(cfg.user_width-1 downto 0);
    variable dest : std_ulogic_vector(cfg.dest_width-1 downto 0);
  begin
    packet_receive(cfg, clock, stream_i, stream_o, packet, id, user, dest);
    frm.data := packet;
    frm.id := dontcare_pad(id, max_id_width_c);
    frm.user := dontcare_pad(user, max_user_width_c);
    frm.dest := dontcare_pad(dest, max_dest_width_c);
  end procedure;

  procedure frame_queue_init(
    variable root: inout frame_queue_root_t)
  is
    variable ret: frame_queue_root_t;
  begin
    root := new frame_queue_root_item_t;
    root.head := null;
  end procedure;

  procedure frame_queue_put(
    variable root: frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv)
  is
    variable frm : frame_t := frame(data, dest, id, user);
  begin
    frame_queue_put(root, frm);
  end procedure;

  procedure frame_queue_put2(
    variable a, b: in frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv)
  is
    variable frm : frame_t := frame(data, dest, id, user);
    variable c : frame_t;
  begin
    frame_clone(c, frm);
    frame_queue_put(a, c);
    frame_queue_put(b, frm);
  end procedure;

  procedure frame_queue_put2(
    variable a, b: in frame_queue_root_t;
    variable frm: in frame_t)
  is
    variable c : frame_t;
  begin
    frame_clone(c, frm);
    frame_queue_put(a, c);
    frame_queue_put(b, frm);
  end procedure;

  procedure frame_queue_put(
    variable root: in frame_queue_root_t;
    variable frm: in frame_t)
  is
    variable item_a, chain_a: frame_queue_t;
    variable root_v: frame_queue_root_t := root;
  begin
    item_a := new frame_queue_item_t;
    item_a.frame := frm;
    item_a.chain := null;

    if root_v.head = null then
      root_v.head := item_a;
    else
      chain_a := root_v.head;
      while chain_a.chain /= null
      loop
        chain_a := chain_a.chain;
      end loop;
      chain_a.chain := item_a;
    end if;
  end procedure;

  procedure frame_queue_check(
    variable root: frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable frm: frame_t := frame(data, dest, id, user);
  begin
    frame_queue_check(root, frm, dt, timeout, sev);
  end procedure;

  procedure frame_queue_check(
    variable root: in frame_queue_root_t;
    variable frm: in frame_t;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable rx_frm: frame_t;
    variable ref_frm: frame_t := frm;
  begin
    frame_queue_get(root, rx_frm, dt, timeout, sev);
    assert rx_frm.data.all = ref_frm.data.all
      and rx_frm.id = ref_frm.id
      and rx_frm.user = ref_frm.user
      and rx_frm.dest = ref_frm.dest
      report "Bad frame received, expected "&to_string(ref_frm.data.all)&", received "&to_string(rx_frm.data.all)
      severity sev;
    deallocate(rx_frm.data);
    deallocate(ref_frm.data);
  end procedure;

  procedure frame_queue_check_io(
    variable root_master: in frame_queue_root_t;
    variable root_slave: in frame_queue_root_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable frm: frame_t := frame(data, dest, id, user);
  begin
    frame_queue_check_io(root_master, root_slave, frm, dt, timeout, sev);
  end procedure;

  procedure frame_queue_check_io(
    variable root_master: in frame_queue_root_t;
    variable root_slave: in frame_queue_root_t;
    variable frm: in frame_t;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable c : frame_t;
  begin
    frame_clone(c, frm);
    frame_queue_put(root_master, c);
    frame_queue_check(root_slave, frm, dt, timeout, sev);
  end procedure;

  procedure frame_queue_get(
    variable root: frame_queue_root_t;
    variable frm: out frame_t;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable root_v: frame_queue_root_t := root;
    variable item_a: frame_queue_t;
    variable ret: frame_t;
    variable time_left: time := timeout;
  begin
    while time_left > dt
    loop
      if root_v.head /= null then
        item_a := root_v.head;
        root_v.head := item_a.chain;
        ret := item_a.frame;
        deallocate(item_a);
        frm := ret;
        return;
      end if;
      wait for dt;
      time_left := time_left - dt;
    end loop;
    assert false
      report "Timeout while waiting for frame"
      severity sev;
  end procedure;

  procedure frame_queue_master(constant cfg: config_t;
                               variable root: in frame_queue_root_t;
                               signal clock: in std_ulogic;
                               signal stream_i: in slave_t;
                               signal stream_o: out master_t;
                               timeout : in time := 100 us;
                               dt : in time := 10 ns)
  is
    variable frm: frame_t;
  begin
    stream_o <= transfer_defaults(cfg);

    loop
      frame_queue_get(root, frm, dt, timeout);
      wait until falling_edge(clock);
      frame_put(cfg, clock, stream_i, stream_o, frm);
    end loop;
  end procedure;

  procedure frame_queue_slave(constant cfg: config_t;
                              variable root: in frame_queue_root_t;
                              signal clock: in std_ulogic;
                              signal stream_i: in master_t;
                              signal stream_o: out slave_t;
                               dt : in time := 10 ns)
  is
    variable frm: frame_t;
  begin
    stream_o <= accept(cfg, false);

    loop
      wait until falling_edge(clock);
      frame_get(cfg, clock, stream_i, stream_o, frm);
      frame_queue_put(root, frm);
    end loop;
  end procedure;

  procedure frame_queue_drain(constant cfg: config_t;
                              variable root: in frame_queue_root_t;
                              dt : in time := 10 ns;
                              timeout : in time := 100 us;
                              sev: severity_level := failure)
  is
    variable time_left: time := timeout;
  begin
    while time_left > dt
    loop
      if root.head = null then
        return;
      end if;
      wait for dt;
      time_left := time_left - dt;
    end loop;

    assert false
      report "Timeout while waiting for queue emptiness"
      severity sev;
  end procedure;

  procedure frame_queue_assert_equal(constant cfg: config_t;
                                     variable a, b: in frame_queue_root_t;
                                     sev: severity_level := failure) 
 is
    variable a_frm, b_frm: frame_t;
  begin
    while a.head /= null
    loop
      frame_queue_get(a, a_frm);
      assert b.head /= null
        report "Right queue is shorter than left one"
        severity sev;

      frame_queue_get(b, b_frm);
      
      assert a_frm.data.all = b_frm.data.all
        and a_frm.id(cfg.id_width-1 downto 0) = b_frm.id(cfg.id_width-1 downto 0)
        and a_frm.user(cfg.user_width-1 downto 0) = b_frm.user(cfg.user_width-1 downto 0)
        and a_frm.dest(cfg.dest_width-1 downto 0) = b_frm.dest(cfg.dest_width-1 downto 0)
        report "Mismatch between frames, left from "&to_string(a_frm.ts)&" "&to_string(a_frm.data.all)&", right from "&to_string(b_frm.ts)&" "&to_string(b_frm.data.all)
        severity sev;

      deallocate(a_frm.data);
      deallocate(b_frm.data);
    end loop;

    assert b.head = null
      report "Left queue is shorter than right one"
      severity sev;
  end procedure;

end package body axi4_stream;
