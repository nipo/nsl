library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;
use nsl_bnoc.chunked_link.all;

-- Chunk staging buffer for chunked_link senders.
--
-- Drains the TX stream into a fixed-size shift buffer so a frame sender can
-- emit a length-prefixed data header with the byte count and last flag known
-- up front. The buffer is filled left-aligned; a chunk that closes short of
-- data_bytes_max_c bytes (end-of-packet or TX bubble) is then shifted until
-- its first byte reaches the output position.
--
-- The sender may consume the chunk over several data frames (a
-- budget/credit-limited frame takes only part of it); the chunk stays
-- presented until fully consumed, refilling only afterwards.
entity chunked_link_chunker is
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    tx_data_i  : in  byte;
    tx_last_i  : in  std_ulogic;
    tx_valid_i : in  std_ulogic;
    tx_ready_o : out std_ulogic;

    chunk_valid_o  : out std_ulogic;
    chunk_byte_o   : out byte;
    chunk_len_m1_o : out unsigned(data_bytes_max_l2_c-1 downto 0);
    chunk_last_o   : out std_ulogic;
    chunk_next_i   : in  std_ulogic
    );
end entity;

architecture beh of chunked_link_chunker is

  type state_t is (
    ST_START,
    ST_EMPTY,
    ST_FILL,
    ST_ALIGN,
    ST_FLUSH
    );

  type regs_t is
  record
    state : state_t;
    chunk : byte_string(0 to data_bytes_max_c-1);
    len_m1, aligner_left_m1 : unsigned(data_bytes_max_l2_c-1 downto 0);
    last : std_ulogic;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_START;
    end if;
  end process;

  transition: process(r, tx_data_i, tx_last_i, tx_valid_i, chunk_next_i)
  begin
    rin <= r;

    case r.state is
      when ST_START =>
        rin.state <= ST_EMPTY;

      when ST_EMPTY =>
        if tx_valid_i = '1' then
          rin.state <= ST_FILL;
          rin.chunk <= shift_left(r.chunk, tx_data_i);
          rin.len_m1 <= (others => '0');
          -- With 1 byte in the buffer, we have to realign for size-2 times.
          rin.aligner_left_m1 <= to_unsigned(data_bytes_max_c-2, r.aligner_left_m1'length);
          rin.last <= tx_last_i;
          if tx_last_i = '1' then
            -- Unaligned full packet
            rin.state <= ST_ALIGN;
          end if;
        end if;

      when ST_FILL =>
        if tx_valid_i = '1' then
          rin.chunk <= shift_left(r.chunk, tx_data_i);
          rin.len_m1 <= r.len_m1 + 1;
          rin.aligner_left_m1 <= r.aligner_left_m1 - 1;
          rin.last <= tx_last_i;
          if tx_last_i = '1' then
            if r.len_m1 = data_bytes_max_c - 2 then
              -- Aligned full packet
              rin.state <= ST_FLUSH;
            else
              -- Unaligned full packet
              rin.state <= ST_ALIGN;
            end if;
          elsif r.len_m1 = data_bytes_max_c - 2 then
            -- Full packet
            rin.state <= ST_FLUSH;
          end if;
        else
          -- Unaligned partial packet
          rin.state <= ST_ALIGN;
        end if;

      when ST_ALIGN =>
        if r.aligner_left_m1 /= 0 then
          rin.aligner_left_m1 <= r.aligner_left_m1 - 1;
        else
          rin.state <= ST_FLUSH;
        end if;
        rin.chunk <= shift_left(r.chunk);

      when ST_FLUSH =>
        if chunk_next_i = '1' then
          rin.chunk <= shift_left(r.chunk);
          if r.len_m1 = 0 then
            rin.state <= ST_START;
          else
            rin.len_m1 <= r.len_m1 - 1;
          end if;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    tx_ready_o <= '0';
    chunk_valid_o <= '0';

    case r.state is
      when ST_START | ST_ALIGN =>
        null;

      when ST_FILL | ST_EMPTY =>
        tx_ready_o <= '1';

      when ST_FLUSH =>
        chunk_valid_o <= '1';
    end case;

    chunk_byte_o <= first_left(r.chunk);
    chunk_len_m1_o <= r.len_m1;
    chunk_last_o <= r.last;
  end process;

end architecture;
