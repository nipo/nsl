library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.committed.all;
use nsl_data.crc.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

-- Ethernet MAC framing (layer-2 wire conditioning).  Handles FCS and
-- minimal frame size.  This layer is transparent: addresses and
-- ethertype are forwarded untouched, in-band.  Address
-- interpretation, filtering and ethertype dispatch are the job of
-- nsl_inet.ethernet, stacked above.
package mac is

  -- Ethernet mac address is transmitted LSB-first, but we usually
  -- represent it as hex in a group of 6 bytes, with transmit first
  -- (least significant byte) on the left. If we'd like to accept
  -- literal unsigned as x"aabbccddeeff" for address
  -- "aa:bb:cc:dd:ee:ff", that would make a very strange shift order.
  -- For simplicity in declaration, we'll only define it as a group of
  -- bytes.

  -- For mac48 literal, use nsl_data.bytestream.from_hex
  --@-- convert python:str, serialize:'value', convert:nsl_inet.mac.to_mac48({})
  subtype mac48_t is byte_string(0 to 5);
  type mac48_vector is array(integer range <>) of mac48_t;
  constant ethernet_broadcast_addr_c : mac48_t := from_hex("ffffffffffff");

  function is_broadcast(mac: mac48_t) return boolean;
  function mac_to_string(mac: mac48_t) return string;
  function to_mac48(s: string) return mac48_t;

  subtype ethertype_t is integer range 0 to 65535;
  type ethertype_vector is array(integer range <>) of ethertype_t;

  constant ethertype_ipv4 : ethertype_t := 16#0800#;
  constant ethertype_arp  : ethertype_t := 16#0806#;
  constant ethertype_vlan : ethertype_t := 16#8100#;
  constant ethertype_ipv6 : ethertype_t := 16#86dd#;
  constant ethertype_ptp  : ethertype_t := 16#88f7#;

  -- Frames are carried through bnoc committed infrastructure.

  -- Frame structure from/to layer 1:
  -- * Optional L1 pre-header [N]
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * FCS [4], if l1_has_fcs_c
  -- * Status
  --   [0]   Frame complete
  --   [7:1] Reserved

  -- Frame structure from/to upper layer:
  -- * Optional L1 pre-header [N]
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * Status byte (word with 'last' asserted)
  --   [0]   Whether frame is valid. On RX, this is cleared if there
  --         is a CRC error. Invalid frames should be ignored.
  --   [7:1] Reserved
  -- Payload may be padded. Padding is carried over on RX; on TX,
  -- frames are padded to the minimal frame size.

  -- Checks and strips FCS. Frames with a bad FCS are forwarded with
  -- validity bit cleared.
  component mac_receiver is
    generic(
      l1_has_fcs_c : boolean := true;
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      l1_i : in nsl_bnoc.committed.committed_req;
      l1_o : out nsl_bnoc.committed.committed_ack;

      l2_o : out nsl_bnoc.committed.committed_req;
      l2_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  -- Pads committed frames to minimal frame size and appends FCS.
  -- Cancelled frames are forwarded without padding.
  component mac_transmitter is
    generic(
      l1_has_fcs_c : boolean := true;
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0;
      -- Total frame size on wire, FCS included
      min_frame_size_c : natural := 64 --bytes
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      l2_i : in nsl_bnoc.committed.committed_req;
      l2_o : out nsl_bnoc.committed.committed_ack;

      l1_o : out nsl_bnoc.committed.committed_req;
      l1_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

  -- A frame router based on destination address to select output port.
  component mac_router is
    generic(
      destination_count_c : natural;
      -- Flit count to pass through at the start of a frame
      l1_header_length_c : integer := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Address to lookup
      destination_address_o : out mac48_t;
      -- Request strobe, response MUST appear on destination_port_i on next cycle.
      destination_lookup_o : out std_ulogic;
      destination_port_i : in natural range 0 to destination_count_c - 1;

      in_i : in nsl_bnoc.committed.committed_req;
      in_o : out nsl_bnoc.committed.committed_ack;

      out_o : out nsl_bnoc.committed.committed_req_array(0 to destination_count_c-1);
      out_i : in nsl_bnoc.committed.committed_ack_array(0 to destination_count_c-1)
      );
  end component;

  function frame_pack(dest, src : mac48_t;
                      ethertype : ethertype_t;
                      payload : byte_string;
                      min_frame_size_c : natural := 0) return byte_string;

  function frame_is_fcs_valid(frame : byte_string) return boolean;
  function frame_daddr_get(frame : byte_string) return mac48_t;
  function frame_saddr_get(frame : byte_string) return mac48_t;
  function frame_ethertype_get(frame : byte_string) return ethertype_t;
  function frame_payload_get(frame : byte_string) return byte_string;

  -- CRC parameters
  constant fcs_params_c : crc_params_t := crc_params(
    init             => "",
    poly             => x"104c11db7",
    complement_input => false,
    complement_state => true,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_INCREASING
    );

end package;

package body mac is

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
    variable fcs : crc_state_t := crc_init(fcs_params_c);
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

  function frame_is_fcs_valid(frame : byte_string) return boolean
  is
    alias xframe : byte_string(0 to frame'length-1) is frame;
    variable fcs : crc_state_t;
  begin
    if xframe'length < 6 + 6 + 2 + 4 then
      return false;
    end if;

    fcs := crc_update(fcs_params_c, crc_init(fcs_params_c), xframe(0 to xframe'right-4));
    return crc_spill(fcs_params_c, fcs) = xframe(xframe'right-3 to xframe'right);
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

  function to_mac48(s: string) return mac48_t
  is
    alias xs: string(1 to 17) is s;
    variable r: mac48_t;
  begin
    for i in r'range
    loop
      r(i) := byte_from_hex(xs(1+i*3 to 2+i*3));
    end loop;
    return r;
  end function;

end package body;
