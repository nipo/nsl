library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_stream_sized_deframing_1b is
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
  assert out_config_c.data_width = 1
    report "out_config_c data_width must be 1"
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
  assert in_config_c.has_strobe = out_config_c.has_strobe
    report "in/out has_strobe must match"
    severity failure;
  assert max_frame_size_c >= 4
    report "max_frame_size_c must be at least 4"
    severity failure;
end entity;

architecture rtl of axi4_stream_sized_deframing_1b is

  -- FIFO config: 1-byte, same sideband as in/out, no last needed (we use count).
  constant fifo_config_c : config_t := config(
    bytes  => 1,
    id     => in_config_c.id_width,
    user   => in_config_c.user_width,
    dest   => in_config_c.dest_width,
    keep   => in_config_c.has_keep,
    strobe => in_config_c.has_strobe,
    last   => false
    );

  type state_t is (
    STATE_RESET,
    STATE_DATA,
    STATE_HEADER,
    STATE_FLUSH
    );

  type regs_t is record
    state      : state_t;
    -- Counts bytes received, starting at all-ones (-1), so after N bytes
    -- count = N-1, which is the off-by-one header value directly.
    count      : unsigned(31 downto 0);
    header_idx : natural range 0 to 3;
    first_byte : boolean;
    -- Sideband captured from the first byte of each input frame, replayed
    -- on the header bytes.
    cap        : master_t;
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
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state      <= STATE_DATA;
        rin.count      <= (others => '1');
        rin.first_byte <= true;
        rin.header_idx <= 0;

      when STATE_DATA =>
        if is_valid(in_config_c, in_i) and is_ready(fifo_config_c, fifo_in_ss) then
          if r.first_byte then
            rin.cap        <= in_i;
            rin.first_byte <= false;
          end if;
          rin.count <= r.count + 1;
          if is_last(in_config_c, in_i) then
            rin.state      <= STATE_HEADER;
            rin.header_idx <= 0;
          end if;
        end if;

      when STATE_HEADER =>
        if is_ready(out_config_c, out_i) then
          if r.header_idx = header_length_c - 1 then
            rin.state      <= STATE_FLUSH;
            rin.header_idx <= 0;
          else
            rin.header_idx <= r.header_idx + 1;
          end if;
        end if;

      when STATE_FLUSH =>
        if is_valid(fifo_config_c, fifo_out_ms) and is_ready(out_config_c, out_i) then
          if r.count = 0 then
            rin.state      <= STATE_DATA;
            rin.count      <= (others => '1');
            rin.first_byte <= true;
          else
            rin.count <= r.count - 1;
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
    variable out_byte : byte;
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

      when STATE_HEADER =>
        out_byte := (others => '-');
        for byte_n in 0 to header_length_c - 1 loop
          if r.header_idx = byte_n then
            if endian_c = ENDIAN_LITTLE then
              out_byte := std_ulogic_vector(
                r.count(byte_n * 8 + 7 downto byte_n * 8));
            else
              out_byte := std_ulogic_vector(
                r.count((header_length_c - 1 - byte_n) * 8 + 7
                         downto (header_length_c - 1 - byte_n) * 8));
            end if;
          end if;
        end loop;
        out_o <= transfer(out_config_c,
                          bytes => byte_string'(0 => out_byte),
                          id    => id(in_config_c, r.cap),
                          user  => user(in_config_c, r.cap),
                          dest  => dest(in_config_c, r.cap),
                          valid => true);

      when STATE_FLUSH =>
        out_o <= transfer(out_config_c, fifo_out_ms,
                          force_last => out_config_c.has_last,
                          last       => r.count = 0);
        fifo_out_ss <= accept(fifo_config_c, is_ready(out_config_c, out_i));
    end case;
  end process;

end architecture;
