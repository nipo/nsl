library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_stream_sized_deframing_1b_to_nb is
  generic(
    in_config_c      : config_t;
    out_config_c     : config_t;
    header_length_c  : positive range 1 to 4 := 2;
    endian_c         : endian_t := ENDIAN_LITTLE;
    max_frame_size_c : natural := 2048
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    in_i  : in  master_t;
    in_o  : out slave_t;

    out_o : out master_t;
    out_i : in  slave_t
    );
begin
  assert in_config_c.data_width = 1
    report "in_config_c data_width must be 1"
    severity failure;
  assert in_config_c.has_last
    report "in_config_c must have has_last"
    severity failure;
  assert not out_config_c.has_last
    report "out_config_c must not have has_last"
    severity failure;
  assert in_config_c.id_width = out_config_c.id_width
    report "in/out id_width must match"
    severity failure;
  assert in_config_c.dest_width = out_config_c.dest_width
    report "in/out dest_width must match"
    severity failure;
  assert in_config_c.user_width = out_config_c.user_width
    report "in/out user_width must match"
    severity failure;
  assert in_config_c.has_keep = out_config_c.has_keep
    report "in/out has_keep must match"
    severity failure;
  assert out_config_c.data_width = 1 or out_config_c.has_keep
    report "out_config_c has data_width > 1 without has_keep: partial last words will contain garbage bytes unless all frame sizes keep (header_length_c + data_size) a multiple of out_config_c.data_width"
    severity failure;
  assert in_config_c.has_strobe = out_config_c.has_strobe
    report "in/out has_strobe must match"
    severity failure;
  assert max_frame_size_c >= 4
    report "max_frame_size_c must be at least 4"
    severity failure;
end entity;

