library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_inet, nsl_data;
use nsl_simulation.logging.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_inet.ethernet.all;
use nsl_inet.ipv4.all;
use nsl_inet.udp.all;

package testing is

  procedure arp_dump(prefix: string;
                     packet: byte_string);
  procedure icmp_dump(prefix: string;
                      packet: byte_string);
  procedure udp_dump(prefix: string;
                     packet: byte_string);
  procedure ip_dump(prefix: string;
                    packet: byte_string);
  procedure ethernet_dump(prefix: string;
                          frame: byte_string);

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

  procedure ip_dump(prefix: string;
                    packet: byte_string) is
    alias xpacket: byte_string(0 to packet'length-1) is packet;
    variable sum: checksum_t;
    constant header_len : integer := 4 * to_integer(unsigned(xpacket(0)(3 downto 0)));
    constant src: ipv4_t := xpacket(ip_off_src0 to ip_off_src3);
    constant dst: ipv4_t := xpacket(ip_off_dst0 to ip_off_dst3);
    constant proto: ip_proto_t := to_integer(xpacket(ip_off_proto));
    constant total_len : integer := to_integer(from_be(xpacket(ip_off_len_h to ip_off_len_l)));
    constant payload : byte_string(0 to total_len - header_len - 1)
      := xpacket(header_len to total_len-1);
  begin
    if xpacket(0)(7 downto 4) /= x"4" then
      log_error(prefix&"IP bad version");
      return;
    end if;

    if not checksum_is_valid(xpacket(0 to header_len-1)) then
      log_error(prefix&"IP bad header checksum");
      return;
    end if;

    log_info(prefix&"IP from "&ip_to_string(src)&" to "&ip_to_string(dst));

    case proto is
      when ip_proto_icmp =>
        icmp_dump(prefix&"   ", payload);

      when ip_proto_udp =>
        udp_dump(prefix&"   ", payload);

      when others =>
        log_info(prefix&"proto "&to_string(proto)&": "& to_string(payload));
    end case;
  end procedure;

  procedure ethernet_dump(prefix: string;
                          frame: byte_string) is
    alias xframe: byte_string(0 to frame'length-1) is frame;
    constant fcs_valid: boolean := frame_is_fcs_valid(xframe);
    constant daddr: mac48_t := frame_daddr_get(xframe);
    constant saddr: mac48_t := frame_saddr_get(xframe);
    constant ethertype: ethertype_t := frame_ethertype_get(xframe);
  begin
    log_info(prefix & "Frame from " & mac_to_string(saddr)
             & " to " & mac_to_string(daddr)
             & " FCS " & if_else(fcs_valid, "OK", "Bad"));

    if not fcs_valid then
      return;
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

end package body testing;
