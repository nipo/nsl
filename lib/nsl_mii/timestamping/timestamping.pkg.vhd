library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

-- Frame timestamping sidebands for the layer-1 drivers.  Time never
-- enters the packet path: the drivers only export an SFD strobe and
-- a small cycling identifier, and consumers sample their own time
-- base on the strobe into a register file
-- (nsl_time.capture.timestamp_capture), indexed by the identifier.
-- The identifier travels with the frame as a one-byte layer-1
-- pre-header block, so any layer that sees the frame can find the
-- capture register that belongs to it.
--
-- The time base may live in its own clock domain: the sideband is
-- the only thing that crosses, through
-- timestamping_sideband_resync, and the capture register file then
-- sits in the time base domain.  Claims of a capture register from
-- the stream domain stay safe without a handshake because the
-- register is written a synchronizer latency after the strobe and
-- read a whole stream-path latency after it, and is not reused
-- before 2**id_bits_c further frames.
--
-- The tag byte encoding is private to the functions below: use the
-- constructors and accessors, not the values.
--
-- On receive, the tagger assigns identifiers in sequence.  A
-- consumer must claim its capture register when the tag byte enters
-- it, which bounds the association lifetime to the fixed latency
-- between the wire and that point: with the default two identifier
-- bits, four frames must start on the wire before a register is
-- reused, more than the layers in between can hold.
--
-- On transmit, the sender fills the tag block itself: an arbitrary
-- identifier and a flag requesting the strobe.  Frames without the
-- flag pass silently.
package timestamping is

  -- Contents length of the tag pre-header block.
  constant tag_length_c : natural := 1;

  -- Identifier, at most four bits wide; a component cycling over
  -- identifiers uses the id_bits_c low bits.
  subtype tag_id_t is unsigned(3 downto 0);

  function tag_build(strobe: boolean; id: tag_id_t) return byte;
  function tag_id(tag: byte) return tag_id_t;
  function tag_strobes(tag: byte) return boolean;

  -- Sits on the receive stream out of a layer-1 driver.  Each sfd_i
  -- pulse assigns the next identifier and reports it on the sfd_o /
  -- id_o sideband, for a capture register file to sample its time
  -- base; the same identifier is prepended to the matching frame as
  -- the tag pre-header block.
  --
  -- The driver must emit exactly one packet per sfd_i pulse, in
  -- order; packets it flags as errored still count.  This is
  -- asserted in simulation.
  component timestamping_rx_tagger is
    generic(
      config_c : config_t;
      id_bits_c : natural range 1 to 4 := 2
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      sfd_i : in std_ulogic;

      sfd_o : out std_ulogic;
      id_o : out tag_id_t;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- Carries (strobe, identifier) events into another clock domain,
  -- for a capture register file living next to the time base.  One
  -- event crosses at a time: a strobe arriving while the previous
  -- event is still in flight is an error, asserted in simulation --
  -- frames on the wire are spaced far beyond the synchronizer
  -- latency.  done_o pulses, in the a domain, once the b side has
  -- delivered the event, hence once the capture register is written:
  -- a consumer waiting for done_o may read the register without any
  -- further synchronization.
  component timestamping_sideband_resync is
    port(
      reset_n_i : in std_ulogic;

      a_clock_i : in std_ulogic;
      a_strobe_i : in std_ulogic;
      a_id_i : in tag_id_t;
      a_done_o : out std_ulogic;

      b_clock_i : in std_ulogic;
      b_strobe_o : out std_ulogic;
      b_id_o : out tag_id_t
      );
  end component;

  -- Sits on the transmit stream into a layer-1 driver.  The tag
  -- pre-header block is consumed and remembered, the rest of the
  -- frame forwarded; when the driver strobes the frame's SFD on
  -- sfd_i, a frame whose tag requested it pulses strobe_o with the
  -- sender's identifier on id_o.
  component timestamping_tx_strober is
    generic(
      config_c : config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      sfd_i : in std_ulogic;

      strobe_o : out std_ulogic;
      id_o : out tag_id_t;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

end package;

package body timestamping is

  -- Tag byte encoding, private: bit 7 is the transmit strobe
  -- request, the low nibble is the identifier.
  function tag_build(strobe: boolean; id: tag_id_t) return byte
  is
    variable ret: byte := (others => '0');
  begin
    if strobe then
      ret(7) := '1';
    end if;
    ret(3 downto 0) := std_ulogic_vector(id);
    return ret;
  end function;

  function tag_id(tag: byte) return tag_id_t
  is
  begin
    return unsigned(tag(3 downto 0));
  end function;

  function tag_strobes(tag: byte) return boolean
  is
  begin
    return tag(7) = '1';
  end function;

end package body;
