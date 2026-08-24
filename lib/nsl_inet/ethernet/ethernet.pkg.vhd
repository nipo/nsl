library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use work.mac.all;

-- Ethernet host adaptation (layer-2 addressing).  Stacked on
-- nsl_inet.mac (or on one branch of nsl_inet.vlan), it filters
-- frames on destination address, compresses addressing to a
-- peer/context header, and dispatches frames on ethertype.
package ethernet is

  -- Frames are carried through bnoc committed infrastructure.
  -- Frame components are the same for receive and transmit frames.

  -- Frame structure from/to layer below (nsl_inet.mac boundary):
  -- * Optional pre-header [N]
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * Status
  --   [0]   Whether frame is valid
  --   [7:1] Reserved
  -- Payload may be padded. Padding is carried over.

  -- Frame structure from/to layer 3:
  -- * Optional pre-header [N]
  -- * Peer hardware address [6], in network order
  -- * Frame source/destination context
  --   [0] Address type (0: Unicast, 1: Broadcast)
  --   [7:1] Reserved
  -- * Layer-3 Data
  -- * Optional padding (should be null on TX)
  -- * Status byte (word with 'last' asserted)
  --   [0]   Whether frame is valid. Invalid frames should be ignored.
  --   [7:1] Reserved
  -- Ethertype does not appear here: it is implied by the pipe the
  -- frame is transferred on.

  -- Header length before L3 data
  constant ethernet_layer_header_length_c : integer := 7;

  -- This component can detect its own local address or broadcast
  -- address. Multicast is not supported.
  component ethernet_receiver is
    generic(
      -- Index of entry in this table will be outputted belongside the
      -- frame on frame_o port.  Only defined entries are handled.
      -- All non-handled ethertypes coming on l2_i are dropped.
      ethertype_c : ethertype_vector;
      -- Flit count to pass through at the start of a frame
      header_length_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      l2_i : in nsl_bnoc.committed.committed_req;
      l2_o : out nsl_bnoc.committed.committed_ack;

      -- Valid at least on first word of frame on l3_o.
      l3_type_index_o : out integer range 0 to ethertype_c'length - 1;
      l3_o : out nsl_bnoc.committed.committed_req;
      l3_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  component ethernet_transmitter is
    generic(
      -- Flit count to pass through at the start of a frame
      header_length_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      -- Frame type is snapshotted on first word of l3_i.
      l3_type_i : in ethertype_t;
      l3_i : in nsl_bnoc.committed.committed_req;
      l3_o : out nsl_bnoc.committed.committed_ack;

      l2_o : out nsl_bnoc.committed.committed_req;
      l2_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  -- This component is an union of the two above with muxing of
  -- ethertype source/destinations. There is one bidir frame pipe per
  -- ethertype.
  component ethernet_layer is
    generic(
      ethertype_c : ethertype_vector;
      -- Flit count to pass through at the start of a frame
      header_length_c : integer := 0;
      mtu_c : natural := 1500;
      filter_inbound_packets_c : boolean := true
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      to_l3_o : out nsl_bnoc.committed.committed_req_array(0 to ethertype_c'length-1);
      to_l3_i : in nsl_bnoc.committed.committed_ack_array(0 to ethertype_c'length-1);
      from_l3_i : in nsl_bnoc.committed.committed_req_array(0 to ethertype_c'length-1);
      from_l3_o : out nsl_bnoc.committed.committed_ack_array(0 to ethertype_c'length-1);

      to_l2_o : out nsl_bnoc.committed.committed_req;
      to_l2_i : in nsl_bnoc.committed.committed_ack;
      from_l2_i : in nsl_bnoc.committed.committed_req;
      from_l2_o : out nsl_bnoc.committed.committed_ack
      );
  --@-- grouped name:l2, members:to_l2;from_l2
  --@-- grouped name:l3, members:to_l3;from_l3
  end component;

  function l3_pack(src : mac48_t;
                   is_bcast : boolean;
                   payload : byte_string) return byte_string;

end package;

package body ethernet is

  function l3_pack(src : mac48_t;
                   is_bcast : boolean;
                   payload : byte_string) return byte_string
  is
    variable bcast: byte := x"00";
  begin
    if is_bcast then
      bcast := x"01";
    end if;

    return src & bcast & payload;
  end function;

end package body;
