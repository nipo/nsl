library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;
use nsl_bnoc.chunked_link.all;

-- Slave-side transmit framer for chunked_link.
--
-- Produces the byte stream the transport serialises toward the master. It
-- stages the TX stream through a chunker (so a length-prefixed data header can
-- be emitted with the chunk count and last flag known up front), then emits
-- data frames gated by the TX budget. When no data frame can be started (no
-- chunk, or not enough budget to finish one) it emits credit refreshes as
-- filler, keeping the master's RX credit fresh.
--
-- The budget opens each batch at zero and is set absolutely by the master's
-- credit grants; every emitted byte (signalled by byte_ready_i) spends one
-- unit until it reaches zero, after which only filler flows. A data frame is
-- sized so that header and body both fit the remaining budget, so payload
-- never lands in the untransmitted tail of a batch.
entity chunked_link_slave_framer is
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    -- Batch start: budget back to zero, emission restarts with control.
    batch_start_i : in std_ulogic;

    -- One byte was latched by the transport; advance and present the next
    -- byte.
    byte_ready_i : in  std_ulogic;
    byte_o       : out byte;

    -- TX budget grant from the deframer (absolute).
    budget_set_i : in  std_ulogic;
    budget_i     : in  unsigned(credit_bits_c-1 downto 0);

    -- TX stream (payload to send).
    tx_data_i  : in  byte;
    tx_last_i  : in  std_ulogic;
    tx_valid_i : in  std_ulogic;
    tx_ready_o : out std_ulogic;

    -- RX buffer free space to advertise to the master (credit frames).
    rx_free_i : in  unsigned(credit_bits_c-1 downto 0);

    -- TX backlog to advertise to the master (tx-level frames): after each
    -- end-of-packet, and in place of idle whenever the value changed
    -- since last advertised.
    tx_level_i : in  unsigned(credit_bits_c-1 downto 0)
    );
end entity;

architecture beh of chunked_link_slave_framer is

  -- Budget spent by a data frame on top of its body: the header byte, plus the
  -- filler byte that may still be latched out of ST_IDLE in the cycle the
  -- frame is decided.
  constant frame_overhead_c : integer := 2;

  type state_t is (
    ST_IDLE,
    ST_CREDIT_OP,
    ST_CREDIT_LSB,
    ST_CREDIT_MSB,
    ST_LEVEL_OP,
    ST_LEVEL_LSB,
    ST_LEVEL_MSB,
    ST_DATA_OP,
    ST_DATA
    );

  type regs_t is
  record
    budget : integer range 0 to 2**credit_bits_c-1;
    state : state_t;
    left_m1 : unsigned(data_bytes_max_l2_c-1 downto 0);
    last : std_ulogic;
    rx_credit : unsigned(credit_bits_c-1 downto 0);
    tx_level : unsigned(credit_bits_c-1 downto 0);
  end record;

  signal r, rin : regs_t;

  signal chunk_valid_s : std_ulogic;
  signal chunk_byte_s : byte;
  signal chunk_len_m1_s : unsigned(data_bytes_max_l2_c-1 downto 0);
  signal chunk_last_s : std_ulogic;
  signal chunk_next_s : std_ulogic;

