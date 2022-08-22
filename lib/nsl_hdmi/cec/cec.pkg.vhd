library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_io;
use nsl_data.bytestream.all;

package cec is

  -- From HDMI v1.4b

  -- Figure 3, p. CEC-9
  constant cec_start_period_c : time := 4500 us;
  constant cec_start_low_time_c : time := 3700 us;
  -- Exactly 0.5 ms before symbol nominal end
  constant cec_start_end_sample_offset_c : time := 4000 us;

  -- Figure 4, p. CEC-10
  constant cec_bit_period_c : time := 2400 us;
  constant cec_bit_1_time_c : time := 600 us;
  constant cec_bit_0_time_c : time := 1400 us;
  constant cec_bit_sample_offset_c : time := 1050 us;
  -- Exactly 0.5 ms before symbol nominal end, before T7 in all cases.
  constant cec_bit_end_sample_offset_c : time := 1900 us;

  -- Table 4, p. CEC-17
  -- Present Initiator wants to send another frame immediately after its previous frame
  constant cec_signal_free_bit_time_same_initiator_c : natural := 7;
  -- New Initiator wants to send a frame
  constant cec_signal_free_bit_time_new_initiator_c : natural := 4;
  -- Previous attempt to send frame unsuccessful
  constant cec_signal_free_bit_time_retry_c : natural := 3;
  
  type cec_symbol_t is (
    CEC_SYMBOL_0,
    CEC_SYMBOL_1,
    CEC_SYMBOL_START,
    CEC_SYMBOL_IDLE,
    CEC_SYMBOL_INVALID
    );
  
  component cec_deserializer is
    generic(
      clock_i_hz_c: natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      cec_i : in std_ulogic;

      idle_o: out std_ulogic;
      ack_window_o : out std_ulogic;
      valid_o: out std_ulogic;
      symbol_o: out cec_symbol_t
      );
  end component;
  
  component cec_serializer is
    generic(
      clock_i_hz_c: natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      cec_o : out nsl_io.io.opendrain;

      ready_o: out std_ulogic;
      valid_i: in std_ulogic;
      symbol_i: in cec_symbol_t
      );
  end component;
  
  component cec_transceiver is
    generic(
      clock_i_hz_c: natural
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      cec_i : in std_ulogic;
      cec_o : out nsl_io.io.opendrain;

      -- Addresses for which we acknowledge messages
      local_destination_i : in std_ulogic_vector(0 to 14) := (others => '0');

      -- For unicast message, whether we accept the data bytes, for broadcast
      -- messages, whether we do not reject data bytes.
      accept_i: in std_ulogic := '1';

      rx_ready_i : in std_ulogic := '1';
      rx_valid_o : out std_ulogic;
      rx_data_o : out byte;
      rx_last_o : out std_ulogic;

      tx_ready_o : out std_ulogic;
      tx_valid_i : in std_ulogic;
      tx_data_i : in byte;
      tx_last_i : in std_ulogic
      );
  end component;
  
end package cec;
