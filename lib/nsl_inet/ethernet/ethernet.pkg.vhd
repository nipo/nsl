library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.committed.all;
use nsl_data.crc.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

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
  function mac_to_string(mac: mac48_t) return string;
  
  subtype ethertype_t is integer range 0 to 65535;
  type ethertype_vector is array(integer range <>) of ethertype_t;

  constant ethertype_ipv4 : ethertype_t := 16#0800#;
  constant ethertype_arp  : ethertype_t := 16#0806#;
  constant ethertype_ipv6 : ethertype_t := 16#86dd#;
  constant ethertype_ptp  : ethertype_t := 16#88f7#;

  -- Frames are carried through bnoc committed infrastructure.
  -- Frame components are the same for receive and transmit frames.

  -- Frame structure form/to layer 1:
  -- * Optional L1 pre-header [N]
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * FCS
  -- * Status
  --   [0]   Frame complete
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

  -- Header length before L3 data
  constant ethernet_layer_header_length_c : integer := 7;

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

      l1_i : in nsl_bnoc.committed.committed_req;
      l1_o : out nsl_bnoc.committed.committed_ack;

      -- Valid at least on first word of frame on l3_o.
      l3_type_index_o : out integer range 0 to ethertype_c'length - 1;
      l3_o : out nsl_bnoc.committed.committed_req;
      l3_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  -- This component can detect its own local address or broadcast
  -- address. Multicast is not supported.
  component ethernet_transmitter is
    generic(
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0;
      min_frame_size_c : natural := 64 --bytes
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      -- Frame type is snapshotted on first word of l3_i.
      l3_type_i : in ethertype_t;
      l3_i : in nsl_bnoc.committed.committed_req;
      l3_o : out nsl_bnoc.committed.committed_ack;

      l1_o : out nsl_bnoc.committed.committed_req;
      l1_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  -- This component is an union of the two above with muxing of
  -- ethertype source/destinations. There is one bidir frame pipe per
  -- ethertype.
  component ethernet_layer is
    generic(
      ethertype_c : ethertype_vector;
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0;
      min_frame_size_c : natural := 64 --bytes
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      local_address_i : in mac48_t;

      to_l3_o : out nsl_bnoc.committed.committed_req_array(0 to ethertype_c'length-1);
      to_l3_i : in nsl_bnoc.committed.committed_ack_array(0 to ethertype_c'length-1);
      from_l3_i : in nsl_bnoc.committed.committed_req_array(0 to ethertype_c'length-1);
      from_l3_o : out nsl_bnoc.committed.committed_ack_array(0 to ethertype_c'length-1);

      to_l1_o : out nsl_bnoc.committed.committed_req;
      to_l1_i : in nsl_bnoc.committed.committed_ack;
      from_l1_i : in nsl_bnoc.committed.committed_req;
      from_l1_o : out nsl_bnoc.committed.committed_ack
      );
  end component;

  function frame_pack(dest, src : mac48_t;
                      ethertype : ethertype_t;
                      payload : byte_string;
                      min_frame_size_c : natural := 0) return byte_string;

  function l3_pack(src : mac48_t;
                   is_bcast : boolean;
                   payload : byte_string) return byte_string;

  function frame_is_fcs_valid(frame : byte_string) return boolean;
  function frame_daddr_get(frame : byte_string) return mac48_t;
  function frame_saddr_get(frame : byte_string) return mac48_t;
  function frame_ethertype_get(frame : byte_string) return ethertype_t;
  function frame_payload_get(frame : byte_string) return byte_string;

  -- CRC parameters
  subtype fcs_t is nsl_data.crc.crc_state(31 downto 0);
  constant fcs_params_c : crc_params_t := (
    length           => 32,
    init             => 16#00000000#,
    poly             => -306674912, -- edb88320,
    complement_input => false,
    insert_msb       => true,
    pop_lsb          => true,
    complement_state => true,
    spill_bitswap    => false,
    spill_lsb_first  => true
    );
  
end package;

package body ethernet is

  function is_broadcast(mac: mac48_t) return boolean
  is
  begin
    return mac = ethernet_broadcast_addr_c;
  end function;

  function frame_pack(dest, src : mac48_t;
                      ethertype : ethertype_t;
                      payload : byte_string;
                      min_frame_size_c : natural := 0) return byte_string
  is
    variable hdr : byte_string(1 to 6+6+2);
    variable fcs : fcs_t := crc_init(fcs_params_c);
    variable pad : byte_string(payload'length to min_frame_size_c-6-6-2-4-1) := (others => x"00");
  begin
    hdr(1 to 6) := dest;
    hdr(7 to 12) := src;
    hdr(13 to 14) := to_be(to_unsigned(ethertype, 16));

    fcs := crc_update(fcs_params_c, fcs, hdr);
    fcs := crc_update(fcs_params_c, fcs, payload);
    fcs := crc_update(fcs_params_c, fcs, pad);

    return hdr & payload & pad & crc_spill(fcs_params_c, fcs);
  end function;

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

  function frame_is_fcs_valid(frame : byte_string) return boolean
  is
    alias xframe : byte_string(0 to frame'length-1) is frame;
    variable fcs : fcs_t;
  begin
    if xframe'length < 6 + 6 + 2 + 4 then
      return false;
    end if;

    fcs := crc_update(fcs_params_c, crc_init(fcs_params_c), xframe(0 to xframe'right-4));
    return to_le(unsigned(fcs)) = xframe(xframe'right-3 to xframe'right);
  end function;
  
  function frame_daddr_get(frame : byte_string) return mac48_t
  is
    alias xframe : byte_string(0 to frame'length-1) is frame;
    constant r: mac48_t := xframe(0 to 5);
  begin
    return r;
  end function;

  function frame_saddr_get(frame : byte_string) return mac48_t
  is
    alias xframe : byte_string(0 to frame'length-1) is frame;
    constant r: mac48_t := xframe(6 to 11);
  begin
    return r;
  end function;

  function frame_ethertype_get(frame : byte_string) return ethertype_t
  is
    alias xframe : byte_string(0 to frame'length-1) is frame;
    constant f: byte_string := xframe(12 to 13);
  begin
    return ethertype_t(to_integer(from_be(f)));
  end function;

  function frame_payload_get(frame : byte_string) return byte_string
  is
    alias xframe : byte_string(0 to frame'length-1) is frame;
    constant r: byte_string(0 to xframe'length-1-6-6-2-4) := xframe(14 to xframe'right-4);
  begin
    return r;
  end function;

  function mac_to_string(mac: mac48_t) return string
  is
  begin
    return to_hex_string(mac(0))
      & ":" & to_hex_string(mac(1))
      & ":" & to_hex_string(mac(2))
      & ":" & to_hex_string(mac(3))
      & ":" & to_hex_string(mac(4))
      & ":" & to_hex_string(mac(5));
  end function;

end package body;
