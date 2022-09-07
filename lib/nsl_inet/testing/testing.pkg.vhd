library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, work, nsl_data, nsl_math;
use nsl_simulation.logging.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_data.binary_io.all;
use work.ethernet.all;
use work.ipv4.all;
use work.checksum.all;
use work.udp.all;

package testing is

  procedure arp_dump(prefix: string;
                     packet: byte_string);
  procedure icmp_dump(prefix: string;
                      packet: byte_string);
  procedure udp_dump(prefix: string;
                     packet: byte_string);
  procedure tcp_dump(prefix: string;
                     packet: byte_string);
  procedure ip_dump(prefix: string;
                    packet: byte_string);
  procedure ethernet_dump(prefix: string;
                          frame: byte_string;
                          has_fcs: boolean := true);
  
  type pcap_header_t is
  record
    is_valid: boolean;
    endian: endian_t;
    has_ns_timestamp: boolean;
    major, minor: integer range 0 to 65535;
    snap_length: integer;
    link_type: integer;
    fcs_present: boolean;
    fcs_length: integer range 0 to 7;
    base_sec: integer;
  end record;

  type pcap_packet_t is
  record
    data: byte_stream;
    original_length: integer;
    timestamp: time;
  end record;

  procedure pcap_read(file pcap_file: binary_file; header: out pcap_header_t);
  procedure pcap_read(file pcap_file: binary_file; variable header: inout pcap_header_t; packet: out pcap_packet_t);
  procedure pcap_packet_free(packet: inout pcap_packet_t);

end package testing;

