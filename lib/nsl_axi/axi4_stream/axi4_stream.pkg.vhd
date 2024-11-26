library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_logic, nsl_math, nsl_data;
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

  type m_vector is array (natural range <>) of master_t;
  type s_vector is array (natural range <>) of slave_t;
  type bus_vector is array (natural range <>) of bus_t;

  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');

  function is_valid(cfg: config_t; m: master_t) return boolean;
  function is_last(cfg: config_t; m: master_t) return boolean;
  function is_ready(cfg: config_t; s: slave_t) return boolean;
  function bytes(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return byte_string;
  function value(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return unsigned;
  function strobe(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return std_ulogic_vector;
  function keep(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return std_ulogic_vector;
  function user(cfg: config_t; m: master_t) return std_ulogic_vector;
  function id(cfg: config_t; m: master_t) return std_ulogic_vector;
  function dest(cfg: config_t; m: master_t) return std_ulogic_vector;

  function transfer_defaults(cfg: config_t) return master_t;

  function transfer(cfg: config_t;
                    bytes: byte_string;
                    strobe: std_ulogic_vector := na_suv;
                    keep: std_ulogic_vector := na_suv;
                    endian: endian_t := ENDIAN_LITTLE;
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
  
  component axi4_stream_fifo is
    generic(
      config_c : config_t;
      depth_c : positive;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

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
                 constant endian: endian_t := ENDIAN_LITTLE;
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

end package;

package body axi4_stream is

  function is_valid(cfg: config_t; m: master_t) return boolean
  is
  begin
    return m.valid = '1';
  end function;

  function is_last(cfg: config_t; m: master_t) return boolean
  is
  begin
    if cfg.has_last then
      return m.last = '1';
    else
      return true;
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

  function bytes(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return byte_string
  is
  begin
    if endian = ENDIAN_LITTLE then
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

  function strobe(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(cfg.data_width-1 downto 0);
  begin
    if not cfg.has_strobe then
      return keep(cfg, m);
    end if;

    if endian = ENDIAN_LITTLE then
      return m.strobe(0 to cfg.data_width-1);
    end if;        

    for i in 0 to cfg.data_width-1
    loop
      ret(i) := m.strobe(i);
    end loop;

    return ret;
  end function;

  function keep(cfg: config_t; m: master_t; endian: endian_t := ENDIAN_LITTLE) return std_ulogic_vector
  is
    constant default: std_ulogic_vector(cfg.data_width-1 downto 0) := (others => '1');
    variable ret : std_ulogic_vector(cfg.data_width-1 downto 0);
  begin
    if not cfg.has_keep then
      return default;
    end if;

    if endian = ENDIAN_LITTLE then
      return m.keep(0 to cfg.data_width-1);
    end if;

    for i in 0 to cfg.data_width-1
    loop
      ret(i) := m.keep(i);
    end loop;

    return ret;
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
                    endian: endian_t := ENDIAN_LITTLE;
                    id: std_ulogic_vector := na_suv;
                    user: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid : boolean := true;
                    last : boolean := false) return master_t
  is
    variable ret: master_t;
  begin
    if not cfg.has_keep or cfg.data_width = 0 then
      ret.keep := (others => '-');
    elsif keep'length /= 0 then
      assert keep'length = cfg.data_width
        report "Bad keep length"
        severity failure;
      if endian = ENDIAN_BIG then
        ret.keep(0 to cfg.data_width-1) := bitswap(keep);
      else
        ret.keep(0 to cfg.data_width-1) := keep;
      end if;
    else
      ret.keep(0 to cfg.data_width-1) := (others => '1');
    end if;

    if not cfg.has_strobe or cfg.data_width = 0 then
      ret.strobe := (others => '-');
    elsif strobe'length /= 0 then
      assert strobe'length = cfg.data_width
        report "Bad strobe length"
        severity failure;
      if endian = ENDIAN_BIG then
        ret.strobe(0 to cfg.data_width-1) := bitswap(strobe);
      else
        ret.strobe(0 to cfg.data_width-1) := strobe;
      end if;
    else
      ret.strobe(0 to cfg.data_width-1) := (others => '1');
    end if;

    if cfg.data_width = 0 then
      ret.data := (others => (others => '-'));
    else
      assert bytes'length = cfg.data_width
        report "Bad data length"
        severity failure;
      if endian = ENDIAN_BIG then
        ret.data(0 to cfg.data_width-1) := reverse(bytes);
      else
        ret.data(0 to cfg.data_width-1) := bytes;
      end if;
    end if;

    if cfg.user_width = 0 then
      ret.user := (others => '-');
    else
      assert user'length = cfg.user_width
        report "Bad user length"
        severity failure;
      ret.user(cfg.user_width-1 downto 0) := user;
    end if;

    if cfg.dest_width = 0 then
      ret.dest := (others => '-');
    else
      assert dest'length = cfg.dest_width
        report "Bad dest length"
        severity failure;
      ret.dest(cfg.dest_width-1 downto 0) := dest;
    end if;

    if cfg.id_width = 0 then
      ret.id := (others => '-');
    else
      assert id'length = cfg.id_width
        report "Bad id length"
        severity failure;
      ret.id(cfg.dest_width-1 downto 0) := id;
    end if;

    if valid then
      ret.valid := '1';
    else
      ret.valid := '0';
    end if;

    if not cfg.has_last then
      ret.last := '-';
    elsif last then
      ret.last := '1';
    else
      ret.last := '0';
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
    ret := if_else(strchr(elements, 'i') = -1, 0, cfg.id_width);
    ret := if_else(strchr(elements, 'd') = -1, 0, cfg.data_width * 8);
    ret := if_else(strchr(elements, 's') = -1, 0, cfg.data_width);
    ret := if_else(strchr(elements, 'k') = -1, 0, cfg.data_width);
    ret := if_else(strchr(elements, 'o') = -1, 0, cfg.dest_width);
    ret := if_else(strchr(elements, 'u') = -1, 0, cfg.user_width);
    ret := if_else(strchr(elements, 'v') = -1, 0, 1);
    ret := if_else(strchr(elements, 'l') = -1, 0, 1);
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
          ret(point to point+cfg.data_width-1) := strobe(cfg, m);
          point := point + cfg.data_width;
        when 'k' =>
          ret(point to point+cfg.data_width-1) := keep(cfg, m);
          point := point + cfg.data_width;
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
          ret(point) := to_logic(is_last(cfg, m));
          point := point + 1;
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
          ret.data(0 to cfg.data_width*8-1) := to_be(unsigned(vv(0 to cfg.data_width*8-1)));
          point := point + cfg.data_width * 8;
        when 's' =>
          ret.strobe(0 to cfg.data_width-1) := vv(point to point+cfg.data_width-1);
          point := point + cfg.data_width;
        when 'k' =>
          ret.keep(0 to cfg.data_width-1) := vv(point to point+cfg.data_width-1);
          point := point + cfg.data_width;
        when 'o' =>
          ret.dest(cfg.dest_width-1 downto 0) := vv(point to point+cfg.dest_width-1);
          point := point + cfg.dest_width;
        when 'u' =>
          ret.dest(cfg.user_width-1 downto 0) := vv(point to point+cfg.user_width-1);
          point := point + cfg.user_width;
        when 'v' =>
          ret.valid := vv(point);
          point := point + 1;
        when 'l' =>
          ret.last := vv(point);
          point := point + 1;
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
                 constant endian: endian_t := ENDIAN_LITTLE;
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
                                                  endian => endian,
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

end package body axi4_stream;
