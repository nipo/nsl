library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

-- UDP is a layer-4 protocol. It is meant to be transported on IP.
package udp is

  subtype udp_port_t is integer range 0 to 65535;
  type udp_port_vector is array(integer range <>) of udp_port_t;
  constant udp_port_vector_null_c: udp_port_vector(0 to -1) := (others => 0);
  
  -- Frame structure from/to layer 3
  -- * Some fixed context, passed through [0..N] *
  -- * Layer 4 PDU size, big endian [2]
  -- * Layer 4 data [*]
  -- * Status
  --   [0]   Validity bit
  --   [7:1] Reserved
  
  -- Frame structure from/to layer 5
  -- * Upper layer context, passed through [0..N] *
  -- * Remote port, MSB first [2]
  -- * Local port, MSB first [2] (not in layer stream)
  -- * Layer 5 data [N]
  -- * Status
  --   [0]   Validity bit
  --   [7:1] Reserved

  -- [*] For instance, stacked on IPv4 implementation, passed through
  -- context will be:
  -- * L1 header
  -- * L2 header
  -- * Peer IP address
  -- * IP Context (address type)
  -- * IP proto
  
  component udp_receiver is
    generic(
      -- Upper-layer-specific data size
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Frame from layer 3
      l3_i : in committed_req;
      l3_o : out committed_ack;

      -- To layer 5
      l5_o : out committed_req;
      l5_i : in committed_ack
      );
  end component;

  component udp_transmitter is
    generic(
      mtu_c : integer := 1500;
      -- Flit count to pass through at the start of a packet
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- From layer 5
      l5_i : in committed_req;
      l5_o : out committed_ack;

      -- To layer 3
      l3_o : out committed_req;
      l3_i : in committed_ack
      );
  end component;

  component udp_layer is
    generic(
      tx_mtu_c : integer := 1500;
      udp_port_c : udp_port_vector;
      header_length_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Frame structure from/to layer 5
      -- * Upper layer context, passed through [header_length_c]
      -- * Remote port, MSB first [2]
      -- * Layer 5 data [N]
      -- * Status
      --   [0]   Validity bit
      --   [7:1] Reserved
      to_l5_o : out committed_req_array(0 to udp_port_c'length - 1);
      to_l5_i : in committed_ack_array(0 to udp_port_c'length - 1);
      from_l5_i : in committed_req_array(0 to udp_port_c'length - 1);
      from_l5_o : out committed_ack_array(0 to udp_port_c'length - 1);

      from_l3_i : in committed_req;
      from_l3_o : out committed_ack;
      to_l3_o : out committed_req;
      to_l3_i : in committed_ack
      );
  end component;

  function udp_pack(
    destination, source : udp_port_t;
    data : byte_string;
    header_checksum : boolean := false) return byte_string;

end package;

package body udp is

  function udp_pack(
    destination, source : udp_port_t;
    data : byte_string;
    header_checksum : boolean := false) return byte_string
  is
    variable dp, sp, len, c: unsigned(15 downto 0);
  begin
    dp := to_unsigned(destination, 16);
    sp := to_unsigned(source, 16);
    len := to_unsigned(data'length + 8, 16);
    if header_checksum then
      c := x"ffff";
      c := c - dp - sp - len;
    else
      c := x"0000";
    end if;

    return to_be(sp) & to_be(dp) & to_be(len) & to_be(c) & data;
  end function;

end package body;
