library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_video, nsl_data, nsl_logic, nsl_memory;
use nsl_amba.axi4_mm.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity vdma_writer is
  generic(
    mem_config_c : nsl_amba.axi4_mm.config_t;
    stream_config_c : nsl_video.pixel_stream.config_t;
    burst_length_l2_c : natural := 4;
    buffer_depth_c : positive := 32;
    size_width_c : positive := 16
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    base_i : in unsigned(mem_config_c.address_width-1 downto 0);
    stride_i : in unsigned(mem_config_c.address_width-1 downto 0);
    max_height_i : in unsigned(size_width_c-1 downto 0);

    start_o : out std_ulogic;
    done_o : out std_ulogic;
    status_o : out nsl_video.vdma.frame_status_t;

    stream_i : in nsl_video.pixel_stream.master_t;
    stream_o : out nsl_video.pixel_stream.slave_t;

    mem_o : out nsl_amba.axi4_mm.master_t;
    mem_i : in nsl_amba.axi4_mm.slave_t
    );
end entity;

architecture beh of vdma_writer is

  constant aw_c : positive := mem_config_c.address_width;
  constant word_l2_c : natural := mem_config_c.data_bus_width_l2;
  constant word_bytes_c : positive := 2 ** word_l2_c;
  constant burst_l2_c : natural := nsl_video.vdma.burst_length_l2(mem_config_c, burst_length_l2_c);
  constant len_w_c : natural := mem_config_c.len_width;
  constant pending_max_c : natural := 255;
  constant cmd_depth_c : positive := 4;

  -- Gearbox output: one memory word per beat, pixel_stream user bits.
  constant gb_config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => word_bytes_c,
                                   user => nsl_video.pixel_stream.user_width_c,
                                   keep => true,
                                   last => true);
  -- Data FIFO: one memory word per entry, TLAST is WLAST.
  constant word_config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => word_bytes_c,
                                   keep => true,
                                   last => true);

  subtype addr_t is unsigned(aw_c-1 downto 0);
  subtype word_count_t is unsigned(aw_c-word_l2_c-1 downto 0);
  subtype len_t is unsigned(len_w_c-1 downto 0);
  subtype cmd_t is std_ulogic_vector(aw_c+len_w_c-1 downto 0);

  type state_t is (
    ST_RESET,
    ST_SYNC,
    ST_FRAME,
    ST_DRAIN,
    ST_DONE
    );

  type regs_t is
  record
    state : state_t;
    line_first : boolean;
    any_line : boolean;
    start : boolean;

    line_addr, word_addr, burst_addr, stride : addr_t;
    stride_words, words_left : word_count_t;
    lines_left : unsigned(size_width_c-1 downto 0);
    burst_count : len_t;
    pending : unsigned(7 downto 0);

    eof_seen, line_error, overflow, bus_error : boolean;
  end record;

  signal r, rin : regs_t;

  signal gb_s, data_in_s, data_out_s : nsl_amba.axi4_stream.bus_t;
  signal cmd_in_s, cmd_out_s : cmd_t;
  signal cmd_in_valid_s, cmd_in_ready_s, cmd_out_valid_s : std_ulogic;

  -- What the frame processing does with the word presented by the
  -- gearbox in the current cycle.
  type decision_t is
  record
    take : boolean;
    push_word : boolean;
    push_cmd : boolean;
    closing : boolean;
  end record;

  function align(a : unsigned) return addr_t
  is
    variable ret : addr_t := a;
  begin
    ret(word_l2_c-1 downto 0) := (others => '0');
    return ret;
  end function;

  function at_boundary(a : addr_t) return boolean
  is
  begin
    if burst_l2_c = 0 then
      return true;
    end if;
    return a(word_l2_c+burst_l2_c-1 downto word_l2_c) = (burst_l2_c-1 downto 0 => '1');
  end function;

  function is_sof_word(r : regs_t; w : nsl_amba.axi4_stream.master_t) return boolean
  is
  begin
    return r.line_first
      and nsl_amba.axi4_stream.user(gb_config_c, w)(nsl_video.pixel_stream.user_sof_c) = '1';
  end function;

  function decide(r : regs_t;
                  w : nsl_amba.axi4_stream.master_t;
                  data_ready, cmd_ready : std_ulogic) return decision_t
  is
    variable ret : decision_t;
    variable keep_word : boolean;
  begin
    ret := (take => false, push_word => false, push_cmd => false, closing => false);

    if not nsl_amba.axi4_stream.is_valid(gb_config_c, w) then
      return ret;
    end if;

    case r.state is
      when ST_SYNC =>
        ret.take := not is_sof_word(r, w);

      when ST_FRAME =>
        if is_sof_word(r, w) and r.any_line then
          return ret;
        end if;

        keep_word := r.lines_left /= 0 and r.words_left /= 0;
        ret.closing := nsl_amba.axi4_stream.is_last(gb_config_c, w)
                       or r.words_left = 1
                       or at_boundary(r.word_addr);

        if not keep_word then
          ret.take := true;
        elsif data_ready = '1'
          and (not ret.closing or (cmd_ready = '1' and r.pending /= pending_max_c)) then
          ret.take := true;
          ret.push_word := true;
          ret.push_cmd := ret.closing;
        end if;

      when others =>
        null;
    end case;

    return ret;
  end function;

  function b_error(b : write_response_t) return boolean
  is
  begin
    return is_valid(mem_config_c, b)
      and (resp(mem_config_c, b) = RESP_SLVERR or resp(mem_config_c, b) = RESP_DECERR);
  end function;

