library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc, nsl_data, nsl_memory;
use nsl_data.bytestream.all;
use nsl_bnoc.chunked_link.all;
use nsl_spi.chunked_link.all;

-- SPI slave transport for chunked_link.
--
-- The SCK domain holds only the byte shift register; every protocol block
-- (framer, deframer, payload FIFOs) runs in the clock_i domain. Per-byte
-- events cross domains as toggle handshakes: a received byte is latched with
-- a toggle on the SCK side and sampled after the toggle is observed on the
-- system side; a transmitted byte is presented quasi-statically by the framer
-- and advanced only after the SCK side signalled its consumption, so it is
-- stable long before the next byte boundary samples it. This bounds SCK to
-- clock_i / 4.
--
-- CS deassertion, resynchronised, restarts the framer (chunked_link batch
-- start): the budget is dropped and emission restarts on a frame boundary, so
-- byte 0 of the next window is a valid header on MISO. CS must therefore stay
-- deasserted a few clock_i cycles between windows.
entity spi_chunked_link_slave is
  generic(
    rx_fifo_depth_c : positive := 256;
    tx_fifo_depth_c : positive := 256
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;

    spi_i : in  nsl_spi.spi.spi_slave_i;
    spi_o : out nsl_spi.spi.spi_slave_o;

    -- System -> master (MISO direction).
    tx_i : in  nsl_bnoc.framed.framed_req_t;
    tx_o : out nsl_bnoc.framed.framed_ack_t;

    -- Master -> system (MOSI direction).
    rx_o : out nsl_bnoc.framed.framed_req_t;
    rx_i : in  nsl_bnoc.framed.framed_ack_t
    );
end entity;

architecture beh of spi_chunked_link_slave is

  -- Bytes in flight in the receive path (SCK-side latch, resynchronisation,
  -- deframer) not yet reflected in the RX FIFO free count; the advertised
  -- credit is derated by this so the master cannot over-send.
  constant rx_credit_margin_c : integer := 4;

  -- SCK domain.
  signal sck_rx_data_s : std_ulogic_vector(7 downto 0);
  signal sck_rx_strobe_s, sck_tx_strobe_s : std_ulogic;
  signal sck_rx_byte : std_ulogic_vector(7 downto 0);
  signal sck_rx_toggle, sck_tx_toggle : std_ulogic;

  -- System domain.
  type regs_t is
  record
    rx_toggle_sync : std_ulogic_vector(0 to 2);
    tx_toggle_sync : std_ulogic_vector(0 to 2);
    cs_n_sync : std_ulogic_vector(0 to 2);
    rx_valid : std_ulogic;
    rx_byte : byte;
    tx_next : std_ulogic;
    tx_hold : byte;
    tx_hold_valid : std_ulogic;
    batch_start : std_ulogic;
  end record;

  signal r, rin : regs_t;

  signal framer_byte_s : byte;
  signal framer_byte_ready_s : std_ulogic;
  signal rx_data_s : byte;
  signal rx_last_s, rx_valid_s : std_ulogic;
  signal budget_s : unsigned(credit_bits_c-1 downto 0);
  signal budget_set_s : std_ulogic;

  signal rx_free : integer range 0 to rx_fifo_depth_c;
  signal rx_free_uns : unsigned(credit_bits_c-1 downto 0);
  signal tx_level : integer range 0 to tx_fifo_depth_c;
  signal tx_level_uns : unsigned(credit_bits_c-1 downto 0);

  signal fifo_tx_data : byte;
  signal fifo_tx_last, fifo_tx_valid, fifo_tx_ready : std_ulogic;

