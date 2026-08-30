library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, work;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_math.int_ext.all;
use work.mac.all;

-- Ethernet host adaptation (layer-2 addressing) over the AXI4-Stream
-- transport conventions of nsl_inet.stream.  Stacked on the mac
-- layer, it filters frames on destination address, compresses
-- addressing to a context block, and dispatches frames on ethertype,
-- one stream pair per handled ethertype.
--
-- header_length_c lists the contents lengths of the blocks of the
-- layers below, forwarded verbatim in both directions.  Below,
-- P stands for nsl_inet.stream.context_byte_count(config_c,
-- header_length_c), F for nsl_inet.stream_mac.ethernet_frame_offset
-- (config_c) and C for nsl_inet.stream.context_byte_count(config_c,
-- (0 => l2_context_length_c)).
--
-- Frames on the mac side
-- ======================
--
-- * Forwarded blocks [P]
-- * Ethernet frame block [F+14]:
--   * Front padding [F]
--   * Destination mac address [6]
--   * Source mac address [6]
--   * Ethertype [2], big endian
-- * Layer-3 PDU [*], possibly followed by mac padding
--
-- No FCS appears here, the mac layer strips it on receive and appends
-- it on transmit.  The reject flag carried on the last beat (the FCS
-- verdict, for instance) is forwarded unchanged to the layer above.
--
-- Frames on the layer-3 side
-- ==========================
--
-- * Forwarded blocks [P], the same bytes as on the mac side, padding
--   included
-- * Context block [C]: to_bytes(l2_context_t), tail padded
-- * Layer-3 PDU [*], possibly followed by mac padding
--
-- Mac padding is not stripped: a frame shorter than the minimum
-- ethernet frame size reaches the layer above with the padding still
-- in place.  Upper layers know their own length fields and ignore
-- whatever follows their PDU.
--
-- The ethertype is not part of the context: each layer-3 stream pair
-- carries exactly the ethertype of its ethertype_c entry, in both
-- directions.
package stream_ethernet is

  -- Context block produced and consumed by this layer.  Ethertype
  -- does not appear here: streams above the ethernet layer exist
  -- after ethertype dispatch, one per handled type.  Casting reports
  -- how the frame was addressed on receive and is ignored on
  -- transmit, where the frame is always sent to peer.
  type l2_casting_t is (
    L2_CAST_UNICAST,
    L2_CAST_BROADCAST
    );

  type l2_context_t is
  record
    peer: mac48_t;
    casting: l2_casting_t;
  end record;

  constant l2_context_length_c: natural := 7;

  function to_bytes(ctx: l2_context_t) return byte_string;
  function from_bytes(data: byte_string) return l2_context_t;

  -- Address filtering keeps frames whose destination address is
  -- local_address_i, reported as L2_CAST_UNICAST, or the broadcast
  -- address, reported as L2_CAST_BROADCAST.  Multicast group
  -- addresses are dropped.
  --
  -- The ethertype of an accepted frame is looked up in ethertype_c;
  -- the frame is forwarded on the output port of matching index, or
  -- dropped if the ethertype is not in the table.  The context block
  -- carries the frame source address as peer.
  component stream_ethernet_receiver is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      ethertype_c : ethertype_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_vector(0 to ethertype_c'length-1);
      out_i : in slave_vector(0 to ethertype_c'length-1)
      );
  end component;

  -- Frames from any input port are funneled to the mac side with a
  -- crafted ethernet header: destination address is the context peer,
  -- source address is local_address_i, ethertype is the ethertype_c
  -- entry of the input port the frame came from.  The context casting
  -- field is ignored, a frame always goes to peer.
  component stream_ethernet_transmitter is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      ethertype_c : ethertype_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      in_i : in master_vector(0 to ethertype_c'length-1);
      in_o : out slave_vector(0 to ethertype_c'length-1);

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  -- Union of the two components above, with one bidirectional stream
  -- pair per ethertype.
  component stream_ethernet_layer is
    generic(
      config_c : config_t;
      header_length_c : integer_vector := null_integer_vector;
      ethertype_c : ethertype_vector
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      to_l3_o : out master_vector(0 to ethertype_c'length-1);
      to_l3_i : in slave_vector(0 to ethertype_c'length-1);
      from_l3_i : in master_vector(0 to ethertype_c'length-1);
      from_l3_o : out slave_vector(0 to ethertype_c'length-1);

      to_l1_o : out master_t;
      to_l1_i : in slave_t;
      from_l1_i : in master_t;
      from_l1_o : out slave_t
      );
  end component;

end package;

package body stream_ethernet is

  function to_bytes(ctx: l2_context_t) return byte_string
  is
  begin
    case ctx.casting is
      when L2_CAST_UNICAST =>
        return ctx.peer & to_byte(0);
      when L2_CAST_BROADCAST =>
        return ctx.peer & to_byte(1);
    end case;
  end function;

  function from_bytes(data: byte_string) return l2_context_t
  is
    alias xd: byte_string(0 to l2_context_length_c-1) is data;
    variable ret: l2_context_t;
  begin
    assert data'length = l2_context_length_c
      report "Bad context block length"
      severity failure;

    ret.peer := xd(0 to 5);
    -- Unknown casting values read as unicast: the field is ignored
    -- on transmit and the receive side only emits values above.
    if xd(6) = to_byte(1) then
      ret.casting := L2_CAST_BROADCAST;
    else
      ret.casting := L2_CAST_UNICAST;
    end if;
    return ret;
  end function;

end package body;
