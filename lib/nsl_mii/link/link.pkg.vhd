library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package link is

  type link_speed_t is (
    LINK_SPEED_10,
    LINK_SPEED_100,
    LINK_SPEED_1000
    );

  type link_duplex_t is (
    LINK_DUPLEX_FULL,
    LINK_DUPLEX_HALF
    );

  type link_status_t is
  record
    up: boolean;
    speed: link_speed_t;
    duplex: link_duplex_t;
  end record;

  constant link_down_c: link_status_t := (false, LINK_SPEED_10, LINK_DUPLEX_HALF);
  constant link_10_hd_c: link_status_t := (true, LINK_SPEED_10, LINK_DUPLEX_HALF);
  constant link_100_hd_c: link_status_t := (true, LINK_SPEED_100, LINK_DUPLEX_HALF);
  constant link_1000_hd_c: link_status_t := (true, LINK_SPEED_1000, LINK_DUPLEX_HALF);
  constant link_10_fd_c: link_status_t := (true, LINK_SPEED_10, LINK_DUPLEX_FULL);
  constant link_100_fd_c: link_status_t := (true, LINK_SPEED_100, LINK_DUPLEX_FULL);
  constant link_1000_fd_c: link_status_t := (true, LINK_SPEED_1000, LINK_DUPLEX_FULL);
  
  function to_string(speed: link_speed_t) return string;

end package link;

package body link is

  function to_string(speed: link_speed_t) return string
  is
  begin
    case speed is
      when LINK_SPEED_10   => return "10M";
      when LINK_SPEED_100  => return "100M";
      when LINK_SPEED_1000 => return "1G";
    end case;
  end function;

end package body;
