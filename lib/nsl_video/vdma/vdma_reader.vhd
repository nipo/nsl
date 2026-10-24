library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_video, nsl_data, nsl_logic, nsl_math;
use nsl_amba.axi4_mm.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity vdma_reader is
  generic(
    mem_config_c : nsl_amba.axi4_mm.config_t;
    stream_config_c : nsl_video.pixel_stream.config_t;
    burst_length_l2_c : natural := 4;
    buffer_depth_c : positive := 256;
    size_width_c : positive := 16;
    line_repeat_c : positive := 1
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    base_i : in unsigned(mem_config_c.address_width-1 downto 0);
    stride_i : in unsigned(mem_config_c.address_width-1 downto 0);
    width_i : in unsigned(size_width_c-1 downto 0);
    height_i : in unsigned(size_width_c-1 downto 0);
    start_i : in std_ulogic;
    ready_o : out std_ulogic;

    done_o : out std_ulogic;
    status_o : out nsl_video.vdma.frame_status_t;

    mem_o : out nsl_amba.axi4_mm.master_t;
    mem_i : in nsl_amba.axi4_mm.slave_t;

    stream_o : out nsl_video.pixel_stream.master_t;
    stream_i : in nsl_video.pixel_stream.slave_t
    );
end entity;

architecture beh of vdma_reader is

  constant aw_c : positive := mem_config_c.address_width;
  constant word_l2_c : natural := mem_config_c.data_bus_width_l2;
  constant word_bytes_c : positive := 2 ** word_l2_c;
  constant burst_l2_c : natural := nsl_video.vdma.burst_length_l2(mem_config_c, burst_length_l2_c);
  constant burst_max_c : positive := 2 ** burst_l2_c;
  constant len_w_c : natural := mem_config_c.len_width;

  -- FIFO and gearbox input: one memory word per beat, pixel_stream
  -- user bits.
  constant word_config_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => word_bytes_c,
                                   user => nsl_video.pixel_stream.user_width_c,
                                   keep => true,
                                   last => true);

  subtype addr_t is unsigned(aw_c-1 downto 0);
  subtype size_t is unsigned(size_width_c-1 downto 0);
  subtype word_count_t is unsigned(size_width_c-word_l2_c downto 0);
  subtype repeat_t is natural range 0 to line_repeat_c-1;
  subtype burst_len_t is natural range 1 to burst_max_c;
  subtype credit_t is unsigned(nsl_math.arith.log2(buffer_depth_c) downto 0);

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_PLAN,
    ST_ISSUE,
    ST_WAIT_DATA,
    ST_DONE
    );

  type regs_t is
  record
    state : state_t;

    -- Address side
    line_addr, addr, stride : addr_t;
    width_words, words_left : word_count_t;
    lines_left : size_t;
    repeat_left : repeat_t;
    len : burst_len_t;
    credits : credit_t;
    pop_pending : boolean;

    -- Data side
    last_keep : std_ulogic_vector(0 to word_bytes_c-1);
    r_words_left : word_count_t;
    r_lines_left : size_t;
    r_repeat_left : repeat_t;
    r_first : boolean;
    r_done : boolean;
    bus_error : boolean;
  end record;

  signal r, rin : regs_t;

  signal data_in_s, data_out_s : nsl_amba.axi4_stream.bus_t;

  function align(a : unsigned) return addr_t
  is
    variable ret : addr_t := a;
  begin
    ret(word_l2_c-1 downto 0) := (others => '0');
    return ret;
  end function;

  function to_boundary(a : addr_t) return burst_len_t
  is
  begin
    if burst_l2_c = 0 then
      return 1;
    end if;
    return burst_max_c - to_integer(a(word_l2_c+burst_l2_c-1 downto word_l2_c));
  end function;

  function r_is_last_line(r : regs_t) return boolean
  is
  begin
    return r.r_lines_left = 1 and r.r_repeat_left = 0;
  end function;

