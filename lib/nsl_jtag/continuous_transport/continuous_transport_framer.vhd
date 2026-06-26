library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_data;
use nsl_data.bytestream.all;
use nsl_jtag.continuous_transport.all;

-- Transmit framer for continuous_transport (TCK domain).
--
-- Produces the payload byte stream the serializer emits after the SOF. It
-- drains the TX FIFO into a staging buffer (so a length-prefixed data header
-- can be emitted with the chunk count and last flag known up front), then
-- emits data frames gated by the TX budget. When no data frame can be started
-- (no chunk, or not enough budget to finish one) it emits credit refreshes as
-- filler, keeping the ATE's RX credit fresh.
--
-- The budget opens each batch at zero (capture) and is set absolutely by the
-- ATE's credit grants; every emitted byte (signalled by byte_ready_i) spends
-- one unit until it reaches zero (danger zone), after which only filler flows.
-- A data frame is only started when the whole frame fits the remaining budget,
-- so payload never lands in the untransmitted tail of a batch.
entity continuous_transport_framer is
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    -- Batch start: budget back to zero, emission restarts with control.
    capture_i : in  std_ulogic;

    -- One payload byte was latched by the serializer; advance and present
    -- the next byte.
    byte_ready_i : in  std_ulogic;
    byte_o       : out byte;

    -- TX budget grant from the deframer (absolute).
    budget_set_i : in  std_ulogic;
    budget_i     : in  unsigned(credit_bits_c-1 downto 0);

    -- TX FIFO read side (system -> TCK).
    tx_data_i  : in  byte;
    tx_last_i  : in  std_ulogic;
    tx_valid_i : in  std_ulogic;
    tx_ready_o : out std_ulogic;

    -- RX FIFO free space to advertise to the ATE (credit frames).
    rx_free_i : in  unsigned(credit_bits_c-1 downto 0);

    -- TX backlog (FIFO occupancy) to advertise to the ATE (tx-level frames):
    -- after each end-of-packet, and as the idle filler when empty so the ATE
    -- reliably learns it can stop clocking.
    tx_level_i : in  unsigned(credit_bits_c-1 downto 0)
    );
end entity;

