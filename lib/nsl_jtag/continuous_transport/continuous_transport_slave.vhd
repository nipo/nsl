library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_hwdep, nsl_memory, nsl_clocking, nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;
use nsl_jtag.continuous_transport.all;

-- TAP-side slave for continuous_transport.
--
-- Terminates the protocol against a custom JTAG data register (selected by
-- reg_id_c) and exposes an nsl_bnoc.framed byte interface in each direction on
-- the system clock. The TCK-domain core is bridged to the system clock by two
-- dual-clock FIFOs; the RX FIFO free count feeds the core's outgoing credit.
-- TLR is a hard reset of the whole block and is offered, resynchronised to the
-- system clock, on reset_n_o for resetting user logic.
entity continuous_transport_slave is
  generic(
    reg_id_c         : natural range 1 to 4;
    -- The RX FIFO must absorb a full batch to support blind, long-latency
    -- adapter batches without a mid-stream stall (spec section 6.1).
    rx_fifo_depth_c  : positive;
    tx_fifo_depth_c  : positive;
    preamble_count_c : positive := preamble_min_c
    );
  port(
    clock_i   : in  std_ulogic;
    reset_n_i : in  std_ulogic;
    reset_n_o : out std_ulogic;

    -- System -> ATE (TDO direction).
    tx_i : in  nsl_bnoc.framed.framed_req_t;
    tx_o : out nsl_bnoc.framed.framed_ack_t;

    -- ATE -> System (TDI direction).
    rx_o : out nsl_bnoc.framed.framed_req_t;
    rx_i : in  nsl_bnoc.framed.framed_ack_t
    );
end entity;

architecture beh of continuous_transport_slave is

  signal tck       : std_ulogic;
  signal tlr       : std_ulogic;
  signal selected  : std_ulogic;
  signal capture   : std_ulogic;
  signal shift     : std_ulogic;
  signal update    : std_ulogic;
  signal jtag_tdi  : std_ulogic;       -- bit from the ATE (register tdi_o)
  signal jtag_tdo  : std_ulogic;       -- bit to the ATE (register tdo_i)

  signal cap, shf, upd : std_ulogic;   -- strobes gated by selection

  signal merged_reset_n : std_ulogic;
  signal reset_n_tck    : std_ulogic;

  -- TCK-domain core <-> FIFO interfaces.
  signal core_rx_data  : byte;
  signal core_rx_last  : std_ulogic;
  signal core_rx_valid : std_ulogic;
  signal rx_free       : integer range 0 to rx_fifo_depth_c;
  signal rx_free_uns   : unsigned(credit_bits_c-1 downto 0);

  -- Bytes in flight in the receive pipeline (deserializer + deframer + CDC)
  -- not yet reflected in the FIFO free count; advertised RX credit is derated
  -- by this so the ATE cannot over-send (spec section 6.1).
  constant rx_credit_margin_c : integer := (tap_rx_latency_c + 7) / 8 + 1;

  signal core_tx_data  : byte;
  signal core_tx_last  : std_ulogic;
  signal core_tx_valid : std_ulogic;
  signal core_tx_ready : std_ulogic;
  signal tx_level      : integer range 0 to tx_fifo_depth_c;
  signal tx_level_uns  : unsigned(credit_bits_c-1 downto 0);

begin

  tap: nsl_hwdep.jtag.jtag_tap_register
    generic map(
      id_c => reg_id_c
      )
    port map(
      tck_o => tck,
      tlr_o => tlr,
      selected_o => selected,
      capture_o => capture,
      shift_o => shift,
      update_o => update,
      run_o => open,
      tdi_o => jtag_tdi,
      tdo_i => jtag_tdo
      );

  cap <= capture and selected;
  shf <= shift and selected;
  upd <= update and selected;

  merged_reset_n <= (not tlr) and reset_n_i;

  reset_sync_tck: nsl_clocking.async.async_edge
    port map(
      clock_i => tck,
      data_i => merged_reset_n,
      data_o => reset_n_tck
      );

  reset_sync_sys: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_i,
      data_i => merged_reset_n,
      data_o => reset_n_o
      );

  rx_free_uns <= to_unsigned(rx_free - rx_credit_margin_c, credit_bits_c)
                 when rx_free > rx_credit_margin_c
                 else (others => '0');

  core: nsl_jtag.continuous_transport.continuous_transport_core
    generic map(
      preamble_count_c => preamble_count_c
      )
    port map(
      clock_i => tck,
      reset_n_i => reset_n_tck,
      shift_i => shf,
      capture_i => cap,
      update_i => upd,
      tdi_i => jtag_tdi,
      tdo_o => jtag_tdo,
      rx_data_o => core_rx_data,
      rx_last_o => core_rx_last,
      rx_valid_o => core_rx_valid,
      rx_free_i => rx_free_uns,
      tx_data_i => core_tx_data,
      tx_last_i => core_tx_last,
      tx_valid_i => core_tx_valid,
      tx_ready_o => core_tx_ready,
      tx_level_i => tx_level_uns
      );

  tx_level_uns <= to_unsigned(tx_level, credit_bits_c);

  -- RX: TCK-domain core writes, system side reads.
  rx_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => rx_fifo_depth_c,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_tck,
      clock_i(0) => tck,
      clock_i(1) => clock_i,

      in_data_i(8) => core_rx_last,
      in_data_i(7 downto 0) => core_rx_data,
      in_valid_i => core_rx_valid,
      in_ready_o => open,
      in_free_o => rx_free,

      out_data_o(8) => rx_o.last,
      out_data_o(7 downto 0) => rx_o.data,
      out_valid_o => rx_o.valid,
      out_ready_i => rx_i.ready,
      out_available_min_o => open,
      out_available_o => open
      );

  -- TX: system side writes, TCK-domain core reads.
  tx_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => tx_fifo_depth_c,
      clock_count_c => 2
      )
    port map(
      reset_n_i => reset_n_tck,
      clock_i(0) => clock_i,
      clock_i(1) => tck,

      in_data_i(8) => tx_i.last,
      in_data_i(7 downto 0) => tx_i.data,
      in_valid_i => tx_i.valid,
      in_ready_o => tx_o.ready,
      in_free_o => open,

      out_data_o(8) => core_tx_last,
      out_data_o(7 downto 0) => core_tx_data,
      out_valid_o => core_tx_valid,
      out_ready_i => core_tx_ready,
      out_available_min_o => tx_level,
      out_available_o => open
      );

end architecture;