begin

  assert word_bytes_c <= nsl_amba.axi4_stream.max_data_width_c
    report "Memory data width is too wide for internal stream"
    severity failure;

  assert buffer_depth_c >= burst_max_c and buffer_depth_c >= 4
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

  transition: process(r, start_i, base_i, stride_i, width_i, height_i,
                      mem_i.ar, mem_i.r, data_out_s) is
    variable pop : boolean;
    variable width_words : word_count_t;
    variable rem_bytes : natural range 0 to word_bytes_c-1;
    variable ar_taken : boolean;
  begin
    rin <= r;

    pop := nsl_amba.axi4_stream.is_valid(word_config_c, data_out_s.m)
           and nsl_amba.axi4_stream.is_ready(word_config_c, data_out_s.s);
    ar_taken := r.state = ST_ISSUE and r.credits >= to_unsigned(r.len, credit_t'length)
                and is_ready(mem_config_c, mem_i.ar);

    if ar_taken then
      rin.credits <= r.credits - to_unsigned(r.len, credit_t'length);
      rin.pop_pending <= pop;
    elsif r.pop_pending and pop then
      rin.credits <= r.credits + 2;
      rin.pop_pending <= false;
    elsif r.pop_pending or pop then
      rin.credits <= r.credits + 1;
      rin.pop_pending <= false;
    end if;

    if is_valid(mem_config_c, mem_i.r) then
      if resp(mem_config_c, mem_i.r) = RESP_SLVERR
        or resp(mem_config_c, mem_i.r) = RESP_DECERR then
        rin.bus_error <= true;
      end if;

      rin.r_first <= false;
      rin.r_words_left <= r.r_words_left - 1;
      if r.r_words_left = 1 then
        rin.r_words_left <= r.width_words;
        if r.r_repeat_left /= 0 then
          rin.r_repeat_left <= r.r_repeat_left - 1;
        else
          rin.r_repeat_left <= line_repeat_c - 1;
          rin.r_lines_left <= r.r_lines_left - 1;
          if r.r_lines_left = 1 then
            rin.r_done <= true;
          end if;
        end if;
      end if;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.credits <= to_unsigned(buffer_depth_c, credit_t'length);
        rin.pop_pending <= false;

      when ST_IDLE =>
        if start_i = '1' then
          width_words := resize(shift_right(resize(width_i, size_width_c+1)
                                            + (word_bytes_c - 1), word_l2_c),
                                word_count_t'length);
          rem_bytes := to_integer(width_i(word_l2_c-1 downto 0));

          rin.state <= ST_PLAN;
          rin.line_addr <= align(base_i);
          rin.addr <= align(base_i);
          rin.stride <= align(stride_i);
          rin.width_words <= width_words;
          rin.words_left <= width_words;
          rin.lines_left <= height_i;
          rin.repeat_left <= line_repeat_c - 1;

          for i in 0 to word_bytes_c-1
          loop
            rin.last_keep(i) <= to_logic(rem_bytes = 0 or i < rem_bytes);
          end loop;
          rin.r_words_left <= width_words;
          rin.r_lines_left <= height_i;
          rin.r_repeat_left <= line_repeat_c - 1;
          rin.r_first <= true;
          rin.r_done <= false;
          rin.bus_error <= false;
        end if;

      when ST_PLAN =>
        rin.state <= ST_ISSUE;
        if r.words_left < to_boundary(r.addr) then
          rin.len <= to_integer(r.words_left);
        else
          rin.len <= to_boundary(r.addr);
        end if;

      when ST_ISSUE =>
        if ar_taken then
          rin.state <= ST_PLAN;
          rin.addr <= r.addr + r.len * word_bytes_c;
          rin.words_left <= r.words_left - r.len;

          if r.words_left = r.len then
            rin.words_left <= r.width_words;
            if r.repeat_left /= 0 then
              rin.repeat_left <= r.repeat_left - 1;
              rin.addr <= r.line_addr;
            elsif r.lines_left = 1 then
              rin.state <= ST_WAIT_DATA;
            else
              rin.repeat_left <= line_repeat_c - 1;
              rin.lines_left <= r.lines_left - 1;
              rin.line_addr <= r.line_addr + r.stride;
              rin.addr <= r.line_addr + r.stride;
            end if;
          end if;
        end if;

      when ST_WAIT_DATA =>
        if r.r_done then
          rin.state <= ST_DONE;
        end if;

      when ST_DONE =>
        rin.state <= ST_IDLE;
    end case;
  end process;

  moore: process(r) is
  begin
    ready_o <= to_logic(r.state = ST_IDLE);
    done_o <= to_logic(r.state = ST_DONE);
    status_o.complete <= to_logic(not r.bus_error);
    status_o.truncated <= '0';
    status_o.line_error <= '0';
    status_o.overflow <= '0';
    status_o.bus_error <= to_logic(r.bus_error);

    mem_o.ar <= address(mem_config_c,
                        addr => r.addr,
                        len_m1 => to_unsigned(r.len - 1, len_w_c),
                        size_l2 => to_unsigned(word_l2_c, 3),
                        burst => BURST_INCR,
                        valid => r.state = ST_ISSUE and r.credits >= to_unsigned(r.len, credit_t'length));
    mem_o.r <= accept(mem_config_c, true);
    mem_o.aw <= address_defaults(mem_config_c);
    mem_o.w <= write_data_defaults(mem_config_c);
    mem_o.b <= accept(mem_config_c, false);
  end process;

  mealy: process(r, mem_i.r) is
    variable keep : std_ulogic_vector(0 to word_bytes_c-1);
    variable user : std_ulogic_vector(nsl_video.pixel_stream.user_width_c-1 downto 0);
  begin
    keep := (others => '1');
    if r.r_words_left = 1 then
      keep := r.last_keep;
    end if;

    user := (others => '0');
    user(nsl_video.pixel_stream.user_sof_c) := to_logic(r.r_first);
    user(nsl_video.pixel_stream.user_eof_c) := to_logic(r.r_words_left = 1 and r_is_last_line(r));

    data_in_s.m <= nsl_amba.axi4_stream.transfer(
      word_config_c,
      bytes => bytes(mem_config_c, mem_i.r),
      keep => keep,
      user => user,
      valid => is_valid(mem_config_c, mem_i.r),
      last => r.r_words_left = 1);
  end process;

  -- pragma translate_off
  overrun_check: process(clock_i) is
  begin
    if rising_edge(clock_i) then
      assert not (data_in_s.m.valid = '1' and data_in_s.s.ready = '0')
        report "Read data FIFO overrun, credit accounting is broken"
        severity failure;
      assert r.state = ST_RESET or r.credits <= buffer_depth_c
        report "More credits than FIFO slots"
        severity failure;
    end if;
  end process;
  -- pragma translate_on

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

  gearbox: nsl_video.vdma.vdma_gearbox
    generic map(
      in_config_c => word_config_c,
      out_config_c => stream_config_c.stream
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => data_out_s.m,
      in_o => data_out_s.s,

      out_o => stream_o,
      out_i => stream_i
      );

end architecture;
