library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_data;
use nsl_data.bytestream.all;
use nsl_jtag.continuous_transport.all;

-- TCK-domain protocol core for continuous_transport.
--
-- Ties the four bit/byte/frame blocks together against a raw shift interface
-- (already gated by the register selection upstream) and exposes the two
-- FIFO-side byte interfaces. The TDO alignment pad is double-buffered here: a
-- set-pad frame updates the shadow, and the shadow transfers to the active pad
-- on Update-DR so it takes effect from the next batch's preamble.
--
-- reset_n_i is the TCK-domain reset and is expected to already fold in TLR.
entity continuous_transport_core is
  generic(
    preamble_count_c : positive := preamble_min_c
    );
  port(
    clock_i   : in  std_ulogic;         -- TCK
    reset_n_i : in  std_ulogic;

    shift_i   : in  std_ulogic;
    capture_i : in  std_ulogic;
    update_i  : in  std_ulogic;
    tdi_i     : in  std_ulogic;
    tdo_o     : out std_ulogic;

    -- RX FIFO write side (received payload).
    rx_data_o  : out byte;
    rx_last_o  : out std_ulogic;
    rx_valid_o : out std_ulogic;
    -- RX FIFO free space, advertised to the ATE as credit.
    rx_free_i  : in  unsigned(credit_bits_c-1 downto 0);

    -- TX FIFO read side (payload to send).
    tx_data_i  : in  byte;
    tx_last_i  : in  std_ulogic;
    tx_valid_i : in  std_ulogic;
    tx_ready_o : out std_ulogic;
    -- TX FIFO occupancy, advertised to the ATE as tx-level.
    tx_level_i : in  unsigned(credit_bits_c-1 downto 0)
    );
end entity;

architecture beh of continuous_transport_core is

  signal des_byte       : byte;
  signal des_byte_valid : std_ulogic;

  signal budget     : unsigned(credit_bits_c-1 downto 0);
  signal budget_set : std_ulogic;
  signal pad        : std_ulogic_vector(2 downto 0);
  signal pad_set    : std_ulogic;

  signal frame_byte : byte;
  signal byte_ready : std_ulogic;

  signal pad_shadow : std_ulogic_vector(2 downto 0);
  signal pad_active : integer range 0 to 7;

begin

  deserializer: nsl_jtag.continuous_transport.continuous_transport_deserializer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      shift_i => shift_i,
      capture_i => capture_i,
      tdi_i => tdi_i,
      locked_o => open,
      byte_o => des_byte,
      byte_valid_o => des_byte_valid
      );

  deframer: nsl_jtag.continuous_transport.continuous_transport_deframer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      byte_i => des_byte,
      byte_valid_i => des_byte_valid,
      rx_data_o => rx_data_o,
      rx_last_o => rx_last_o,
      rx_valid_o => rx_valid_o,
      budget_o => budget,
      budget_set_o => budget_set,
      pad_o => pad,
      pad_set_o => pad_set
      );

  framer: nsl_jtag.continuous_transport.continuous_transport_framer
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      capture_i => capture_i,
      byte_ready_i => byte_ready,
      byte_o => frame_byte,
      budget_set_i => budget_set,
      budget_i => budget,
      tx_data_i => tx_data_i,
      tx_last_i => tx_last_i,
      tx_valid_i => tx_valid_i,
      tx_ready_o => tx_ready_o,
      rx_free_i => rx_free_i,
      tx_level_i => tx_level_i
      );

  serializer: nsl_jtag.continuous_transport.continuous_transport_serializer
    generic map(
      preamble_count_c => preamble_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      shift_i => shift_i,
      capture_i => capture_i,
      update_i => update_i,
      pad_i => pad_active,
      tdo_o => tdo_o,
      byte_i => frame_byte,
      byte_ready_o => byte_ready
      );

  -- TDO alignment pad: shadow updated by set-pad frames, transferred to the
  -- active pad on Update-DR (batch close).
  pad_latch: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if pad_set = '1' then
        pad_shadow <= pad;
      end if;
      if update_i = '1' then
        pad_active <= to_integer(unsigned(pad_shadow));
      end if;
    end if;

    if reset_n_i = '0' then
      pad_shadow <= (others => '0');
      pad_active <= 0;
    end if;
  end process;

end architecture;
