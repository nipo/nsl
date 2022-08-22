library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_clocking, nsl_logic, nsl_data;
use nsl_math.timing.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use work.cec.all;

entity cec_transceiver is
  generic(
    clock_i_hz_c: natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    cec_i : in std_ulogic;
    cec_o : out nsl_io.io.opendrain;

    -- Addresses for which we receive messages
    -- Messages to ignored destinations will be dropped silently.
    -- Broadcast is treated the other way around and is always accepted.
    accepted_destinations_i : in std_ulogic_vector(0 to 14) := (others => '0');

    rx_ready_i : in std_ulogic := '1';
    rx_valid_o : out std_ulogic;
    rx_data_o : out byte;
    rx_last_o : out std_ulogic;

    tx_ready_o : out std_ulogic;
    tx_valid_i : in std_ulogic;
    tx_data_i : in byte;
    tx_last_i : in std_ulogic
    );
end entity;

architecture beh of cec_transceiver is

  type state_t is (
    ST_RESET,

    ST_BUSY,
    ST_BACKOFF,
    ST_IDLE,

    ST_RX_HDR_DATA,
    ST_RX_HDR_EOM,
    ST_RX_HDR_ACK,
    ST_RX_HDR_PUT,

    ST_RX_MSG_DATA,
    ST_RX_MSG_EOM,
    ST_RX_MSG_ACK,
    ST_RX_MSG_PUT,

    ST_TX_MSG_GET,
    ST_TX_START,
    ST_TX_MSG_DATA,
    ST_TX_MSG_EOM,
    ST_TX_MSG_ACK,
    );

  type regs_t is
  record
    to_idle: natural range 0 to 7;
    is_bcast: boolean;
    bit_ctr: natural range 0 to 7;
    data: byte;
  end record;

  signal r, rin: regs_t;

  signal ack_s : nsl_io.io.opendrain;

  signal rx_idle_s, rx_ack_window_s, rx_valid_o: std_ulogic;
  signal rx_symbol_s: cec_symbol_t
  signal tx_ready_s, tx_valid_i: std_ulogic;
  signal tx_symbol_s: cec_symbol_t
  signal tx_cec_s : nsl_io.io.opendrain;
  
begin
  
  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r,
                      rx_idle_s, rx_ack_window_s, rx_valid_s, rx_symbol_s, rx_ready_i,
                      tx_ready_s, tx_symbol_s, tx_valid_i, tx_data_i, tx_last_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_BUSY;

      when ST_BUSY =>
        if rx_valid_s = '1' and rx_symbol_s = CEC_SYMBOL_IDLE then
          rin.state <= ST_BACKOFF;
        end if;

      when ST_BACKOFF =>
        if rx_valid_s = '1' then
          if rx_symbol_s = CEC_SYMBOL_IDLE then
            if r.to_idle = 0 then
              rin.state <= ST_IDLE;
            else
              rin.to_idle <= r.to_idle - 1;
            end if;
          else
            rin.state <= ST_BUSY;
            rin.to_idle <= cec_signal_free_bit_time_new_initiator_c;
          end if;
        end if;

      when ST_IDLE =>
        if rx_valid_s = '1' then
          if rx_symbol_s /= CEC_SYMBOL_IDLE then
            rin.state <= ST_BUSY;
            rin.to_idle <= cec_signal_free_bit_time_new_initiator_c;
          end if;
        end if;
        
  end process;

  serializer: work.cec.cec_serializer
    generic map(
      clock_i_hz_c => clock_i_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cec_o => tx_cec_s,

      ready_o => tx_ready_s,
      valid_i => tx_valid_s,
      symbol_i => tx_symbol_s
      );

  deserializer: work.cec.cec_deserializer
    generic map(
      clock_i_hz_c => clock_i_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cec_i => cec_i,

      idle_o => rx_idle_s,
      ack_window_o => rx_ack_window_s,
      valid_o => rx_valid_s,
      symbol_o => rx_symbol_s
      );

  cec_o <= tx_cec_s + ack_s;
  
end architecture;

