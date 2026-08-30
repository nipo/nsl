library ieee;
use ieee.std_logic_1164.all;

library nsl_amba, nsl_math;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;

-- Ethernet MAC framing for the AXI4-Stream protocol suite: frame
-- check sequence and minimum frame size.  This layer is transparent
-- to addresses and ethertype; interpretation, filtering and dispatch
-- belong to the ethernet layer stacked above.
--
-- Streams on both sides follow the block conventions of
-- nsl_inet.stream:
-- * the blocks whose contents lengths are header_length_c, forwarded
--   without interpretation,
-- * the ethernet frame block: front pad, ethernet header, payload,
--   and, on the layer-1 side only, the FCS.
--
-- The forwarded blocks and the front pad take part in neither the FCS
-- nor the frame size accounting; everything from the first ethernet
-- header byte onward does.
--
-- On receive, the payload padding ethernet mandates is carried over
-- as-is, the upper layer being the one knowing the actual payload
-- length.  On transmit, padding is appended so that the frame reaches
-- the minimum size and ends on a beat boundary, which may make it up
-- to one byte short of a beat longer than the minimum size alone
-- would.  The padding is covered by the FCS and trimmed by receivers
-- from the length field of the protocol above, just like the padding
-- the minimum frame size mandates.
--
-- Both components take the stream configuration from
-- nsl_inet.stream.stream_config() and use the user bit as the reject
-- flag defined there.
package stream_mac is

  constant ethernet_header_length_c : natural := 14;

  -- Front padding of the ethernet frame block, i.e. the offset of
  -- the first ethernet header byte within its first beat.  It makes
  -- the frame block end, and therefore the payload, land on a beat
  -- boundary.
  function ethernet_frame_offset(stream_config: config_t) return integer;

  -- Checks and strips the FCS.  Frames whose FCS does not verify, and
  -- frames shorter than the minimum ethernet frame size, are
  -- forwarded with the reject flag set on their last beat.  An
  -- already rejected frame stays rejected.
  --
  -- Frames whose total transported length does not exceed the FCS
  -- length carry no byte at all once trimmed: they are dropped
  -- silently.
  component stream_mac_receiver is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- Pads frames to the minimum ethernet frame size and to a whole
  -- count of beats, then appends the FCS.  Outgoing frames therefore
  -- carry up to width-1 padding bytes more than the minimum size
  -- alone would ask for, and every outgoing beat is full.  A frame
  -- arriving with the reject flag set gets a corrupted FCS, which is
  -- how a late cancellation reaches the peer; the outgoing frame
  -- itself is not flagged.
  component stream_mac_transmitter is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

end package;

package body stream_mac is

  function ethernet_frame_offset(stream_config: config_t) return integer
  is
    constant w: integer := stream_config.data_width;
  begin
    return (w - (ethernet_header_length_c mod w)) mod w;
  end function;

end package body;
