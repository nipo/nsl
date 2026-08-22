library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;
use nsl_bnoc.chunked_link.all;

-- Master-side transmit framer for chunked_link.
--
-- Produces the byte stream the transport serialises toward the slave. Data
-- frames are gated by the slave's advertised RX credit: each received credit
-- value is taken as an absolute balance, derated by flight_margin_c to cover
-- data emitted while the credit frame was in flight, then spent by data bytes
-- only (headers and control are not buffered by the slave). A data frame is
-- sized to fit the remaining balance; the rest of the chunk waits for a
-- refresh.
--
-- Budget grants toward the slave go through the grant handshake: the caller
-- decides when to grant and how much, because a grant is a commitment to keep
-- the link clocking. grant_sent_o strobes once the frame's last byte has been
-- latched by the transport, giving the caller the anchor from which its
-- clocking commitment runs.
entity chunked_link_master_framer is
  generic(
    flight_margin_c : natural := 16
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    -- Batch start: emission restarts on a frame boundary. The credit
    -- balance is running and survives batch boundaries.
    batch_start_i : in std_ulogic;

    -- One byte was latched by the transport; advance and present the next
    -- byte.
    byte_ready_i : in  std_ulogic;
    byte_o       : out byte;

    -- Slave RX credit from the deframer (absolute).
    credit_set_i : in  std_ulogic;
    credit_i     : in  unsigned(credit_bits_c-1 downto 0);

    -- TX budget grant to emit toward the slave.
    grant_i       : in  unsigned(credit_bits_c-1 downto 0);
    grant_valid_i : in  std_ulogic;
    grant_ready_o : out std_ulogic;
    grant_sent_o  : out std_ulogic;

    -- TX stream (payload to send).
    tx_data_i  : in  byte;
    tx_last_i  : in  std_ulogic;
    tx_valid_i : in  std_ulogic;
    tx_ready_o : out std_ulogic;

    -- A chunk is staged and not fully sent yet.
    pending_o : out std_ulogic;
    -- A chunk is staged and the credit balance allows sending part of it
    -- now; tells the batch controller more clocking makes TX progress.
    sendable_o : out std_ulogic
    );
end entity;

architecture beh of chunked_link_master_framer is

  type state_t is (
    ST_IDLE,
    ST_GRANT_OP,
    ST_GRANT_LSB,
    ST_GRANT_MSB,
    ST_DATA_OP,
    ST_DATA
    );

  type regs_t is
  record
    state : state_t;
    balance : integer range 0 to 2**credit_bits_c-1;
    grant : unsigned(credit_bits_c-1 downto 0);
    grant_sent : std_ulogic;
    left_m1 : unsigned(data_bytes_max_l2_c-1 downto 0);
    last : std_ulogic;
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
      r.balance <= 0;
      r.grant_sent <= '0';
    end if;
  end process;

  transition: process(r, batch_start_i, byte_ready_i,
                      credit_set_i, credit_i,
                      grant_i, grant_valid_i,
                      chunk_valid_s, chunk_len_m1_s, chunk_last_s)
  begin
    rin <= r;
    rin.grant_sent <= '0';

    case r.state is
      when ST_IDLE =>
        -- Dont wait for byte_ready_i here. We may move out of this
        -- state any time.
        if grant_valid_i = '1' then
          rin.grant <= grant_i;
          rin.state <= ST_GRANT_OP;
        elsif chunk_valid_s = '1' and r.balance /= 0 then
          rin.state <= ST_DATA_OP;
          if chunk_len_m1_s > r.balance - 1 then
            rin.left_m1 <= to_unsigned(r.balance - 1, r.left_m1'length);
            rin.last <= '0';
          else
            rin.left_m1 <= chunk_len_m1_s;
            -- The whole chunk fits, but it is only an end-of-packet if the
            -- chunk actually ended on one (a partial chunk flushed on a TX
            -- bubble has chunk_last = '0').
            rin.last <= chunk_last_s;
          end if;
        end if;

      when ST_GRANT_OP =>
        if byte_ready_i = '1' then
          rin.state <= ST_GRANT_LSB;
        end if;

      when ST_GRANT_LSB =>
        if byte_ready_i = '1' then
          rin.state <= ST_GRANT_MSB;
        end if;

      when ST_GRANT_MSB =>
        if byte_ready_i = '1' then
          rin.state <= ST_IDLE;
          rin.grant_sent <= '1';
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
            rin.state <= ST_IDLE;
          else
            rin.left_m1 <= r.left_m1 - 1;
          end if;
        end if;
    end case;

    if batch_start_i = '1' then
      -- Each batch is self-framed, so a data frame left mid-body by a
      -- truncated previous batch must be re-headered for its remainder. A
      -- grant frame cut the same way is re-emitted whole: the value is
      -- absolute, so a duplicate costs nothing.
      case r.state is
        when ST_GRANT_OP | ST_GRANT_LSB | ST_GRANT_MSB =>
          rin.state <= ST_GRANT_OP;
        when others =>
          rin.state <= ST_IDLE;
      end case;
    end if;

    if credit_set_i = '1' then
      -- Absolute balance, derated by the data possibly emitted while the
      -- credit value was in flight (overrides the spend below).
      if credit_i > flight_margin_c then
        rin.balance <= to_integer(credit_i) - flight_margin_c;
      else
        rin.balance <= 0;
      end if;
    elsif byte_ready_i = '1' and r.state = ST_DATA and r.balance /= 0 then
      rin.balance <= r.balance - 1;
    end if;
  end process;

  grant_sent_o <= r.grant_sent;
  grant_ready_o <= '1' when r.state = ST_IDLE else '0';
  pending_o <= chunk_valid_s;
  sendable_o <= chunk_valid_s when r.balance /= 0 else '0';

  moore: process(r, chunk_byte_s) is
  begin
    case r.state is
      when ST_IDLE =>
        byte_o <= ctl_idle_c;

      when ST_GRANT_OP =>
        byte_o <= ctl_credit_c;

      when ST_GRANT_LSB =>
        byte_o <= std_ulogic_vector(r.grant(7 downto 0));

      when ST_GRANT_MSB =>
        byte_o <= std_ulogic_vector(r.grant(15 downto 8));

      when ST_DATA_OP =>
        byte_o(7) <= '0';
        byte_o(6) <= r.last;
        byte_o(5 downto 0) <= std_ulogic_vector(r.left_m1);

      when ST_DATA =>
        byte_o <= chunk_byte_s;
    end case;
  end process;

end architecture;
