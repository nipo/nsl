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
  function to_status(ibs: std_ulogic_vector(3 downto 0)) return link_status_t;
  function to_logic(ibs: link_status_t) return std_ulogic_vector;
  function to_speed(ibs_speed: std_ulogic_vector(1 downto 0)) return link_speed_t;
  function to_logic(speed: link_speed_t) return std_ulogic_vector;

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

  function to_status(ibs: std_ulogic_vector(3 downto 0)) return link_status_t
  is
    variable ret: link_status_t;
  begin
    ret.up := ibs(0) = '1';

    ret.speed := to_speed(ibs(2 downto 1));

    if ibs(3) = '1' then
      ret.duplex := LINK_DUPLEX_FULL;
    else
      ret.duplex := LINK_DUPLEX_HALF;
    end if;

    return ret;
  end function;

  function to_logic(ibs: link_status_t) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(3 downto 0) := "0000";
  begin
    if ibs.up then
      ret(0) := '1';
    end if;

    ret(2 downto 1) := to_logic(ibs.speed);

    if ibs.duplex = LINK_DUPLEX_FULL then
      ret(3) := '1';
    end if;

    return ret;
  end function;

  function to_speed(ibs_speed: std_ulogic_vector(1 downto 0)) return link_speed_t
  is
  begin
    case ibs_speed is
      when "00" => return LINK_SPEED_10;
      when "01" => return LINK_SPEED_100;
      when others => return LINK_SPEED_1000;
    end case;
  end function;
  
  function to_logic(speed: link_speed_t) return std_ulogic_vector
  is
  begin
    case speed is
      when LINK_SPEED_10 => return "00";
      when LINK_SPEED_100 => return "01";
      when others => return "10";
    end case;
  end function;

end package body;
