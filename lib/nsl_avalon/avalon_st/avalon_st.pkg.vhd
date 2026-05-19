library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

-- This package defines Avalon-ST bus signals and accessors.
--
-- It mirrors the design approach of nsl_amba.axi4_stream: the signal
-- records carry every field at its worst-case width. A config_t value
-- accompanies the records at every interface; accessors slice it for
-- actual use and return sensible protocol defaults for features the
-- config disables, so component code never branches on cfg.has_*.
--
-- Data orientation: symbols are packed in source.data with symbol 0
-- occupying the low-order bits (bits [data_bits_per_symbol-1 downto 0]),
-- symbol 1 the next data_bits_per_symbol bits, and so on. This is the
-- internal canonical form. The first_symbol_in_high_order_bits flag in
-- config_t describes the orientation expected at the *external* port
-- of an interface; matching it against the wire layout is the job of a
-- boundary adapter, not of these accessors.
package avalon_st is

  -- Arbitrary NSL limits
  constant max_data_bits_c            : natural := 1024;
  constant max_symbols_per_beat_c     : natural := 128;
  constant max_data_bits_per_symbol_c : natural := 64;
  constant max_channel_width_c        : natural := 24;
  constant max_error_width_c          : natural := 16;
  constant max_packet_user_width_c    : natural := 64;
  constant max_symbol_user_bits_c     : natural := 1024;
  constant max_ready_latency_c        : natural := 8;
  constant max_ready_allowance_c      : natural := 16;
  constant empty_bits_c               : natural := nsl_math.arith.log2(max_symbols_per_beat_c);

  subtype data_t        is std_ulogic_vector(max_data_bits_c-1 downto 0);
  subtype symbol_user_t is std_ulogic_vector(max_symbol_user_bits_c-1 downto 0);
  subtype channel_t     is std_ulogic_vector(max_channel_width_c-1 downto 0);
  subtype error_t       is std_ulogic_vector(max_error_width_c-1 downto 0);
  subtype packet_user_t is std_ulogic_vector(max_packet_user_width_c-1 downto 0);
  subtype empty_t       is unsigned(empty_bits_c-1 downto 0);

  -- Configuration parameters for an Avalon-ST interface
  type config_t is
  record
    symbols_per_beat:                positive range 1 to max_symbols_per_beat_c;
    data_bits_per_symbol:            positive range 1 to max_data_bits_per_symbol_c;
    channel_width:                   natural  range 0 to max_channel_width_c;
    error_width:                     natural  range 0 to max_error_width_c;
    packet_user_width:               natural  range 0 to max_packet_user_width_c;
    symbol_user_width:               natural  range 0 to max_symbol_user_bits_c;
    has_ready:                       boolean;
    has_packet:                      boolean;
    has_empty:                       boolean;
    ready_latency:                   natural  range 0 to max_ready_latency_c;
    ready_allowance:                 natural  range 0 to max_ready_allowance_c;
    first_symbol_in_high_order_bits: boolean;
  end record;

  type config_vector is array (natural range <>) of config_t;

  -- Configuration factory with sensible defaults.
  --
  -- ready_allowance defaults to ready_latency. has_empty implies
  -- has_packet and symbols_per_beat > 1.
  function config(
    symbols_per_beat:                positive := 1;
    data_bits_per_symbol:            positive := 8;
    channel:                         natural  := 0;
    error:                           natural  := 0;
    packet_user:                     natural  := 0;
    symbol_user:                     natural  := 0;
    has_ready:                       boolean  := true;
    has_packet:                      boolean  := false;
    has_empty:                       boolean  := false;
    ready_latency:                   natural  := 0;
    ready_allowance:                 integer  := -1;
    first_symbol_in_high_order_bits: boolean  := true
    ) return config_t;

  -- Source-to-sink interface
  --@-- grouped group:bus_t
  type source_t is
  record
    data:           data_t;
    valid:          std_ulogic;
    startofpacket:  std_ulogic;
    endofpacket:    std_ulogic;
    empty:          empty_t;
    channel:        channel_t;
    error:          error_t;
    packet_user:    packet_user_t;
    symbol_user:    symbol_user_t;
  end record;

  -- Sink-to-source interface
  --@-- grouped group:bus_t
  type sink_t is
  record
    ready: std_ulogic;
  end record;

  type bus_t is
  record
    --@-- grouped direction:forward
    src: source_t;
    --@-- grouped direction:reverse
    snk: sink_t;
  end record;

  type source_vector is array (natural range <>) of source_t;
  type sink_vector   is array (natural range <>) of sink_t;
  type bus_vector    is array (natural range <>) of bus_t;

  constant null_source_c : source_t := (
    data          => (others => '-'),
    valid         => '0',
    startofpacket => '-',
    endofpacket   => '-',
    empty         => (others => '-'),
    channel       => (others => '-'),
    error         => (others => '-'),
    packet_user   => (others => '-'),
    symbol_user   => (others => '-')
    );

  constant null_source_vector : source_vector(1 to 0) := (others => null_source_c);

  constant na_suv : std_ulogic_vector(1 to 0) := (others => '-');

  -- Predicates
  function is_valid(cfg: config_t; src: source_t) return boolean;
  function is_ready(cfg: config_t; snk: sink_t) return boolean;
  function is_sop  (cfg: config_t; src: source_t; default: boolean := true) return boolean;
  function is_eop  (cfg: config_t; src: source_t; default: boolean := true) return boolean;
  function is_error(cfg: config_t; src: source_t) return boolean;

  -- Symbol-oriented accessors
  function data_bits         (cfg: config_t) return natural;
  function data              (cfg: config_t; src: source_t) return std_ulogic_vector;
  function symbol            (cfg: config_t; src: source_t; n: natural) return std_ulogic_vector;
  function symbol_count      (cfg: config_t) return natural;
  function valid_symbol_count(cfg: config_t; src: source_t) return natural;
  function empty             (cfg: config_t; src: source_t) return natural;
  function channel           (cfg: config_t; src: source_t) return std_ulogic_vector;
  function error             (cfg: config_t; src: source_t) return std_ulogic_vector;
  function packet_user       (cfg: config_t; src: source_t) return std_ulogic_vector;
  function symbol_user       (cfg: config_t; src: source_t; n: natural) return std_ulogic_vector;

  -- Byte shortcuts (assert data_bits_per_symbol = 8)
  function bytes     (cfg: config_t; src: source_t;
                      order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string;
  function byte_count(cfg: config_t; src: source_t) return natural;
  function value     (cfg: config_t; src: source_t;
                      endian: endian_t := ENDIAN_LITTLE) return unsigned;

  -- Builders
  function transfer_defaults(cfg: config_t) return source_t;

  function accept(cfg: config_t; ready: boolean := false) return sink_t;

  -- General builder: data is a std_ulogic_vector of length
  -- symbols_per_beat*data_bits_per_symbol, with symbol 0 in the low bits.
  -- valid_symbols = 0 means "all symbols valid"; any other value asserts
  -- has_empty and eop, and is encoded in the empty field.
  function transfer(cfg:           config_t;
                    data:          std_ulogic_vector;
                    valid_symbols: natural          := 0;
                    channel:       std_ulogic_vector := na_suv;
                    error:         std_ulogic_vector := na_suv;
                    packet_user:   std_ulogic_vector := na_suv;
                    symbol_user:   std_ulogic_vector := na_suv;
                    valid:         boolean := true;
                    sop:           boolean := false;
                    eop:           boolean := false) return source_t;

  -- Byte shortcut (asserts data_bits_per_symbol = 8). bytes'length must
  -- equal symbols_per_beat; partial beats use valid_symbols.
  function transfer(cfg:           config_t;
                    bytes:         byte_string;
                    valid_symbols: natural          := 0;
                    order:         byte_order_t     := BYTE_ORDER_INCREASING;
                    channel:       std_ulogic_vector := na_suv;
                    error:         std_ulogic_vector := na_suv;
                    packet_user:   std_ulogic_vector := na_suv;
                    symbol_user:   std_ulogic_vector := na_suv;
                    valid:         boolean := true;
                    sop:           boolean := false;
                    eop:           boolean := false) return source_t;

  -- Convert a beat coming from src_cfg to cfg. Both configs must agree
  -- on symbols_per_beat and data_bits_per_symbol; cfg may widen channel,
  -- error and user fields. Disabled features are zero-filled.
  function transfer(cfg: config_t;
                    src_cfg: config_t;
                    src: source_t) return source_t;

  -- Modify only control flags (valid/sop/eop) of an existing source.
  function transfer(cfg:         config_t;
                    src:         source_t;
                    force_valid: boolean := false;
                    force_sop:   boolean := false;
                    force_eop:   boolean := false;
                    valid:       boolean := false;
                    sop:         boolean := false;
                    eop:         boolean := false) return source_t;

  -- Vector pack/unpack of a subset of source signals.
  --
  -- Element codes: 'd' = data, 'c' = channel, 'e' = error,
  -- 'u' = packet_user, 's' = symbol_user, 'm' = empty,
  -- 'v' = valid, 'p' = sop, 'q' = eop.
  function vector_length(cfg: config_t;
                         elements: string) return natural;
  function vector_pack  (cfg: config_t;
                         elements: string;
                         src: source_t) return std_ulogic_vector;
  function vector_unpack(cfg: config_t;
                         elements: string;
                         v: std_ulogic_vector) return source_t;

  -- Debugging
  function to_string(cfg: config_t) return string;
  function to_string(cfg: config_t; src: source_t) return string;
  function to_string(cfg: config_t; snk: sink_t)   return string;

  component avalon_st_dumper is
    generic(
      config_c : config_t;
      prefix_c : string := "AVST"
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      bus_i : in bus_t
      );
  end component;

end package;

package body avalon_st is

  function config(
    symbols_per_beat:                positive := 1;
    data_bits_per_symbol:            positive := 8;
    channel:                         natural  := 0;
    error:                           natural  := 0;
    packet_user:                     natural  := 0;
    symbol_user:                     natural  := 0;
    has_ready:                       boolean  := true;
    has_packet:                      boolean  := false;
    has_empty:                       boolean  := false;
    ready_latency:                   natural  := 0;
    ready_allowance:                 integer  := -1;
    first_symbol_in_high_order_bits: boolean  := true
    ) return config_t
  is
    variable allowance : natural;
  begin
    assert symbols_per_beat * data_bits_per_symbol <= max_data_bits_c
      report "symbols_per_beat * data_bits_per_symbol exceeds max_data_bits_c"
      severity failure;
    assert symbol_user * symbols_per_beat <= max_symbol_user_bits_c
      report "symbol_user * symbols_per_beat exceeds max_symbol_user_bits_c"
      severity failure;
    assert (not has_empty) or (has_packet and symbols_per_beat > 1)
      report "has_empty requires has_packet and symbols_per_beat > 1"
      severity failure;

    if ready_allowance < 0 then
      allowance := ready_latency;
    else
      allowance := ready_allowance;
    end if;

    assert allowance >= ready_latency
      report "ready_allowance must be >= ready_latency"
      severity failure;
    assert allowance <= max_ready_allowance_c
      report "ready_allowance exceeds max_ready_allowance_c"
      severity failure;

    return config_t'(
      symbols_per_beat                => symbols_per_beat,
      data_bits_per_symbol            => data_bits_per_symbol,
      channel_width                   => channel,
      error_width                     => error,
      packet_user_width               => packet_user,
      symbol_user_width               => symbol_user,
      has_ready                       => has_ready,
      has_packet                      => has_packet,
      has_empty                       => has_empty,
      ready_latency                   => ready_latency,
      ready_allowance                 => allowance,
      first_symbol_in_high_order_bits => first_symbol_in_high_order_bits
      );
  end function;

  function is_valid(cfg: config_t; src: source_t) return boolean
  is
  begin
    return src.valid = '1';
  end function;

  function is_ready(cfg: config_t; snk: sink_t) return boolean
  is
  begin
    if cfg.has_ready then
      return snk.ready = '1';
    else
      return true;
    end if;
  end function;

  function is_sop(cfg: config_t; src: source_t; default: boolean := true) return boolean
  is
  begin
    if cfg.has_packet then
      return src.startofpacket = '1';
    else
      return default;
    end if;
  end function;

  function is_eop(cfg: config_t; src: source_t; default: boolean := true) return boolean
  is
  begin
    if cfg.has_packet then
      return src.endofpacket = '1';
    else
      return default;
    end if;
  end function;

  function is_error(cfg: config_t; src: source_t) return boolean
  is
    variable any : std_ulogic := '0';
  begin
    if cfg.error_width = 0 then
      return false;
    end if;
    for i in 0 to cfg.error_width - 1
    loop
      if src.error(i) = '1' then
        any := '1';
      end if;
    end loop;
    return any = '1';
  end function;

  function data_bits(cfg: config_t) return natural
  is
  begin
    return cfg.symbols_per_beat * cfg.data_bits_per_symbol;
  end function;

  function data(cfg: config_t; src: source_t) return std_ulogic_vector
  is
    constant w : natural := data_bits(cfg);
  begin
    return src.data(w-1 downto 0);
  end function;

  function symbol(cfg: config_t; src: source_t; n: natural) return std_ulogic_vector
  is
    constant w  : natural := cfg.data_bits_per_symbol;
    constant lo : natural := n * w;
  begin
    assert n < cfg.symbols_per_beat
      report "symbol index out of range"
      severity failure;
    return src.data(lo + w - 1 downto lo);
  end function;

  function symbol_count(cfg: config_t) return natural
  is
  begin
    return cfg.symbols_per_beat;
  end function;

  function empty(cfg: config_t; src: source_t) return natural
  is
  begin
    if not cfg.has_empty then
      return 0;
    end if;
    return to_integer(src.empty);
  end function;

  function valid_symbol_count(cfg: config_t; src: source_t) return natural
  is
  begin
    if cfg.has_empty and is_eop(cfg, src, default => false) then
      return cfg.symbols_per_beat - empty(cfg, src);
    end if;
    return cfg.symbols_per_beat;
  end function;

  function channel(cfg: config_t; src: source_t) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(cfg.channel_width-1 downto 0) := (others => '-');
  begin
    if cfg.channel_width = 0 then
      return ret;
    end if;
    return src.channel(cfg.channel_width-1 downto 0);
  end function;

  function error(cfg: config_t; src: source_t) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(cfg.error_width-1 downto 0) := (others => '-');
  begin
    if cfg.error_width = 0 then
      return ret;
    end if;
    return src.error(cfg.error_width-1 downto 0);
  end function;

  function packet_user(cfg: config_t; src: source_t) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(cfg.packet_user_width-1 downto 0) := (others => '-');
  begin
    if cfg.packet_user_width = 0 then
      return ret;
    end if;
    return src.packet_user(cfg.packet_user_width-1 downto 0);
  end function;

  function symbol_user(cfg: config_t; src: source_t; n: natural) return std_ulogic_vector
  is
    constant w  : natural := cfg.symbol_user_width;
    constant lo : natural := n * w;
    variable ret : std_ulogic_vector(w-1 downto 0) := (others => '-');
  begin
    assert n < cfg.symbols_per_beat
      report "symbol_user index out of range"
      severity failure;
    if w = 0 then
      return ret;
    end if;
    return src.symbol_user(lo + w - 1 downto lo);
  end function;

  function bytes(cfg: config_t; src: source_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING) return byte_string
  is
    variable ret : byte_string(0 to cfg.symbols_per_beat - 1);
  begin
    assert cfg.data_bits_per_symbol = 8
      report "bytes() requires data_bits_per_symbol = 8"
      severity failure;

    for i in 0 to cfg.symbols_per_beat - 1
    loop
      ret(i) := std_ulogic_vector(src.data(i*8 + 7 downto i*8));
    end loop;

    if order = BYTE_ORDER_INCREASING then
      return ret;
    else
      return reverse(ret);
    end if;
  end function;

  function byte_count(cfg: config_t; src: source_t) return natural
  is
  begin
    return valid_symbol_count(cfg, src);
  end function;

  function value(cfg: config_t; src: source_t;
                 endian: endian_t := ENDIAN_LITTLE) return unsigned
  is
  begin
    return from_endian(bytes(cfg, src), endian);
  end function;

  function transfer_defaults(cfg: config_t) return source_t
  is
    variable ret: source_t;
  begin
    ret.data          := (others => '-');
    ret.valid         := '0';
    ret.empty         := (others => '-');
    ret.channel       := (others => '-');
    ret.error         := (others => '-');
    ret.packet_user   := (others => '-');
    ret.symbol_user   := (others => '-');

    if cfg.has_packet then
      ret.startofpacket := '0';
      ret.endofpacket   := '0';
    else
      ret.startofpacket := '-';
      ret.endofpacket   := '-';
    end if;

    if cfg.has_empty then
      ret.empty := (others => '0');
    end if;

    if cfg.error_width /= 0 then
      ret.error(cfg.error_width-1 downto 0) := (others => '0');
    end if;

    return ret;
  end function;

  function accept(cfg: config_t; ready: boolean := false) return sink_t
  is
    variable ret : sink_t;
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

  function transfer(cfg:           config_t;
                    data:          std_ulogic_vector;
                    valid_symbols: natural          := 0;
                    channel:       std_ulogic_vector := na_suv;
                    error:         std_ulogic_vector := na_suv;
                    packet_user:   std_ulogic_vector := na_suv;
                    symbol_user:   std_ulogic_vector := na_suv;
                    valid:         boolean := true;
                    sop:           boolean := false;
                    eop:           boolean := false) return source_t
  is
    constant w  : natural := data_bits(cfg);
    constant us : natural := cfg.symbol_user_width * cfg.symbols_per_beat;
    variable ret: source_t := transfer_defaults(cfg);
  begin
    assert data'length = w
      report "Bad data length"
      severity failure;
    ret.data(w-1 downto 0) := data;

    if cfg.channel_width /= 0 and channel'length /= 0 then
      assert channel'length = cfg.channel_width
        report "Bad channel length"
        severity failure;
      ret.channel(cfg.channel_width-1 downto 0) := channel;
    end if;

    if cfg.error_width /= 0 and error'length /= 0 then
      assert error'length = cfg.error_width
        report "Bad error length"
        severity failure;
      ret.error(cfg.error_width-1 downto 0) := error;
    end if;

    if cfg.packet_user_width /= 0 and packet_user'length /= 0 then
      assert packet_user'length = cfg.packet_user_width
        report "Bad packet_user length"
        severity failure;
      ret.packet_user(cfg.packet_user_width-1 downto 0) := packet_user;
    end if;

    if us /= 0 and symbol_user'length /= 0 then
      assert symbol_user'length = us
        report "Bad symbol_user length"
        severity failure;
      ret.symbol_user(us-1 downto 0) := symbol_user;
    end if;

    if valid then
      ret.valid := '1';
    end if;

    if cfg.has_packet then
      ret.startofpacket := to_logic(sop);
      ret.endofpacket   := to_logic(eop);
    end if;

    if cfg.has_empty then
      if valid_symbols = 0 then
        ret.empty := (others => '0');
      else
        assert eop
          report "valid_symbols < symbols_per_beat is only allowed on eop"
          severity failure;
        assert valid_symbols <= cfg.symbols_per_beat
          report "valid_symbols exceeds symbols_per_beat"
          severity failure;
        ret.empty := to_unsigned(cfg.symbols_per_beat - valid_symbols, ret.empty'length);
      end if;
    else
      assert valid_symbols = 0 or valid_symbols = cfg.symbols_per_beat
        report "Partial beats require has_empty"
        severity failure;
    end if;

    return ret;
  end function;

  function transfer(cfg:           config_t;
                    bytes:         byte_string;
                    valid_symbols: natural          := 0;
                    order:         byte_order_t     := BYTE_ORDER_INCREASING;
                    channel:       std_ulogic_vector := na_suv;
                    error:         std_ulogic_vector := na_suv;
                    packet_user:   std_ulogic_vector := na_suv;
                    symbol_user:   std_ulogic_vector := na_suv;
                    valid:         boolean := true;
                    sop:           boolean := false;
                    eop:           boolean := false) return source_t
  is
    variable bs       : byte_string(0 to cfg.symbols_per_beat - 1);
    variable data_slv : std_ulogic_vector(cfg.symbols_per_beat*8 - 1 downto 0);
  begin
    assert cfg.data_bits_per_symbol = 8
      report "byte-shortcut transfer requires data_bits_per_symbol = 8"
      severity failure;
    assert bytes'length = cfg.symbols_per_beat
      report "Bad bytes length"
      severity failure;

    if order = BYTE_ORDER_INCREASING then
      bs := bytes;
    else
      bs := reverse(bytes);
    end if;

    for i in 0 to cfg.symbols_per_beat - 1
    loop
      data_slv(i*8 + 7 downto i*8) := bs(i);
    end loop;

    return transfer(cfg           => cfg,
                    data          => data_slv,
                    valid_symbols => valid_symbols,
                    channel       => channel,
                    error         => error,
                    packet_user   => packet_user,
                    symbol_user   => symbol_user,
                    valid         => valid,
                    sop           => sop,
                    eop           => eop);
  end function;

  function transfer(cfg: config_t;
                    src_cfg: config_t;
                    src: source_t) return source_t
  is
    constant w        : natural := nsl_math.arith.min(data_bits(cfg), data_bits(src_cfg));
    constant chan_w   : natural := nsl_math.arith.min(cfg.channel_width, src_cfg.channel_width);
    constant err_w    : natural := nsl_math.arith.min(cfg.error_width, src_cfg.error_width);
    constant puser_w  : natural := nsl_math.arith.min(cfg.packet_user_width, src_cfg.packet_user_width);
    constant suser_w  : natural := nsl_math.arith.min(cfg.symbol_user_width * cfg.symbols_per_beat,
                                                      src_cfg.symbol_user_width * src_cfg.symbols_per_beat);
    variable ret : source_t := transfer_defaults(cfg);
  begin
    assert cfg.symbols_per_beat = src_cfg.symbols_per_beat
      report "Cross-config transfer requires matching symbols_per_beat"
      severity failure;
    assert cfg.data_bits_per_symbol = src_cfg.data_bits_per_symbol
      report "Cross-config transfer requires matching data_bits_per_symbol"
      severity failure;

    if w /= 0 then
      ret.data(w-1 downto 0) := src.data(w-1 downto 0);
    end if;

    if cfg.channel_width /= 0 then
      ret.channel(cfg.channel_width-1 downto 0) := (others => '0');
      if chan_w /= 0 then
        ret.channel(chan_w-1 downto 0) := src.channel(chan_w-1 downto 0);
      end if;
    end if;

    if cfg.error_width /= 0 then
      ret.error(cfg.error_width-1 downto 0) := (others => '0');
      if err_w /= 0 then
        ret.error(err_w-1 downto 0) := src.error(err_w-1 downto 0);
      end if;
    end if;

    if cfg.packet_user_width /= 0 then
      ret.packet_user(cfg.packet_user_width-1 downto 0) := (others => '0');
      if puser_w /= 0 then
        ret.packet_user(puser_w-1 downto 0) := src.packet_user(puser_w-1 downto 0);
      end if;
    end if;

    if cfg.symbol_user_width /= 0 then
      ret.symbol_user(cfg.symbol_user_width*cfg.symbols_per_beat-1 downto 0) := (others => '0');
      if suser_w /= 0 then
        ret.symbol_user(suser_w-1 downto 0) := src.symbol_user(suser_w-1 downto 0);
      end if;
    end if;

    ret.valid := src.valid;

    if cfg.has_packet then
      ret.startofpacket := to_logic(is_sop(src_cfg, src, default => true));
      ret.endofpacket   := to_logic(is_eop(src_cfg, src, default => true));
    end if;

    if cfg.has_empty then
      if src_cfg.has_empty then
        ret.empty := src.empty;
      else
        ret.empty := (others => '0');
      end if;
    end if;

    return ret;
  end function;

  function transfer(cfg:         config_t;
                    src:         source_t;
                    force_valid: boolean := false;
                    force_sop:   boolean := false;
                    force_eop:   boolean := false;
                    valid:       boolean := false;
                    sop:         boolean := false;
                    eop:         boolean := false) return source_t
  is
    variable ret : source_t := src;
  begin
    if force_valid then
      ret.valid := to_logic(valid);
    end if;
    if force_sop and cfg.has_packet then
      ret.startofpacket := to_logic(sop);
    end if;
    if force_eop and cfg.has_packet then
      ret.endofpacket := to_logic(eop);
    end if;
    return ret;
  end function;

  function vector_length(cfg: config_t;
                         elements: string) return natural
  is
    variable ret : natural := 0;
  begin
    ret := ret + if_else(strchr(elements, 'd') = -1, 0, data_bits(cfg));
    ret := ret + if_else(strchr(elements, 'c') = -1, 0, cfg.channel_width);
    ret := ret + if_else(strchr(elements, 'e') = -1, 0, cfg.error_width);
    ret := ret + if_else(strchr(elements, 'u') = -1, 0, cfg.packet_user_width);
    ret := ret + if_else(strchr(elements, 's') = -1, 0, cfg.symbol_user_width * cfg.symbols_per_beat);
    ret := ret + if_else(strchr(elements, 'm') /= -1 and cfg.has_empty, empty_bits_c, 0);
    ret := ret + if_else(strchr(elements, 'v') = -1, 0, 1);
    ret := ret + if_else(strchr(elements, 'p') /= -1 and cfg.has_packet, 1, 0);
    ret := ret + if_else(strchr(elements, 'q') /= -1 and cfg.has_packet, 1, 0);
    return ret;
  end function;

  function vector_pack(cfg: config_t;
                       elements: string;
                       src: source_t) return std_ulogic_vector
  is
    constant s     : natural := vector_length(cfg, elements);
    variable ret   : std_ulogic_vector(0 to s-1);
    variable point : natural range 0 to s := 0;
    constant suser : natural := cfg.symbol_user_width * cfg.symbols_per_beat;
  begin
    for ei in elements'range
    loop
      case elements(ei) is
        when 'd' =>
          ret(point to point + data_bits(cfg) - 1) := data(cfg, src);
          point := point + data_bits(cfg);
        when 'c' =>
          if cfg.channel_width /= 0 then
            ret(point to point + cfg.channel_width - 1) := channel(cfg, src);
            point := point + cfg.channel_width;
          end if;
        when 'e' =>
          if cfg.error_width /= 0 then
            ret(point to point + cfg.error_width - 1) := error(cfg, src);
            point := point + cfg.error_width;
          end if;
        when 'u' =>
          if cfg.packet_user_width /= 0 then
            ret(point to point + cfg.packet_user_width - 1) := packet_user(cfg, src);
            point := point + cfg.packet_user_width;
          end if;
        when 's' =>
          if suser /= 0 then
            ret(point to point + suser - 1) := src.symbol_user(suser-1 downto 0);
            point := point + suser;
          end if;
        when 'm' =>
          if cfg.has_empty then
            ret(point to point + empty_bits_c - 1) := std_ulogic_vector(src.empty);
            point := point + empty_bits_c;
          end if;
        when 'v' =>
          ret(point) := to_logic(is_valid(cfg, src));
          point := point + 1;
        when 'p' =>
          if cfg.has_packet then
            ret(point) := to_logic(is_sop(cfg, src));
            point := point + 1;
          end if;
        when 'q' =>
          if cfg.has_packet then
            ret(point) := to_logic(is_eop(cfg, src));
            point := point + 1;
          end if;
        when others =>
          assert false
            report "Bad key, must be one of [dceusmvpq]"
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
                         v: std_ulogic_vector) return source_t
  is
    constant s     : natural := vector_length(cfg, elements);
    alias vv       : std_ulogic_vector(0 to s-1) is v;
    variable point : natural range 0 to s := 0;
    variable ret   : source_t := transfer_defaults(cfg);
    constant suser : natural := cfg.symbol_user_width * cfg.symbols_per_beat;
  begin
    assert vv'length = s
      report "Bad vector length for packing elements"
      severity failure;

    for ei in elements'range
    loop
      case elements(ei) is
        when 'd' =>
          ret.data(data_bits(cfg) - 1 downto 0) := vv(point to point + data_bits(cfg) - 1);
          point := point + data_bits(cfg);
        when 'c' =>
          if cfg.channel_width /= 0 then
            ret.channel(cfg.channel_width-1 downto 0) := vv(point to point + cfg.channel_width - 1);
            point := point + cfg.channel_width;
          end if;
        when 'e' =>
          if cfg.error_width /= 0 then
            ret.error(cfg.error_width-1 downto 0) := vv(point to point + cfg.error_width - 1);
            point := point + cfg.error_width;
          end if;
        when 'u' =>
          if cfg.packet_user_width /= 0 then
            ret.packet_user(cfg.packet_user_width-1 downto 0) := vv(point to point + cfg.packet_user_width - 1);
            point := point + cfg.packet_user_width;
          end if;
        when 's' =>
          if suser /= 0 then
            ret.symbol_user(suser-1 downto 0) := vv(point to point + suser - 1);
            point := point + suser;
          end if;
        when 'm' =>
          if cfg.has_empty then
            ret.empty := unsigned(vv(point to point + empty_bits_c - 1));
            point := point + empty_bits_c;
          end if;
        when 'v' =>
          ret.valid := vv(point);
          point := point + 1;
        when 'p' =>
          if cfg.has_packet then
            ret.startofpacket := vv(point);
            point := point + 1;
          end if;
        when 'q' =>
          if cfg.has_packet then
            ret.endofpacket := vv(point);
            point := point + 1;
          end if;
        when others =>
          assert false
            report "Bad key, must be one of [dceusmvpq]"
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
    return "<AVST"
      &" "&to_string(cfg.symbols_per_beat)&"x"&to_string(cfg.data_bits_per_symbol)
      &if_else(cfg.channel_width>0,     " C"&to_string(cfg.channel_width),         "")
      &if_else(cfg.error_width>0,       " E"&to_string(cfg.error_width),           "")
      &if_else(cfg.packet_user_width>0, " U"&to_string(cfg.packet_user_width),     "")
      &if_else(cfg.symbol_user_width>0, " SU"&to_string(cfg.symbol_user_width),    "")
      &if_else(cfg.has_packet,          " P",                                      "")
      &if_else(cfg.has_empty,           " M",                                      "")
      &if_else(cfg.has_ready,           " R",                                      "")
      &" RL"&to_string(cfg.ready_latency)
      &" RA"&to_string(cfg.ready_allowance)
      &if_else(cfg.first_symbol_in_high_order_bits, " hi", " lo")
      &">";
  end function;

  function to_string(cfg: config_t; src: source_t) return string
  is
    variable vsc : natural;
  begin
    if not is_valid(cfg, src) then
      return "<AVSTs !valid>";
    end if;
    vsc := valid_symbol_count(cfg, src);
    return "<AVSTs"
      &" "&to_string(data(cfg, src))
      &" ["&to_string(vsc)&"/"&to_string(cfg.symbols_per_beat)&"]"
      &if_else(cfg.channel_width>0,     " C:"&to_string(channel(cfg, src)),     "")
      &if_else(cfg.error_width>0,       " E:"&to_string(error(cfg, src)),       "")
      &if_else(cfg.packet_user_width>0, " U:"&to_string(packet_user(cfg, src)), "")
      &if_else(is_sop(cfg, src, default => false), " sop", "")
      &if_else(is_eop(cfg, src, default => false), " eop", "")
      &">";
  end function;

  function to_string(cfg: config_t; snk: sink_t) return string
  is
  begin
    return "<AVSTk"
      &if_else(is_ready(cfg, snk), " ready", " stall")
      &">";
  end function;

end package body;