architecture beh of continuous_transport_framer is

  type chunker_state_t is (
    CHUNKER_START,
    CHUNKER_EMPTY,
    CHUNKER_FILL,
    CHUNKER_ALIGN,
    CHUNKER_FLUSH
    );

  type sender_state_t is (
    SENDER_IDLE,
    SENDER_CREDIT_OP,
    SENDER_CREDIT_LSB,
    SENDER_CREDIT_MSB,
    SENDER_LEVEL_OP,
    SENDER_LEVEL_LSB,
    SENDER_LEVEL_MSB,
    SENDER_DATA_OP,
    SENDER_DATA
    );

  type regs_t is
  record
    chunk : byte_string(0 to data_bytes_max_c-1);
    chunker_state: chunker_state_t;
    chunk_len_m1, aligner_left_m1 : unsigned(data_bytes_max_l2_c downto 0);
    chunk_last: std_ulogic;

    budget : integer range 0 to 2**credit_bits_c-1;
    sender_state : sender_state_t;
    sender_left_m1 : unsigned(data_bytes_max_l2_c-1 downto 0);
    sender_last : std_ulogic;
    rx_credit : unsigned(credit_bits_c-1 downto 0);
    tx_level : unsigned(credit_bits_c-1 downto 0);
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.sender_state <= SENDER_IDLE;
      r.chunker_state <= CHUNKER_START;
    end if;
  end process;

  transition: process(r, capture_i, byte_ready_i,
                      budget_set_i, budget_i,
                      tx_data_i, tx_last_i, tx_valid_i, rx_free_i, tx_level_i)
  begin
    rin <= r;

    case r.chunker_state is
      when CHUNKER_START =>
        rin.chunker_state <= CHUNKER_EMPTY;

      when CHUNKER_EMPTY =>
        if tx_valid_i = '1' then
          rin.chunker_state <= CHUNKER_FILL;
          rin.chunk <= shift_left(r.chunk, tx_data_i);
          rin.chunk_len_m1 <= (others => '0');
          -- With 1 byte in the buffer, we have to realign for size-2 times.
          rin.aligner_left_m1 <= to_unsigned(data_bytes_max_c-2, rin.aligner_left_m1'length);
          rin.chunk_last <= tx_last_i;
          if tx_last_i = '1' then
            -- Unaligned fulll packet
            rin.chunker_state <= CHUNKER_ALIGN;
          end if;
        end if;

      when CHUNKER_FILL =>
        if tx_valid_i = '1' then
          rin.chunk <= shift_left(r.chunk, tx_data_i);
          rin.chunk_len_m1 <= r.chunk_len_m1 + 1;
          rin.aligner_left_m1 <= r.aligner_left_m1 - 1;
          rin.chunk_last <= tx_last_i;
          if tx_last_i = '1' then
            if r.chunk_len_m1 = data_bytes_max_c - 2 then
              -- Aligned full packet
              rin.chunker_state <= CHUNKER_FLUSH;
            else
              -- Unaligned fulll packet
              rin.chunker_state <= CHUNKER_ALIGN;
            end if;
          elsif r.chunk_len_m1 = data_bytes_max_c - 2 then
            -- Full packet
            rin.chunker_state <= CHUNKER_FLUSH;
          end if;
        else
          -- Unaligned partial packet
          rin.chunker_state <= CHUNKER_ALIGN;
        end if;

      when CHUNKER_ALIGN =>
        if r.aligner_left_m1 /= 0 then
          rin.aligner_left_m1 <= r.aligner_left_m1 - 1;
        else
          rin.chunker_state <= CHUNKER_FLUSH;
        end if;
        rin.chunk <= shift_left(r.chunk);

      when CHUNKER_FLUSH =>
        -- There is no requirement the sender actually sends the data chunk in
        -- one go. If credit is too low, we'll send partial chunk with the
        -- proper data header.
        --
        -- That means we'll not flush the whole chunk in one run of
        -- SENDER_DATA state. We'll stay here and wait for sender to send the
        -- whole chunk before we fill again.
        if r.sender_state = SENDER_DATA and byte_ready_i = '1' then
          rin.chunk <= shift_left(r.chunk);
          if r.chunk_len_m1 = 0 then
            rin.chunker_state <= CHUNKER_START;
          else
            rin.chunk_len_m1 <= r.chunk_len_m1 - 1;
          end if;
        end if;
    end case;

    case r.sender_state is
      when SENDER_IDLE =>
        -- Dont wait for byte_ready_i here. We may move out of this
        -- state any time.
        if r.chunker_state = CHUNKER_FLUSH then
          if r.budget /= 0 then
            rin.sender_state <= SENDER_DATA_OP;
            if r.chunk_len_m1 > r.budget then
              rin.sender_left_m1 <= to_unsigned(r.budget, rin.sender_left_m1'length);
              rin.sender_last <= '0';
            else
              rin.sender_left_m1 <= resize(r.chunk_len_m1, rin.sender_left_m1'length);
              -- The whole chunk fits, but it is only an end-of-packet if the
              -- chunk actually ended on one (a partial chunk flushed on a TX
              -- bubble has chunk_last = '0').
              rin.sender_last <= r.chunk_last;
            end if;
          end if;
        elsif rin.rx_credit /= rx_free_i then
          -- Credit is dirty, update it.
          rin.sender_state <= SENDER_CREDIT_OP;
        elsif tx_level_i = 0 then
          -- Nothing queued: advertise the empty backlog in place of idle, so
          -- the ATE keeps a fresh "you can stop clocking" signal even if the
          -- end-of-packet tx-level was lost in a truncated batch tail.
          rin.sender_state <= SENDER_LEVEL_OP;
        end if;

      when SENDER_CREDIT_OP =>
        if byte_ready_i = '1' then
          rin.sender_state <= SENDER_CREDIT_LSB;
          rin.rx_credit <= rx_free_i;
        end if;

      when SENDER_CREDIT_LSB =>
        if byte_ready_i = '1' then
          rin.sender_state <= SENDER_CREDIT_MSB;
        end if;

      when SENDER_CREDIT_MSB =>
        if byte_ready_i = '1' then
          rin.sender_state <= SENDER_IDLE;
        end if;

      when SENDER_LEVEL_OP =>
        if byte_ready_i = '1' then
          rin.sender_state <= SENDER_LEVEL_LSB;
          rin.tx_level <= tx_level_i;
        end if;

      when SENDER_LEVEL_LSB =>
        if byte_ready_i = '1' then
          rin.sender_state <= SENDER_LEVEL_MSB;
        end if;

      when SENDER_LEVEL_MSB =>
        if byte_ready_i = '1' then
          rin.sender_state <= SENDER_IDLE;
        end if;

      when SENDER_DATA_OP =>
        if byte_ready_i = '1' then
          rin.sender_state <= SENDER_DATA;
        end if;

      when SENDER_DATA =>
        if byte_ready_i = '1' then
          assert r.chunker_state = CHUNKER_FLUSH
            report "Bad sibling FSM state"
            severity failure;
          if r.sender_left_m1 = 0 then
            -- After an end-of-packet chunk, advertise the remaining backlog;
            -- a budget-limited partial chunk (sender_last = '0') is mid-packet,
            -- so just go back to a credit refresh.
            if r.sender_last = '1' then
              rin.sender_state <= SENDER_LEVEL_OP;
            else
              rin.sender_state <= SENDER_CREDIT_OP;
            end if;
          else
            rin.sender_left_m1 <= r.sender_left_m1 - 1;
          end if;
        end if;
    end case;

    if capture_i = '1' then
      -- Batch start: drop budget and restart the sender. Each batch is
      -- self-framed (SOF then a fresh header), so a data frame left mid-body
      -- by a truncated previous batch must be re-headered for its remainder
      -- rather than continued headerless. The chunker keeps the unsent chunk,
      -- so SENDER_IDLE re-emits a header for what is left.
      rin.budget <= 0;
      rin.rx_credit <= (others => '0');
      rin.sender_state <= SENDER_IDLE;
    elsif budget_set_i = '1' then
      -- Absolute budget grant from the ATE (overrides the spend above).
      rin.budget <= to_integer(budget_i);
    elsif byte_ready_i = '1' and r.budget /= 0 then
      rin.budget <= r.budget - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    tx_ready_o <= '0';

    case r.chunker_state is
      when CHUNKER_START | CHUNKER_ALIGN | CHUNKER_FLUSH =>
        null;

      when CHUNKER_FILL | CHUNKER_EMPTY =>
        tx_ready_o <= '1';
    end case;

    case r.sender_state is
      when SENDER_IDLE =>
        byte_o <= ctl_idle_c;

      when SENDER_CREDIT_OP =>
        byte_o <= ctl_credit_c;

      when SENDER_CREDIT_LSB =>
        byte_o <= std_ulogic_vector(r.rx_credit(7 downto 0));

      when SENDER_CREDIT_MSB =>
        byte_o <= std_ulogic_vector(r.rx_credit(15 downto 8));

      when SENDER_LEVEL_OP =>
        byte_o <= ctl_tx_level_c;

      when SENDER_LEVEL_LSB =>
        byte_o <= std_ulogic_vector(r.tx_level(7 downto 0));

      when SENDER_LEVEL_MSB =>
        byte_o <= std_ulogic_vector(r.tx_level(15 downto 8));

      when SENDER_DATA_OP =>
        byte_o(7) <= '0';
        byte_o(6) <= r.sender_last;
        byte_o(5 downto 0) <= std_ulogic_vector(r.sender_left_m1);

      when SENDER_DATA =>
        byte_o <= first_left(r.chunk);
    end case;
  end process;

end architecture;
