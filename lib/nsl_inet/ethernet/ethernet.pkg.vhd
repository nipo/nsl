library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

-- Ethernet MAC layer (layer-2). Handles ethernet addressing.
package ethernet is

  -- Ethernet mac address is transmitted LSB-first, but we usually
  -- represent it as hex in a group of 6 bytes, with transmit first
  -- (least significant byte) on the left. If we'd like to accept
  -- literal unsigned as x"aabbccddeeff" for address
  -- "aa:bb:cc:dd:ee:ff", that would make a very strange shift order.
  -- For simplicity in declaration, we'll only define it as a group of
  -- bytes.

  -- For mac48 literal, use nsl_data.bytestream.from_hex
  subtype mac48_t is byte_string(0 to 5);
  constant ethernet_broadcast_addr_c : mac48_t := from_hex("ffffffffffff");

  function is_broadcast(mac: mac48_t) return boolean;
  
  subtype ethertype_t is integer range 0 to 65535;
  type ethertype_vector is array(integer range <>) of ethertype_t;

  constant ethertype_ipv4 : ethertype_t := 16#0800#;
  constant ethertype_arp  : ethertype_t := 16#0806#;
  constant ethertype_ipv6 : ethertype_t := 16#86dd#;
  constant ethertype_ptp  : ethertype_t := 16#88f7#;

  -- Frames are carried through bnoc framed infrastructure.
  -- Frame components are the same for receive and transmit frames.

  -- Frame structure form/to layer 1:
  -- * Optional L1 pre-header [N]
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * Status
  --   [0]   CRC valid / Frame complete
  --   [7:1] Reserved
  -- Payload may be padded. Padding is carried over.
  -- There is no minimal size for frame TX.

  -- Frame structure form/to layer 3:
  -- * Optional L1 pre-header [N]
  -- * Peer hardware address [6], in network order
  -- * Frame source/destination context
  --   [1:0] Address type (0: Unicast, 1: Broadcast, 2-3: Reserved)
  --   [7:2] Reserved
  -- * Layer-3 Data
  -- * Optional padding (should be null on TX)
  -- * Status byte (word with 'last' asserted)
  --   [0]   Whether frame is valid. On RX, this is cleared if there is a
  --         CRC error, for instance. Invalid frames should be ignored.
  --   [7:1] Reserved

  -- This component can detect its own local address or broadcast
  -- address. Multicast is not supported.
  component ethernet_receiver is
    generic(
      -- Index of entry in this table will be outputted belongside the
      -- frame on frame_o port.  Only defined entries are handled.
      -- All non-handled ethertypes coming on l1_i are dropped.
      ethertype_c : ethertype_vector;
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      l1_i : in nsl_bnoc.framed.framed_req;
      l1_o : out nsl_bnoc.framed.framed_ack;

      -- Valid at least on first word of frame on l3_o.
      l3_type_index_o : out integer range 0 to ethertype_c'length - 1;
      l3_o : out nsl_bnoc.framed.framed_req;
      l3_i : in nsl_bnoc.framed.framed_ack
      );
  end component;

  -- This component can detect its own local address or broadcast
  -- address. Multicast is not supported.
  component ethernet_transmitter is
    generic(
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      -- Frame type is snapshotted on first word of l3_i.
      l3_type_i : in ethertype_t;
      l3_i : in nsl_bnoc.framed.framed_req;
      l3_o : out nsl_bnoc.framed.framed_ack;

      l1_o : out nsl_bnoc.framed.framed_req;
      l1_i : in nsl_bnoc.framed.framed_ack
      );
  end component;

  -- This component is an union of the two above with muxing of
  -- ethertype source/destinations. There is one bidir frame pipe per
  -- ethertype.
  component ethernet_layer is
    generic(
      ethertype_c : ethertype_vector;
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      to_l3_o : out nsl_bnoc.framed.framed_req_array(0 to ethertype_c'length-1);
      to_l3_i : in nsl_bnoc.framed.framed_ack_array(0 to ethertype_c'length-1);
      from_l3_i : in nsl_bnoc.framed.framed_req_array(0 to ethertype_c'length-1);
      from_l3_o : out nsl_bnoc.framed.framed_ack_array(0 to ethertype_c'length-1);

      to_l1_o : out nsl_bnoc.framed.framed_req;
      to_l1_i : in nsl_bnoc.framed.framed_ack;
      from_l1_i : in nsl_bnoc.framed.framed_req;
      from_l1_o : out nsl_bnoc.framed.framed_ack
      );
  end component;

end package;

package body ethernet is

  function is_broadcast(mac: mac48_t) return boolean
  is
  begin
    return mac = ethernet_broadcast_addr_c;
  end function;

end package body;