begin

  assert word_bytes_c <= nsl_amba.axi4_stream.max_data_width_c
    report "Memory data width is too wide for internal stream"
    severity failure;

  assert buffer_depth_c >= 2 ** burst_l2_c and buffer_depth_c >= 4
    report "Buffer must hold at least a burst and 4 words"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, gb_s.m, data_in_s.s, cmd_in_ready_s, mem_i.b,
                      base_i, stride_i, max_height_i) is
    variable d : decision_t;
    variable next_line : addr_t;
    variable lastw : boolean;
    variable u : std_ulogic_vector(nsl_video.pixel_stream.user_width_c-1 downto 0);
    variable b_done : boolean;
  begin
    rin <= r;
    rin.start <= false;

    d := decide(r, gb_s.m, data_in_s.s.ready, cmd_in_ready_s);
    lastw := nsl_amba.axi4_stream.is_last(gb_config_c, gb_s.m);
    u := nsl_amba.axi4_stream.user(gb_config_c, gb_s.m);
    next_line := r.line_addr + r.stride;

    b_done := is_valid(mem_config_c, mem_i.b);
    if b_error(mem_i.b) then
      rin.bus_error <= true;
    end if;

    if d.push_cmd and not b_done then
      rin.pending <= r.pending + 1;
    elsif b_done and not d.push_cmd then
      rin.pending <= r.pending - 1;
    end if;

    if d.take then
      rin.line_first <= lastw;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_SYNC;
        rin.line_first <= true;
        rin.pending <= (others => '0');
        rin.bus_error <= false;

      when ST_SYNC =>
        if nsl_amba.axi4_stream.is_valid(gb_config_c, gb_s.m) and is_sof_word(r, gb_s.m) then
          rin.state <= ST_FRAME;
          rin.start <= true;
          rin.line_addr <= align(base_i);
          rin.word_addr <= align(base_i);
          rin.burst_addr <= align(base_i);
          rin.stride <= align(stride_i);
          rin.stride_words <= stride_i(aw_c-1 downto word_l2_c);
          rin.words_left <= stride_i(aw_c-1 downto word_l2_c);
          rin.lines_left <= max_height_i;
          rin.burst_count <= (others => '0');
          rin.any_line <= false;
          rin.eof_seen <= false;
          rin.line_error <= false;
          rin.overflow <= false;
          rin.bus_error <= false;
        end if;

      when ST_FRAME =>
        if nsl_amba.axi4_stream.is_valid(gb_config_c, gb_s.m)
          and is_sof_word(r, gb_s.m) and r.any_line then
          rin.state <= ST_DRAIN;
        end if;

        if d.take then
          if d.push_word then
            rin.words_left <= r.words_left - 1;
            rin.word_addr <= r.word_addr + word_bytes_c;
            if d.closing then
              rin.burst_addr <= r.word_addr + word_bytes_c;
              rin.burst_count <= (others => '0');
            else
              rin.burst_count <= r.burst_count + 1;
            end if;
          else
            rin.overflow <= true;
          end if;

          if lastw then
            rin.any_line <= true;
            rin.line_addr <= next_line;
            rin.word_addr <= next_line;
            rin.burst_addr <= next_line;
            rin.words_left <= r.stride_words;
            rin.burst_count <= (others => '0');
            if r.lines_left /= 0 then
              rin.lines_left <= r.lines_left - 1;
            end if;
            if u(nsl_video.pixel_stream.user_error_c) = '1' then
              rin.line_error <= true;
            end if;
            if u(nsl_video.pixel_stream.user_eof_c) = '1' then
              rin.eof_seen <= true;
              rin.state <= ST_DRAIN;
            end if;
          end if;
        end if;

      when ST_DRAIN =>
        if r.pending = 0 then
          rin.state <= ST_DONE;
        end if;

      when ST_DONE =>
        rin.state <= ST_SYNC;
    end case;
  end process;

  moore: process(r) is
  begin
    start_o <= to_logic(r.start);
    done_o <= to_logic(r.state = ST_DONE);
    status_o.complete <= to_logic(r.eof_seen and not r.line_error
                                  and not r.overflow and not r.bus_error);
    status_o.truncated <= to_logic(not r.eof_seen);
    status_o.line_error <= to_logic(r.line_error);
    status_o.overflow <= to_logic(r.overflow);
    status_o.bus_error <= to_logic(r.bus_error);
  end process;

  mealy: process(r, gb_s.m, data_in_s.s, cmd_in_ready_s) is
    variable d : decision_t;
  begin
    d := decide(r, gb_s.m, data_in_s.s.ready, cmd_in_ready_s);

    gb_s.s <= nsl_amba.axi4_stream.accept(gb_config_c, d.take);

    data_in_s.m <= nsl_amba.axi4_stream.transfer(
      word_config_c,
      bytes => nsl_amba.axi4_stream.bytes(gb_config_c, gb_s.m),
      keep => nsl_amba.axi4_stream.keep(gb_config_c, gb_s.m),
      valid => d.push_word,
      last => d.closing);

    cmd_in_valid_s <= to_logic(d.push_cmd);
    cmd_in_s <= std_ulogic_vector(r.burst_addr) & std_ulogic_vector(r.burst_count);
  end process;

  gearbox: nsl_video.vdma.vdma_gearbox
    generic map(
      in_config_c => stream_config_c.stream,
      out_config_c => gb_config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => stream_i,
      in_o => stream_o,

      out_o => gb_s.m,
      out_i => gb_s.s
      );

  data_fifo: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => word_config_c,
      depth_c => buffer_depth_c
      )
    port map(
      clock_i(0) => clock_i,
      reset_n_i => reset_n_i,

      in_i => data_in_s.m,
      in_o => data_in_s.s,

      out_o => data_out_s.m,
      out_i => data_out_s.s
      );

  cmd_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => cmd_t'length,
      word_count_c => cmd_depth_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      out_data_o => cmd_out_s,
      out_ready_i => mem_i.aw.ready,
      out_valid_o => cmd_out_valid_s,

      in_data_i => cmd_in_s,
      in_valid_i => cmd_in_valid_s,
      in_ready_o => cmd_in_ready_s
      );

  mem_o.aw <= address(mem_config_c,
                      addr => unsigned(cmd_out_s(cmd_t'left downto len_w_c)),
                      len_m1 => unsigned(cmd_out_s(len_w_c-1 downto 0)),
                      size_l2 => to_unsigned(word_l2_c, 3),
                      burst => BURST_INCR,
                      valid => cmd_out_valid_s = '1');

  mem_o.w <= write_data(mem_config_c,
                        bytes => nsl_amba.axi4_stream.bytes(word_config_c, data_out_s.m),
                        strb => nsl_amba.axi4_stream.keep(word_config_c, data_out_s.m),
                        last => nsl_amba.axi4_stream.is_last(word_config_c, data_out_s.m),
                        valid => nsl_amba.axi4_stream.is_valid(word_config_c, data_out_s.m));
  data_out_s.s <= nsl_amba.axi4_stream.accept(word_config_c, mem_i.w.ready = '1');

  -- pragma translate_off
  b_check: process(clock_i) is
  begin
    if rising_edge(clock_i) and r.state /= ST_RESET then
      assert not is_valid(mem_config_c, mem_i.b) or r.pending /= 0
        report "Write response without pending burst"
        severity failure;
    end if;
  end process;
  -- pragma translate_on

  mem_o.b <= accept(mem_config_c, true);
  mem_o.ar <= address_defaults(mem_config_c);
  mem_o.r <= accept(mem_config_c, false);

end architecture;