begin

  shreg: nsl_spi.shift_register.spi_shift_register
    generic map(
      width_c => 8,
      msb_first_c => true
      )
    port map(
      spi_i => spi_i,
      spi_o => spi_o,
      tx_data_i => r.tx_hold,
      tx_strobe_o => sck_tx_strobe_s,
      rx_data_o => sck_rx_data_s,
      rx_strobe_o => sck_rx_strobe_s
      );

  -- SCK-side byte event latches, crossed as toggles.
  sck_events: process(spi_i.sck, reset_n_i)
  begin
    if rising_edge(spi_i.sck) then
      if sck_rx_strobe_s = '1' then
        sck_rx_byte <= sck_rx_data_s;
        sck_rx_toggle <= not sck_rx_toggle;
      end if;
      if sck_tx_strobe_s = '1' then
        sck_tx_toggle <= not sck_tx_toggle;
      end if;
    end if;

    if reset_n_i = '0' then
      sck_rx_toggle <= '0';
      sck_tx_toggle <= '0';
    end if;
  end process;

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.rx_toggle_sync <= (others => '0');
      r.tx_toggle_sync <= (others => '0');
      r.cs_n_sync <= (others => '1');
      r.rx_valid <= '0';
      r.tx_next <= '0';
      r.tx_hold_valid <= '0';
      r.batch_start <= '0';
    end if;
  end process;

  transition: process(r, sck_rx_toggle, sck_tx_toggle, sck_rx_byte,
                      framer_byte_s, spi_i.cs_n)
  begin
    rin <= r;

    rin.rx_toggle_sync <= sck_rx_toggle & r.rx_toggle_sync(0 to 1);
    rin.tx_toggle_sync <= sck_tx_toggle & r.tx_toggle_sync(0 to 1);
    rin.cs_n_sync <= spi_i.cs_n & r.cs_n_sync(0 to 1);

    -- One pulse per crossed event. The byte latch is stable once its
    -- toggle has traversed the synchroniser.
    rin.rx_valid <= r.rx_toggle_sync(1) xor r.rx_toggle_sync(2);
    rin.rx_byte <= sck_rx_byte;
    rin.tx_next <= r.tx_toggle_sync(1) xor r.tx_toggle_sync(2);

    -- CS deassertion ends the batch: restart the framer so the next
    -- window opens on a frame boundary with a zeroed budget.
    rin.batch_start <= r.cs_n_sync(1) and not r.cs_n_sync(2);

    -- One-byte prefetch presented to the SCK domain. The framer's byte_o
    -- may legitimately change at any time until it is consumed, but the
    -- SCK side samples asynchronously, so the byte crossing over must be
    -- a frozen snapshot: it is (re)latched only right after the SCK side
    -- signalled a consumption, several bit times before its next
    -- sampling. A batch restart invalidates the snapshot (it was taken
    -- against the previous batch); the budget margins cover this byte,
    -- so it can only be filler, never payload.
    if r.batch_start = '1' then
      rin.tx_hold_valid <= '0';
    elsif r.tx_hold_valid = '0' or r.tx_next = '1' then
      rin.tx_hold <= framer_byte_s;
      rin.tx_hold_valid <= '1';
    end if;
  end process;

  framer_byte_ready_s <= '1' when r.batch_start = '0'
                         and (r.tx_hold_valid = '0' or r.tx_next = '1')
                         else '0';

  framer: nsl_bnoc.chunked_link.chunked_link_slave_framer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      batch_start_i => r.batch_start,
      byte_ready_i => framer_byte_ready_s,
      byte_o => framer_byte_s,
      budget_set_i => budget_set_s,
      budget_i => budget_s,
      tx_data_i => fifo_tx_data,
      tx_last_i => fifo_tx_last,
      tx_valid_i => fifo_tx_valid,
      tx_ready_o => fifo_tx_ready,
      rx_free_i => rx_free_uns,
      tx_level_i => tx_level_uns
      );

  deframer: nsl_bnoc.chunked_link.chunked_link_deframer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      byte_i => r.rx_byte,
      byte_valid_i => r.rx_valid,
      rx_data_o => rx_data_s,
      rx_last_o => rx_last_s,
      rx_valid_o => rx_valid_s,
      credit_o => budget_s,
      credit_set_o => budget_set_s,
      level_o => open,
      level_set_o => open,
      pad_o => open,
      pad_set_o => open
      );

  rx_free_uns <= to_unsigned(rx_free - rx_credit_margin_c, credit_bits_c)
                 when rx_free > rx_credit_margin_c
                 else (others => '0');
  tx_level_uns <= to_unsigned(tx_level, credit_bits_c);

  rx_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => rx_fifo_depth_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_data_i(8) => rx_last_s,
      in_data_i(7 downto 0) => rx_data_s,
      in_valid_i => rx_valid_s,
      in_ready_o => open,
      in_free_o => rx_free,

      out_data_o(8) => rx_o.last,
      out_data_o(7 downto 0) => rx_o.data,
      out_valid_o => rx_o.valid,
      out_ready_i => rx_i.ready
      );

  tx_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => tx_fifo_depth_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_data_i(8) => tx_i.last,
      in_data_i(7 downto 0) => tx_i.data,
      in_valid_i => tx_i.valid,
      in_ready_o => tx_o.ready,

      out_data_o(8) => fifo_tx_last,
      out_data_o(7 downto 0) => fifo_tx_data,
      out_valid_o => fifo_tx_valid,
      out_ready_i => fifo_tx_ready,
      out_available_min_o => tx_level
      );

end architecture;