package body testing is

  procedure arp_dump(prefix: string;
                     packet: byte_string) is
    alias xpacket: byte_string(0 to packet'length-1) is packet;
    variable tha, sha: mac48_t;
    variable tpa, spa: ipv4_t;
    variable oper: integer;
  begin
    if from_be(xpacket(0 to 1)) /= 1 then
      log_error(prefix&"ARP Bad HTYPE");
      return;
    end if;

    if from_be(xpacket(2 to 3)) /= 16#0800# then
      log_error(prefix&"ARP Bad PTYPE");
      return;
    end if;

    if from_be(xpacket(4 to 4)) /= 6 then
      log_error(prefix&"ARP Bad HLEN");
      return;
    end if;

    if from_be(xpacket(5 to 5)) /= 4 then
      log_error(prefix&"ARP Bad PLEN");
      return;
    end if;

    if xpacket'length < 28 then
      log_error(prefix&"ARP Bad short packet");
      return;
    end if;

    oper := to_integer(from_be(xpacket(6 to 7)));
    sha := xpacket( 8 to 13);
    spa := xpacket(14 to 17);
    tha := xpacket(18 to 23);
    tpa := xpacket(24 to 27);

    case oper is
      when 1 =>
        log_info(prefix&"ARP Request, who has "&ip_to_string(tpa)
                 &", tell "&ip_to_string(spa)&" ("&mac_to_string(sha)&")");

      when 2 =>
        log_info(prefix&"ARP Reply to "&ip_to_string(tpa)
                 &", "&ip_to_string(spa)&" is at "&mac_to_string(sha));

      when others =>
        log_info(prefix&"ARP Bad OPER: "& to_string(to_integer(from_be(xpacket(6 to 7)))));
    end case;
  end procedure;

  procedure icmp_dump(prefix: string;
                      packet: byte_string) is
    alias xpacket: byte_string(0 to packet'length-1) is packet;
  begin
    if not checksum_is_valid(xpacket) then
      log_info(prefix & "ICMP Bad checksum: "&to_string(xpacket));
    end if;
      
    log_info(prefix & "ICMP Type: "&to_string(to_integer(xpacket(0)))
             &" code: "&to_string(to_integer(xpacket(1)))
             &" chk: "&to_string(xpacket(2 to 3))
             &" header: "&to_string(xpacket(4 to 7)));
    log_info(prefix & "    Data: "&to_string(xpacket(8 to xpacket'right)));
  end procedure;

  procedure udp_dump(prefix: string;
                     packet: byte_string) is
    alias xpacket: byte_string(0 to packet'length-1) is packet;
    constant sport:integer := to_integer(from_be(xpacket(0 to 1)));
    constant dport:integer := to_integer(from_be(xpacket(2 to 3)));
  begin
    log_info(prefix&"UDP from "&to_string(sport)&" to "&to_string(dport));
    log_info(prefix&"    " & to_string(xpacket(8 to xpacket'right)));
  end procedure;

  procedure tcp_dump(prefix: string;
                     packet: byte_string) is
    alias xpacket: byte_string(0 to packet'length-1) is packet;
    constant sport:integer := to_integer(from_be(xpacket(0 to 1)));
    constant dport:integer := to_integer(from_be(xpacket(2 to 3)));
    constant sn:unsigned := from_be(xpacket(4 to 7));
    constant an:unsigned := from_be(xpacket(8 to 11));
    constant chk:unsigned := from_be(xpacket(16 to 17));
    constant hsize:integer := to_integer(unsigned(xpacket(12)(7 downto 4))) * 4;
    constant ns:boolean := xpacket(12)(0) = '1';
    constant fin:boolean := xpacket(13)(0) = '1';
    constant syn:boolean := xpacket(13)(1) = '1';
    constant rst:boolean := xpacket(13)(2) = '1';
    constant psh:boolean := xpacket(13)(3) = '1';
    constant ack:boolean := xpacket(13)(4) = '1';
    constant urg:boolean := xpacket(13)(5) = '1';
    constant ece:boolean := xpacket(13)(6) = '1';
    constant cwr:boolean := xpacket(13)(7) = '1';
    constant win:unsigned := from_be(xpacket(14 to 15));
  begin
    log_info(prefix&"TCP from "&to_string(sport)&" to "&to_string(dport));
    log_info(prefix&"    SN: " & to_string(sn));
    log_info(prefix&"    ACK: " & to_string(ack) & " " & to_string(an));
    log_info(prefix&"    WIN: " & to_string(win));
    log_info(prefix&"    CHK: " & to_string(chk));
    log_info(prefix&"    Flags: [" & if_else(syn, "S", "") & if_else(fin, "F", "")
             & if_else(rst, "R", "") & if_else(psh, "P", "") & if_else(ack, ".", "")
             & if_else(urg, "U", "") & if_else(ece, "E", "") & if_else(cwr, "C", "")
             & if_else(ns, "N", "") & "]");
    log_info(prefix&"    " & to_string(xpacket(hsize to xpacket'right)));
  end procedure;

  procedure ip_dump(prefix: string;
                    packet: byte_string) is
    alias xpacket: byte_string(0 to packet'length-1) is packet;
    constant header_len : integer := 4 * to_integer(unsigned(xpacket(0)(3 downto 0)));
    constant src: ipv4_t := xpacket(ip_off_src0 to ip_off_src3);
    constant dst: ipv4_t := xpacket(ip_off_dst0 to ip_off_dst3);
    constant proto: ip_proto_t := to_integer(xpacket(ip_off_proto));
    constant total_len : integer := to_integer(from_be(xpacket(ip_off_len_h to ip_off_len_l)));
    constant actual_len : integer := nsl_math.arith.min(packet'length, total_len);
    alias payload : byte_string(0 to actual_len - header_len - 1) is xpacket(header_len to actual_len-1);
  begin
    if xpacket(0)(7 downto 4) /= x"4" then
      log_error(prefix&"IP bad version");
      return;
    end if;

    if not checksum_is_valid(xpacket(0 to header_len-1)) then
      log_error(prefix&"IP bad header checksum:" & to_string(checksum_spill(checksum_update(checksum_acc_init_c, xpacket(0 to header_len-1)))));
      return;
    end if;

    log_info(prefix&"IP from "&ip_to_string(src)&" to "&ip_to_string(dst));

    case proto is
      when ip_proto_icmp =>
        icmp_dump(prefix&"   ", payload);

      when ip_proto_udp =>
        udp_dump(prefix&"   ", payload);

      when ip_proto_tcp =>
        tcp_dump(prefix&"   ", payload);

      when others =>
        log_info(prefix&"proto "&to_string(proto)&": "& to_string(payload));
    end case;
  end procedure;

  procedure ethernet_dump(prefix: string;
                          frame: byte_string;
                          has_fcs: boolean := true) is
    alias xframe: byte_string(0 to frame'length-1) is frame;
    constant fcs_valid: boolean := frame_is_fcs_valid(xframe);
    constant daddr: mac48_t := frame_daddr_get(xframe);
    constant saddr: mac48_t := frame_saddr_get(xframe);
    constant ethertype: ethertype_t := frame_ethertype_get(xframe);
  begin
    if has_fcs then
      log_info(prefix & "Frame from " & mac_to_string(saddr)
               & " to " & mac_to_string(daddr)
               & " FCS " & if_else(fcs_valid, "OK", "Bad"));

      if not fcs_valid then
        return;
      end if;
    else
      log_info(prefix & "Frame from " & mac_to_string(saddr)
               & " to " & mac_to_string(daddr)
               & " no FCS");
    end if;

    case ethertype is
      when ethertype_arp =>
        arp_dump(prefix & "+ ", frame_payload_get(xframe));
      when ethertype_ipv4 =>
        ip_dump(prefix & "+ ", frame_payload_get(xframe));
      when others =>
        log_info(prefix & "+ Type: " & to_string(ethertype));
        log_info(prefix & "+ " & to_string(frame_payload_get(xframe)));
    end case;
  end procedure;

  procedure pcap_read(file pcap_file: binary_file;
                      constant header: in pcap_header_t;
                      v: out unsigned)
  is
    variable blob: byte_string(0 to ((v'length + 7) / 8) - 1);
  begin
    read(pcap_file, blob);
    v := from_endian(blob, header.endian);
  end procedure;

  procedure pcap_read(file pcap_file: binary_file;
                      constant header: in pcap_header_t;
                      v: out signed)
  is
    variable uv: unsigned(v'range);
  begin
    pcap_read(pcap_file, header, uv);
    v := signed(uv);
  end procedure;

  procedure pcap_read_i32(file pcap_file: binary_file;
                      constant header: in pcap_header_t;
                      v: out integer)
  is
    variable sv: signed(31 downto 0);
  begin
    pcap_read(pcap_file, header, sv);
    v := to_integer(sv);
  end procedure;

  procedure pcap_read_i16(file pcap_file: binary_file;
                      constant header: in pcap_header_t;
                      v: out integer)
  is
    variable sv: signed(15 downto 0);
  begin
    pcap_read(pcap_file, header, sv);
    v := to_integer(sv);
  end procedure;
  
  procedure pcap_read(file pcap_file: binary_file; header: out pcap_header_t)
  is
    variable blob: byte_string(0 to 23);
    variable h: pcap_header_t;
    variable magic: unsigned(31 downto 0);
  begin
    h.is_valid := false;
    h.endian := ENDIAN_LITTLE;
    h.has_ns_timestamp := false;
    h.major := 0;
    h.minor := 0;
    h.snap_length := 0;
    h.link_type := 0;
    h.fcs_present := false;
    h.fcs_length := 0;
    h.base_sec := 0;

    pcap_read(pcap_file, h, magic);

    case magic is
      when x"d4c3b2a1" =>
        h.endian := ENDIAN_BIG;
        h.has_ns_timestamp := false;
      when x"4d3cb2a1" =>
        h.endian := ENDIAN_BIG;
        h.has_ns_timestamp := true;
      when x"a1b2c3d4" =>
        h.endian := ENDIAN_LITTLE;
        h.has_ns_timestamp := false;
      when x"a1b23c4d" =>
        h.endian := ENDIAN_LITTLE;
        h.has_ns_timestamp := true;
      when others =>
        header := h;
        return;
    end case;

    h.is_valid := true;
    pcap_read_i16(pcap_file, h, h.major);
    pcap_read_i16(pcap_file, h, h.minor);
    pcap_read(pcap_file, h, magic); -- Throw away
    pcap_read(pcap_file, h, magic); -- Throw away
    pcap_read_i32(pcap_file, h, h.snap_length);
    pcap_read_i32(pcap_file, h, h.link_type);
    h.fcs_length := h.link_type mod 8;
    h.fcs_present := ((h.link_type / 8) mod 2) = 1;
    h.link_type := h.link_type / 16;

    header := h;
  end procedure;
    
  procedure pcap_read(file pcap_file: binary_file;
                      variable header: inout pcap_header_t;
                      packet: out pcap_packet_t)
  is
    variable field: integer;
    variable p: pcap_packet_t;
  begin
    pcap_read_i32(pcap_file, header, field);
    if header.base_sec = 0 then
      header.base_sec := field;
    end if;
    field := field - header.base_sec;
    p.timestamp := field * 1 sec;
    pcap_read_i32(pcap_file, header, field);
    if header.has_ns_timestamp then
      p.timestamp := p.timestamp + field * 1 ns;
    else
      p.timestamp := p.timestamp + field * 1 ms;
    end if;

    pcap_read_i32(pcap_file, header, field);
    p.data := new byte_string(0 to field - 1);

    pcap_read_i32(pcap_file, header, field);
    p.original_length := field;

    read(pcap_file, p.data.all);

    packet := p;
  end procedure;

  procedure pcap_packet_free(packet: inout pcap_packet_t)
  is
  begin
    deallocate(packet.data);
    packet.data := null;
    packet.timestamp := 0 sec;
    packet.original_length := 0;
  end procedure;

end package body testing;