begin

  chunker: chunked_link_chunker
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      tx_data_i => tx_data_i,
      tx_last_i => tx_last_i,
      tx_valid_i => tx_valid_i,
      tx_ready_o => tx_ready_o,
      chunk_valid_o => chunk_valid_s,
      chunk_byte_o => chunk_byte_s,
      chunk_len_m1_o => chunk_len_m1_s,
      chunk_last_o => chunk_last_s,
      chunk_next_i => chunk_next_s
      );

  chunk_next_s <= byte_ready_i when r.state = ST_DATA else '0';

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.rx_credit <= (others => '0');
      r.tx_level <= (others => '1');
    end if;
  end process;

  transition: process(r, batch_start_i, byte_ready_i,
                      budget_set_i, budget_i,
                      chunk_valid_s, chunk_len_m1_s, chunk_last_s,
                      rx_free_i, tx_level_i)
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        -- Dont wait for byte_ready_i here. We may move out of this
        -- state any time.
        if chunk_valid_s = '1' then
          -- A data frame spends budget on its header as well as on its body,
          -- and one more filler byte may still be latched out of this state
          -- before the header reaches byte_o. So a body of n bytes needs a
          -- budget of n+2; anything above that would be emitted past the
          -- guarantee and land in the untransmitted tail of the batch.
          if r.budget > frame_overhead_c then
            rin.state <= ST_DATA_OP;
            if chunk_len_m1_s > r.budget - frame_overhead_c - 1 then
              rin.left_m1 <= to_unsigned(r.budget - frame_overhead_c - 1,
                                         r.left_m1'length);
              rin.last <= '0';
            else
              rin.left_m1 <= chunk_len_m1_s;
              -- The whole chunk fits, but it is only an end-of-packet if the
              -- chunk actually ended on one (a partial chunk flushed on a TX
              -- bubble has chunk_last = '0').
              rin.last <= chunk_last_s;
            end if;
          end if;
        elsif r.rx_credit /= rx_free_i then
          -- Credit is dirty, update it.
          rin.state <= ST_CREDIT_OP;
        elsif r.tx_level /= tx_level_i then
          -- Backlog changed since last advertised: tell the master, so it
          -- can size its budget grants (a budget-starved backlog would
          -- otherwise stay invisible) and reliably learn it can stop
          -- clocking once the backlog reaches zero.
          rin.state <= ST_LEVEL_OP;
        end if;

      when ST_CREDIT_OP =>
        if byte_ready_i = '1' then
          rin.state <= ST_CREDIT_LSB;
          rin.rx_credit <= rx_free_i;
        end if;

      when ST_CREDIT_LSB =>
        if byte_ready_i = '1' then
          rin.state <= ST_CREDIT_MSB;
        end if;

      when ST_CREDIT_MSB =>
        if byte_ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_LEVEL_OP =>
        if byte_ready_i = '1' then
          rin.state <= ST_LEVEL_LSB;
          rin.tx_level <= tx_level_i;
        end if;

      when ST_LEVEL_LSB =>
        if byte_ready_i = '1' then
          rin.state <= ST_LEVEL_MSB;
        end if;

      when ST_LEVEL_MSB =>
        if byte_ready_i = '1' then
          rin.state <= ST_IDLE;
        end if;

      when ST_DATA_OP =>
        if byte_ready_i = '1' then
          rin.state <= ST_DATA;
        end if;

      when ST_DATA =>
        if byte_ready_i = '1' then
          assert chunk_valid_s = '1'
            report "Chunk consumed under a running data frame"
            severity failure;
          if r.left_m1 = 0 then
            -- After an end-of-packet chunk, advertise the remaining backlog;
            -- a budget-limited partial chunk (last = '0') is mid-packet, so
            -- just go back to a credit refresh.
            if r.last = '1' then
              rin.state <= ST_LEVEL_OP;
            else
              rin.state <= ST_CREDIT_OP;
            end if;
          else
            rin.left_m1 <= r.left_m1 - 1;
          end if;
        end if;
    end case;

    if batch_start_i = '1' then
      -- Batch start: drop budget and restart the sender. Each batch is
      -- self-framed, so a data frame left mid-body by a truncated previous
      -- batch must be re-headered for its remainder rather than continued
      -- headerless. The chunker keeps the unsent chunk, so ST_IDLE re-emits
      -- a header for what is left.
      rin.budget <= 0;
      rin.rx_credit <= (others => '0');
      -- Mark the level dirty so each batch re-advertises the backlog even
      -- if the previous advertisement fell in a truncated batch tail.
      rin.tx_level <= (others => '1');
      rin.state <= ST_IDLE;
    elsif budget_set_i = '1' then
      -- Absolute budget grant from the master (overrides the spend above).
      rin.budget <= to_integer(budget_i);
    elsif byte_ready_i = '1' and r.budget /= 0 then
      rin.budget <= r.budget - 1;
    end if;
  end process;

  moore: process(r, chunk_byte_s) is
  begin
    case r.state is
      when ST_IDLE =>
        byte_o <= ctl_idle_c;

      when ST_CREDIT_OP =>
        byte_o <= ctl_credit_c;

      when ST_CREDIT_LSB =>
        byte_o <= std_ulogic_vector(r.rx_credit(7 downto 0));

      when ST_CREDIT_MSB =>
        byte_o <= std_ulogic_vector(r.rx_credit(15 downto 8));

      when ST_LEVEL_OP =>
        byte_o <= ctl_tx_level_c;

      when ST_LEVEL_LSB =>
        byte_o <= std_ulogic_vector(r.tx_level(7 downto 0));

      when ST_LEVEL_MSB =>
        byte_o <= std_ulogic_vector(r.tx_level(15 downto 8));

      when ST_DATA_OP =>
        byte_o(7) <= '0';
        byte_o(6) <= r.last;
        byte_o(5 downto 0) <= std_ulogic_vector(r.left_m1);

      when ST_DATA =>
        byte_o <= chunk_byte_s;
    end case;
  end process;

end architecture;
