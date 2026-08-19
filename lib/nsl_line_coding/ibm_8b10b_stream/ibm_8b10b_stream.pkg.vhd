library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_data, nsl_line_coding;
use nsl_data.bytestream.all;
use nsl_line_coding.ibm_8b10b.all;

-- This package carries IBM 8b/10b symbol streams over AXI4-Stream.
--
-- Each data byte of a beat is paired with the K (control) bit held in
-- the TUSER bit of matching index. As a consequence, user width is
-- always equal to the data byte count and is not a free parameter.
--
-- Wire-level signals are plain nsl_amba.axi4_stream master/slave
-- records, so any existing AXI4-Stream component operates on such a
-- stream unchanged. This package only adds a configuration record
-- enforcing the user width relationship, and accessors/constructors
-- expressing beats in terms of 8b/10b words.
package ibm_8b10b_stream is

  subtype master_t is nsl_amba.axi4_stream.master_t;
  subtype slave_t is nsl_amba.axi4_stream.slave_t;
  subtype bus_t is nsl_amba.axi4_stream.bus_t;

  constant na_suv: std_ulogic_vector(1 to 0) := (others => '-');

  type config_t is
  record
    word_count: natural range 0 to nsl_amba.axi4_stream.max_data_width_c;
    id_width: natural range 0 to nsl_amba.axi4_stream.max_id_width_c;
    dest_width: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c;
    has_keep: boolean;
    has_strobe: boolean;
    has_ready: boolean;
    has_last: boolean;
  end record;

  -- Underlying AXI4-Stream configuration, with data width and user
  -- width both set to the word count.
  function as_stream_config(cfg: config_t) return nsl_amba.axi4_stream.config_t;

  function config(
    words: natural range 0 to nsl_amba.axi4_stream.max_data_width_c;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    strobe: boolean := false;
    ready: boolean := true;
    last: boolean := false) return config_t;

  function is_valid(cfg: config_t; m: master_t) return boolean;
  function is_last(cfg: config_t; m: master_t; default: boolean := true) return boolean;
  function is_ready(cfg: config_t; s: slave_t) return boolean;
  function strobe(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  function keep(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector;
  function user(cfg: config_t; m: master_t) return std_ulogic_vector;
  function id(cfg: config_t; m: master_t) return std_ulogic_vector;
  function dest(cfg: config_t; m: master_t) return std_ulogic_vector;

  -- Word at a given index of the beat, pairing data byte and K bit of
  -- matching index.
  function word(cfg: config_t;
                m: master_t;
                index: integer := 0;
                order: byte_order_t := BYTE_ORDER_INCREASING)
    return nsl_line_coding.ibm_8b10b.data_t;

  -- All words of the beat. order selects the index direction of the
  -- returned array, following the convention of nsl_data.bytestream
  -- reorder(): word of index i is data byte i paired with K bit i in
  -- both directions.
  function words(cfg: config_t;
                 m: master_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING)
    return nsl_line_coding.ibm_8b10b.data_vector;

  -- Requires cfg.word_count = 1.
  function transfer(cfg: config_t;
                    word: nsl_line_coding.ibm_8b10b.data_t;
                    strobe: boolean := true;
                    keep: boolean := true;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    last: boolean := false) return master_t;

  function transfer(cfg: config_t;
                    words: nsl_line_coding.ibm_8b10b.data_vector;
                    strobe: std_ulogic_vector := na_suv;
                    keep: std_ulogic_vector := na_suv;
                    order: byte_order_t := BYTE_ORDER_INCREASING;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    last: boolean := false) return master_t;

end package;

package body ibm_8b10b_stream is

  function as_stream_config(cfg: config_t) return nsl_amba.axi4_stream.config_t
  is
  begin
    return nsl_amba.axi4_stream.config(
      bytes => cfg.word_count,
      user => cfg.word_count,
      id => cfg.id_width,
      dest => cfg.dest_width,
      keep => cfg.has_keep,
      strobe => cfg.has_strobe,
      ready => cfg.has_ready,
      last => cfg.has_last);
  end function;

  function config(
    words: natural range 0 to nsl_amba.axi4_stream.max_data_width_c;
    id: natural range 0 to nsl_amba.axi4_stream.max_id_width_c := 0;
    dest: natural range 0 to nsl_amba.axi4_stream.max_dest_width_c := 0;
    keep: boolean := false;
    strobe: boolean := false;
    ready: boolean := true;
    last: boolean := false) return config_t
  is
  begin
    assert words <= nsl_amba.axi4_stream.max_user_width_c
      report "One K bit per word is needed, word count cannot exceed maximum user width"
      severity failure;

    return config_t'(
      word_count => words,
      id_width => id,
      dest_width => dest,
      has_keep => keep,
      has_strobe => strobe,
      has_ready => ready,
      has_last => last
      );
  end function;

  function is_valid(cfg: config_t; m: master_t) return boolean
  is
  begin
    return nsl_amba.axi4_stream.is_valid(as_stream_config(cfg), m);
  end function;

  function is_last(cfg: config_t; m: master_t; default: boolean := true) return boolean
  is
  begin
    return nsl_amba.axi4_stream.is_last(as_stream_config(cfg), m, default);
  end function;

  function is_ready(cfg: config_t; s: slave_t) return boolean
  is
  begin
    return nsl_amba.axi4_stream.is_ready(as_stream_config(cfg), s);
  end function;

  function strobe(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.strobe(as_stream_config(cfg), m, order);
  end function;

  function keep(cfg: config_t; m: master_t; order: byte_order_t := BYTE_ORDER_INCREASING) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.keep(as_stream_config(cfg), m, order);
  end function;

  function user(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.user(as_stream_config(cfg), m);
  end function;

  function id(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.id(as_stream_config(cfg), m);
  end function;

  function dest(cfg: config_t; m: master_t) return std_ulogic_vector
  is
  begin
    return nsl_amba.axi4_stream.dest(as_stream_config(cfg), m);
  end function;

  function words(cfg: config_t;
                 m: master_t;
                 order: byte_order_t := BYTE_ORDER_INCREASING)
    return nsl_line_coding.ibm_8b10b.data_vector
  is
    constant stream_cfg: nsl_amba.axi4_stream.config_t := as_stream_config(cfg);
    constant data_v: byte_string(0 to cfg.word_count-1)
      := nsl_amba.axi4_stream.bytes(stream_cfg, m, BYTE_ORDER_INCREASING);
    constant control_v: std_ulogic_vector(cfg.word_count-1 downto 0)
      := nsl_amba.axi4_stream.user(stream_cfg, m);
    variable increasing: data_vector(0 to cfg.word_count-1);
    variable decreasing: data_vector(cfg.word_count-1 downto 0);
  begin
    for i in 0 to cfg.word_count-1
    loop
      increasing(i) := data_t'(data => data_v(i),
                               control => control_v(i));
    end loop;

    if order = BYTE_ORDER_INCREASING then
      return increasing;
    end if;

    for i in 0 to cfg.word_count-1
    loop
      decreasing(i) := increasing(i);
    end loop;

    return decreasing;
  end function;

  function word(cfg: config_t;
                m: master_t;
                index: integer := 0;
                order: byte_order_t := BYTE_ORDER_INCREASING)
    return nsl_line_coding.ibm_8b10b.data_t
  is
    constant all_words: data_vector := words(cfg, m, order);
  begin
    assert 0 <= index and index < cfg.word_count
      report "Word index is out of beat range"
      severity failure;

    return all_words(index);
  end function;

  function transfer(cfg: config_t;
                    words: nsl_line_coding.ibm_8b10b.data_vector;
                    strobe: std_ulogic_vector := na_suv;
                    keep: std_ulogic_vector := na_suv;
                    order: byte_order_t := BYTE_ORDER_INCREASING;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    last: boolean := false) return master_t
  is
    alias xwords: data_vector(0 to words'length-1) is words;
    variable data_v: byte_string(0 to cfg.word_count-1);
    variable control_v: std_ulogic_vector(cfg.word_count-1 downto 0);
  begin
    assert words'length = cfg.word_count
      report "Bad word count"
      severity failure;

    for i in 0 to cfg.word_count-1
    loop
      data_v(i) := xwords(i).data;
    end loop;

    -- data is passed in the order it comes in, but K bits are indexed
    -- by byte position in the beat.
    for i in 0 to cfg.word_count-1
    loop
      if order = BYTE_ORDER_INCREASING then
        control_v(i) := xwords(i).control;
      else
        control_v(i) := xwords(cfg.word_count-1-i).control;
      end if;
    end loop;

    return nsl_amba.axi4_stream.transfer(
      cfg => as_stream_config(cfg),
      bytes => data_v,
      strobe => strobe,
      keep => keep,
      order => order,
      id => id,
      user => control_v,
      dest => dest,
      valid => valid,
      last => last);
  end function;

  function transfer(cfg: config_t;
                    word: nsl_line_coding.ibm_8b10b.data_t;
                    strobe: boolean := true;
                    keep: boolean := true;
                    id: std_ulogic_vector := na_suv;
                    dest: std_ulogic_vector := na_suv;
                    valid: boolean := true;
                    last: boolean := false) return master_t
  is
    variable strobe_v, keep_v: std_ulogic_vector(0 to 0);
    variable word_v: data_vector(0 to 0);
  begin
    assert cfg.word_count = 1
      report "Single-word transfer needs a one-word-wide configuration"
      severity failure;

    if strobe then
      strobe_v := "1";
    else
      strobe_v := "0";
    end if;

    if keep then
      keep_v := "1";
    else
      keep_v := "0";
    end if;

    word_v(0) := word;

    return transfer(cfg => cfg,
                    words => word_v,
                    strobe => strobe_v,
                    keep => keep_v,
                    id => id,
                    dest => dest,
                    valid => valid,
                    last => last);
  end function;

end package body;
