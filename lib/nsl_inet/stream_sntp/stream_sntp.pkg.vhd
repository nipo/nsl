library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use work.ipv4.all;

-- SNTP client over the AXI4-Stream protocol suite, RFC 4330.  The
-- client is an application-contract endpoint on a host UDP port: it
-- polls a unicast server and maintains a running wall-clock time.
-- No clock discipline is attempted: the server transmit timestamp
-- is latched as-is and the seconds field then advances on a local
-- one-second ticker until the next poll resynchronizes it.  The
-- fraction field is only meaningful at synchronization instants.
--
-- The client is byte-wide only; wider stacks place it behind a
-- stream_block_resizer pair, like the DHCP client.
package stream_sntp is

  constant sntp_port_c : natural := 123;
  constant sntp_message_length_c : natural := 48;

  -- Byte offsets inside the message.
  constant sntp_flags_offset_c : natural := 0;
  constant sntp_stratum_offset_c : natural := 1;
  constant sntp_reference_ts_offset_c : natural := 16;
  constant sntp_originate_ts_offset_c : natural := 24;
  constant sntp_receive_ts_offset_c : natural := 32;
  constant sntp_transmit_ts_offset_c : natural := 40;

  -- Client engine.  config_c must be one byte wide.
  --
  -- Packets on rx_i carry the header_length_c blocks, skipped
  -- without interpretation, then the SNTP message; rejected packets
  -- are discarded.  Packets on tx_o follow the application transmit
  -- contract: [IPv4 context][UDP context][48-byte message], peer
  -- sntp_port_c, unicast to server_i.
  --
  -- Polling runs while enable_i and server_valid_i are both
  -- asserted: every 8 seconds until a first valid reply, then every
  -- poll_period_c seconds.  A reply is taken when it comes from a
  -- mode-4 server with a stratum in 1 to 15 and echoes, in its
  -- originate timestamp, the random nonce the request carried as
  -- transmit timestamp; kiss-o'-death replies (stratum 0) are
  -- ignored.
  --
  -- time_o is the 64-bit NTP timestamp, seconds since era epoch in
  -- the upper half, fraction in the lower half.  valid_o is
  -- asserted once a first reply is taken and stays asserted, the
  -- clock free-running between polls, until enable_i or
  -- server_valid_i deasserts, which zeroes the outputs and idles
  -- the engine.  tick_o pulses one cycle per local second while
  -- valid_o is asserted, clock_i_hz_c clock cycles apart.
  component stream_sntp_client is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      clock_i_hz_c : natural;
      poll_period_c : natural := 64
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      server_i : in ipv4_t;
      server_valid_i : in std_ulogic := '1';

      rx_i : in master_t;
      rx_o : out slave_t;
      tx_o : out master_t;
      tx_i : in slave_t;

      time_o : out unsigned(63 downto 0);
      tick_o : out std_ulogic;
      valid_o : out std_ulogic
      );
  end component;

end package;