architecture rtl of axi4_stream_sized_deframing_1b_to_nb is

  -- FIFO: 1-byte, same sideband as in/out, no last needed (we use count).
  constant fifo_config_c : config_t := config(
    bytes  => 1,
    id     => in_config_c.id_width,
    user   => in_config_c.user_width,
    dest   => in_config_c.dest_width,
    keep   => in_config_c.has_keep,
    strobe => in_config_c.has_strobe,
    last   => false
    );

  -- Buffer config for one output word: one-byte "stream", data_width bytes wide.
  -- buf_cfg_c.beat_count = out_config_c.data_width.
  -- beats_to_go counts from data_width-1 down to 0 as the word fills;
  -- position = buf_cfg_c.beat_count - 1 - beats_to_go gives the fill index.
  -- is_last(buf_cfg_c, out_word) is true when the last byte slot is being filled.
  -- reset(buf_cfg_c) zeros all strobe bits, so unfilled slots in a partial last
  -- word remain 0 without an explicit clearing loop.
  constant buf_cfg_c : buffer_config_t := buffer_config(fifo_config_c, out_config_c.data_width);

  type state_t is (
    STATE_RESET,
    STATE_DATA,
    STATE_EMIT,
    STATE_OUTPUT
    );

  type phase_t is (PHASE_HEADER, PHASE_DATA);

  type regs_t is record
    state      : state_t;
    -- Counts bytes received, starting at all-ones (-1), so after N bytes
    -- count = N-1, which is the off-by-one header value directly.
    -- Reused in STATE_EMIT/PHASE_DATA as the remaining-byte counter:
    -- counts down from N-1 to 0; last data byte when count = 0.
    -- count remains 0 through STATE_OUTPUT so that the last-word check
    -- (r.phase = PHASE_DATA and r.count = 0) stays valid there.
    count      : unsigned(31 downto 0);
    header_idx : natural range 0 to 3;
    -- Sideband for the output word currently being assembled: captured from
    -- fifo_out_ms when the first byte is placed in each word (same source as
    -- in the 1b variant).  Valid for both header and data words: during header
    -- emission the FIFO holds the first frame byte unchanged.
    out_sideband : master_t;
    -- Emit phase: header bytes first, then data bytes from the FIFO.
    phase      : phase_t;
    -- Output word accumulator.  out_word.data holds accumulated bytes filled
    -- from position 0 upward; out_word.strobe holds keep bits (1 = valid,
    -- 0 = padding).  beats_to_go tracks the fill index in reverse
    -- (position = beat_count - 1 - beats_to_go).
    out_word : buffer_t;
    -- Set at the STATE_EMIT→STATE_OUTPUT transition: true when the word being
    -- moved to STATE_OUTPUT contains the last data byte of the frame.  Cannot
    -- be derived from r.count in STATE_OUTPUT because count is decremented to
    -- 0 one word early (when placing the second-to-last byte fills a word).
    out_last : boolean;
  end record;

  signal r, rin : regs_t;

  signal fifo_in_ms  : master_t;
  signal fifo_in_ss  : slave_t;
  signal fifo_out_ms : master_t;
  signal fifo_out_ss : slave_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= STATE_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i, fifo_in_ss, fifo_out_ms) is
    variable next_byte  : byte;
    variable byte_avail : boolean;
    variable position   : natural range 0 to out_config_c.data_width - 1;
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state      <= STATE_DATA;
        rin.count      <= (others => '1');
        rin.header_idx <= 0;

      when STATE_DATA =>
        if is_valid(in_config_c, in_i) and is_ready(fifo_config_c, fifo_in_ss) then
          rin.count <= r.count + 1;
          if is_last(in_config_c, in_i) then
            rin.state      <= STATE_EMIT;
            rin.phase      <= PHASE_HEADER;
            rin.header_idx <= 0;
            rin.out_word   <= reset(buf_cfg_c);
          end if;
        end if;

      when STATE_EMIT =>
        byte_avail := false;
        next_byte  := (others => '-');
        position   := buf_cfg_c.beat_count - 1 - r.out_word.beats_to_go;

        if r.phase = PHASE_HEADER then
          -- Header bytes are available immediately from r.count.
          byte_avail := true;
          next_byte  := (others => '-');
          for byte_n in 0 to header_length_c - 1 loop
            if r.header_idx = byte_n then
              if endian_c = ENDIAN_LITTLE then
                next_byte := std_ulogic_vector(
                  r.count(byte_n * 8 + 7 downto byte_n * 8));
              else
                next_byte := std_ulogic_vector(
                  r.count((header_length_c - 1 - byte_n) * 8 + 7
                           downto (header_length_c - 1 - byte_n) * 8));
              end if;
            end if;
          end loop;
        elsif is_valid(fifo_config_c, fifo_out_ms) then
          byte_avail := true;
          next_byte  := bytes(fifo_config_c, fifo_out_ms)(0);
        end if;

        if byte_avail then
          if position = 0 then
            rin.out_sideband <= fifo_out_ms;
          end if;
          rin.out_word.data(position)   <= next_byte;
          rin.out_word.strobe(position) <= '1';

          if r.phase = PHASE_HEADER then
            if r.header_idx = header_length_c - 1 then
              rin.phase      <= PHASE_DATA;
              rin.header_idx <= 0;
            else
              rin.header_idx <= r.header_idx + 1;
            end if;
          elsif r.count /= 0 then
            rin.count <= r.count - 1;
          end if;

          if is_last(buf_cfg_c, r.out_word) or (r.phase = PHASE_DATA and r.count = 0) then
            rin.state    <= STATE_OUTPUT;
            rin.out_last <= r.phase = PHASE_DATA and r.count = 0;
          else
            rin.out_word.beats_to_go <= r.out_word.beats_to_go - 1;
          end if;
        end if;

      when STATE_OUTPUT =>
        if is_ready(out_config_c, out_i) then
          if r.out_last then
            rin.state <= STATE_DATA;
            rin.count <= (others => '1');
          else
            rin.state    <= STATE_EMIT;
            rin.out_word <= reset(buf_cfg_c);
          end if;
        end if;
    end case;
  end process;

  data_fifo: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c      => fifo_config_c,
      depth_c       => max_frame_size_c,
      clock_count_c => 1
      )
    port map(
      clock_i(0)      => clock_i,
      reset_n_i       => reset_n_i,
      in_i            => fifo_in_ms,
      in_o            => fifo_in_ss,
      in_free_o       => open,
      out_o           => fifo_out_ms,
      out_i           => fifo_out_ss,
      out_available_o => open
      );

  mealy: process(r, in_i, out_i, fifo_in_ss, fifo_out_ms) is
  begin
    out_o       <= transfer_defaults(out_config_c);
    fifo_in_ms  <= transfer_defaults(fifo_config_c);
    in_o        <= accept(in_config_c, false);
    fifo_out_ss <= accept(fifo_config_c, false);

    case r.state is
      when STATE_RESET =>
        null;

      when STATE_DATA =>
        fifo_in_ms <= transfer(fifo_config_c, in_config_c, in_i);
        in_o       <= accept(in_config_c, is_ready(fifo_config_c, fifo_in_ss));

      when STATE_EMIT =>
        -- Pop the FIFO in the same cycle we consume the data byte.
        if r.phase = PHASE_DATA and is_valid(fifo_config_c, fifo_out_ms) then
          fifo_out_ss <= accept(fifo_config_c, true);
        end if;

      when STATE_OUTPUT =>
        out_o <= transfer(out_config_c,
                          bytes => bytes(buf_cfg_c, r.out_word),
                          keep  => strobe(buf_cfg_c, r.out_word),
                          id    => id(fifo_config_c, r.out_sideband),
                          user  => user(fifo_config_c, r.out_sideband),
                          dest  => dest(fifo_config_c, r.out_sideband),
                          valid => true,
                          last  => r.out_last);
    end case;
  end process;

end architecture;
