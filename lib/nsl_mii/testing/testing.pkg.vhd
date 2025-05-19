library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_mii, nsl_data, nsl_simulation, nsl_math, nsl_logic;
use nsl_mii.link.all;
use nsl_mii.rgmii.all;
use nsl_mii.rmii.all;
use nsl_mii.mii.all;
use nsl_data.crc.all;
use nsl_simulation.logging.all;
use nsl_logic.bool.all;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;

package testing is

  procedure rgmii_put_init(signal rgmii: out rgmii_io_group_t);
  procedure rgmii_interframe_put(signal rgmii: out rgmii_io_group_t;
                                 constant ipg_time: natural := 96/8;
                                 constant speed: link_speed_t := LINK_SPEED_1000;
                                 constant link_up: boolean := true;
                                 constant full_duplex: boolean := true);
  procedure rgmii_frame_put(signal rgmii: out rgmii_io_group_t;
                            constant data : byte_string;
                            constant speed: link_speed_t := LINK_SPEED_1000;
                            constant pre_count : natural := 8;
                            constant error_at_bit : integer := -1);

  procedure rgmii_frame_get(signal rgmii: in rgmii_io_group_t;
                            data : inout byte_stream;
                            valid : out boolean;
                            constant speed: link_speed_t := LINK_SPEED_1000);

  procedure rgmii_frame_check(
    log_context: string;
    signal rgmii: in rgmii_io_group_t;
    data : in byte_string;
    valid : in boolean;
    constant speed: link_speed_t := LINK_SPEED_1000;
    level : log_level_t := LOG_LEVEL_WARNING);

  procedure mii_status_init(signal mii: out mii_status_p2m);
  procedure mii_tx_init(signal mii: out mii_tx_p2m);
  procedure mii_rx_init(signal mii: out mii_rx_p2m);
  procedure mii_interframe_put(signal mii: out mii_rx_p2m;
                               constant ipg_time: natural := 96/8;
                               constant speed: link_speed_t := LINK_SPEED_100);
  procedure mii_frame_put(signal mii: out mii_rx_p2m;
                            constant data : byte_string;
                            constant speed: link_speed_t := LINK_SPEED_100;
                            constant pre_count : natural := 8;
                            constant error_at_bit : integer := -1);

  procedure mii_frame_get(signal o: out mii_tx_p2m;
                          signal i: in mii_tx_m2p;
                          data : inout byte_stream;
                          valid : out boolean;
                          constant speed: link_speed_t := LINK_SPEED_100);

  procedure mii_frame_check(
    log_context: string;
    signal o: out mii_tx_p2m;
    signal i: in mii_tx_m2p;
    data : in byte_string;
    valid : in boolean;
    constant speed: link_speed_t := LINK_SPEED_100;
    level : log_level_t := LOG_LEVEL_WARNING);


  procedure rmii_init(signal rmii: out rmii_p2m);
  procedure rmii_interframe_put(signal ref_clock: in std_ulogic;
                                signal rmii: out rmii_p2m;
                                constant ipg_time: natural := 96/8;
                                constant speed: link_speed_t := LINK_SPEED_100);
  procedure rmii_frame_put(signal ref_clock: in std_ulogic;
                           signal rmii: out rmii_p2m;
                           constant data : byte_string;
                           constant speed: link_speed_t := LINK_SPEED_100;
                           constant pre_count : natural := 8;
                           constant error_at_bit : integer := -1);

  procedure rmii_frame_get(signal ref_clock: in std_ulogic;
                           signal rmii: in rmii_m2p;
                           data : inout byte_stream;
                           valid : out boolean;
                           constant speed: link_speed_t := LINK_SPEED_100);

  procedure rmii_frame_check(
    log_context: string;
    signal ref_clock: in std_ulogic;
    signal rmii: in rmii_m2p;
    data : in byte_string;
    valid : in boolean;
    constant speed: link_speed_t := LINK_SPEED_100;
    level : log_level_t := LOG_LEVEL_WARNING);
  
end testing;

package body testing is

  function bit_time_ns(constant speed: link_speed_t) return integer
  is
  begin
    case speed is
      when LINK_SPEED_10 => return 100;
      when LINK_SPEED_100 => return 10;
      when LINK_SPEED_1000 => return 1;
    end case;
    return 0;
  end function;
  
  procedure rgmii_put_byte(signal rgmii: out rgmii_io_group_t;
                          constant rxd : byte;
                          constant dv, err : boolean;
                          constant speed: link_speed_t := LINK_SPEED_1000)
  is
  begin
    case speed is
      when LINK_SPEED_10 =>
        rgmii.d <= rxd(3 downto 0);
        rgmii.ctl <= to_logic(dv);
        wait for 2 ns;
        rgmii.c <= '1';
        wait for 200 ns;
        rgmii.c <= '0';
        wait for 198 ns;

        rgmii.d <= rxd(7 downto 4);
        rgmii.ctl <= to_logic(err /= dv);
        wait for 2 ns;
        rgmii.c <= '1';
        wait for 200 ns;
        rgmii.c <= '0';
        wait for 198 ns;

      when LINK_SPEED_100 =>
        rgmii.d <= rxd(3 downto 0);
        rgmii.ctl <= to_logic(dv);
        wait for 2 ns;
        rgmii.c <= '1';
        wait for 20 ns;
        rgmii.c <= '0';
        wait for 18 ns;

        rgmii.d <= rxd(7 downto 4);
        rgmii.ctl <= to_logic(err /= dv);
        wait for 2 ns;
        rgmii.c <= '1';
        wait for 20 ns;
        rgmii.c <= '0';
        wait for 18 ns;

      when LINK_SPEED_1000 =>
        rgmii.d <= rxd(3 downto 0);
        rgmii.ctl <= to_logic(dv);
        wait for 2 ns;
        rgmii.c <= '1';
        wait for 2 ns;

        rgmii.d <= rxd(7 downto 4);
        rgmii.ctl <= to_logic(err /= dv);
        wait for 2 ns;
        rgmii.c <= '0';
        wait for 2 ns;
    end case;
  end procedure;
  
  procedure rgmii_put_init(signal rgmii: out rgmii_io_group_t)
  is
  begin
    log_debug("* Init");
    rgmii.d <= (others => '0');
    rgmii.c <= '0';
    rgmii.ctl <= '0';
    wait for 2 ns;
  end procedure;

  procedure rgmii_interframe_put(signal rgmii: out rgmii_io_group_t;
                                 constant ipg_time : natural := 96/8;
                                 constant speed: link_speed_t := LINK_SPEED_1000;
                                 constant link_up: boolean := true;
                                 constant full_duplex: boolean := true)
  is
    variable inband_status: byte;
  begin
    log_debug("* RGMII < wait " & to_string(ipg_time) & " bit time");

    inband_status(0) := to_logic(link_up);
    inband_status(2 downto 1) := to_logic(speed);
    inband_status(3) := to_logic(full_duplex);
    inband_status(7 downto 4) := inband_status(3 downto 0);
    
    for i in 0 to ipg_time/8 - 1
    loop
      rgmii_put_byte(rgmii, inband_status, false, false, speed);
    end loop;
  end procedure;

  procedure rgmii_frame_put(signal rgmii: out rgmii_io_group_t;
                            constant data : byte_string;
                            constant speed: link_speed_t := LINK_SPEED_1000;
                            constant pre_count : natural := 8;
                            constant error_at_bit : integer := -1)
  is
    variable error_at_byte : integer;
  begin
    log_debug("* RGMII < " & to_string(data) & ", speed: " & to_string(speed));

    error_at_byte := -1;
    if error_at_bit >= 0 then
      error_at_byte := error_at_bit / 8;
    end if;
                     
    if pre_count > 0
    then
      for i in 0 to pre_count-2
      loop
        rgmii_put_byte(rgmii, x"55", true, false, speed);
      end loop;

      rgmii_put_byte(rgmii, x"d5", true, false, speed);
    end if;

    for i in data'range
    loop
      rgmii_put_byte(rgmii, data(i), error_at_byte /= i, error_at_byte = i, speed);
    end loop;
  end procedure;

  procedure rgmii_cycle_get(signal rgmii: in rgmii_io_group_t;
                            data : out byte;
                            ctlh, ctll : out boolean;
                            constant speed: link_speed_t := LINK_SPEED_100)
  is
    variable v: boolean;
    variable d: byte;
  begin
    wait until rising_edge(rgmii.c);
    data(3 downto 0) := rgmii.d;
    ctlh := rgmii.ctl = '1';
    wait until falling_edge(rgmii.c);
    data(7 downto 4) := rgmii.d;
    ctll := rgmii.ctl = '1';
  end procedure;

  procedure rgmii_byte_get(signal rgmii: in rgmii_io_group_t;
                           data : out byte;
                           valid : out boolean;
                           error: out boolean;
                           constant speed: link_speed_t := LINK_SPEED_1000)
  is
    variable c0, c1, drop: boolean;
    variable d0, d1: byte;
  begin
    case speed is
      when LINK_SPEED_10 | LINK_SPEED_100 =>
        rgmii_cycle_get(rgmii, d0, c0, drop, speed);
        rgmii_cycle_get(rgmii, d1, c1, drop, speed);

        data := d1(3 downto 0) & d0(3 downto 0);
        valid := c0;
        error := c0 /= c1;

      when LINK_SPEED_1000 =>
        rgmii_cycle_get(rgmii, d0, c0, c1, speed);

        data := d0;
        valid := c0;
        error := c0 /= c1;
    end case;
  end procedure;

  procedure rgmii_frame_get(signal rgmii: in rgmii_io_group_t;
                            data : inout byte_stream;
                            valid : out boolean;
                            constant speed: link_speed_t := LINK_SPEED_1000)
  is
    variable ret: byte_stream;
    variable v, e, c0, c1, frame_valid: boolean;
    variable tmp, b: byte;
  begin
    deallocate(data);
    ret := new byte_string(1 to 0);
    v := false;
    frame_valid := true;

    while not v
    loop
      rgmii_byte_get(rgmii, b, v, e, speed);
    end loop;

    rgmii_byte_get(rgmii, b, v, e, speed);

    while b = x"55" and v
    loop
      rgmii_byte_get(rgmii, b, v, e, speed);
    end loop;

    if not v then
      return;
    end if;

    if b(3 downto 0) = x"d" and (speed = LINK_SPEED_100 or speed = LINK_SPEED_10) then
      -- realignment hack for 10/100
      rgmii_cycle_get(rgmii, tmp, c0, c1, speed);
      b := tmp(3 downto 0) & b(7 downto 4);
      v := v xor e;
      e := v xor c0;
      
      write(ret, b);

      -- continue with next loop
      b := x"d5";
    end if;

    if b = x"d5" then
      while v
      loop
        rgmii_byte_get(rgmii, b, v, e, speed);
        if v then
          frame_valid := frame_valid and not e;
          write(ret, b);
        end if;
      end loop;
    else
      frame_valid := false;
      while v
      loop
        rgmii_byte_get(rgmii, b, v, e, speed);
      end loop;
    end if;
    
    valid := frame_valid;
    data := ret;
  end procedure;

  procedure rgmii_frame_check(
    log_context: string;
    signal rgmii: in rgmii_io_group_t;
    data : in byte_string;
    valid : in boolean;
    constant speed: link_speed_t := LINK_SPEED_1000;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable rx_data: byte_stream;
    variable rx_valid: boolean;
  begin
    rgmii_frame_get(rgmii, rx_data, rx_valid, speed);
    
    if valid /= rx_valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** Expected valid = " & to_string(valid));
      return;
    end if;

    if not valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", not valid, as expected");
      return;
    end if;

    if not rx_valid then
      log_info(log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", rx valid: " & to_string(rx_valid)
          & " OK");
      return;
    end if;

    if rx_data.all'length /= data'length
      or rx_data.all /= data then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** BAD");
      log(level, log_context & ": " &
          " * " & to_string(data)
          & ", valid: " & to_string(valid)
          & " *** Expected");
      return;
    end if;

    log_info(log_context & ": " &
             " > " & to_string(rx_data.all)
             & ", valid: " & to_string(rx_valid)
             & " OK");
  end procedure;

  procedure mii_put_byte(signal mii: out mii_rx_p2m;
                         constant rxd : byte;
                         constant dv, err : boolean;
                         constant speed: link_speed_t)
  is
    constant cycle_time : time := bit_time_ns(speed) * 4 ns;
  begin
    for off in 0 to 1
    loop
      mii.clk <= '1';
      wait for cycle_time / 2;

      mii.clk <= '0';
      wait for 2000 ps;
      mii.d <= rxd(off*4+3 downto off*4+0);
      mii.dv <= to_logic(dv);
      mii.er <= to_logic(err);
      wait for cycle_time / 2 - 2000 ps;
    end loop;
  end procedure;

  procedure mii_status_init(signal mii: out mii_status_p2m)
  is
  begin
    mii.col <= '0';
    mii.crs <= '0';
  end procedure;

  procedure mii_rx_init(signal mii: out mii_rx_p2m)
  is
  begin
    mii.clk <= '0';
    mii.dv <= '0';
    mii.er <= '0';
    mii.d <= x"0";
  end procedure;

  procedure mii_tx_init(signal mii: out mii_tx_p2m)
  is
  begin
    mii.clk <= '0';
  end procedure;

  procedure mii_interframe_put(signal mii: out mii_rx_p2m;
                               constant ipg_time: natural := 96/8;
                               constant speed: link_speed_t := LINK_SPEED_100)
  is
  begin
    log_debug("* MII < wait " & to_string(ipg_time) & " bit time");
    
    for i in 0 to ipg_time/8 - 1
    loop
      mii_put_byte(mii, "--------", false, false, speed);
    end loop;
  end procedure;

  procedure mii_frame_put(signal mii: out mii_rx_p2m;
                            constant data : byte_string;
                            constant speed: link_speed_t := LINK_SPEED_100;
                            constant pre_count : natural := 8;
                            constant error_at_bit : integer := -1)
  is
    variable error_at_byte : integer;
  begin
    log_debug("* MII < " & to_string(data) & ", speed: " & to_string(speed));

    error_at_byte := -1;
    if error_at_bit >= 0 then
      error_at_byte := error_at_bit / 8;
    end if;
                     
    if pre_count > 0
    then
      for i in 0 to pre_count-2
      loop
        mii_put_byte(mii, x"55", true, false, speed);
      end loop;

      mii_put_byte(mii, x"d5", true, false, speed);
    end if;

    for i in data'range
    loop
      mii_put_byte(mii, data(i), error_at_byte /= i, error_at_byte = i, speed);
    end loop;
  end procedure;

  procedure mii_nibble_get(signal o: out mii_tx_p2m;
                           signal i: in mii_tx_m2p;
                           data : out std_ulogic_vector(3 downto 0);
                           valid : out boolean;
                           error: out boolean;
                           constant speed: link_speed_t)
  is
    constant cycle_time : time := bit_time_ns(speed) * 4 ns;
  begin
      o.clk <= '1';
      data := i.d;
      valid := i.en = '1';
      error := i.er = '1';
      wait for cycle_time / 2;

      o.clk <= '0';
      wait for cycle_time / 2;
  end procedure;

  procedure mii_frame_get(signal o: out mii_tx_p2m;
                          signal i: in mii_tx_m2p;
                          data : inout byte_stream;
                          valid : out boolean;
                          constant speed: link_speed_t := LINK_SPEED_100)
  is
    variable ret: byte_stream;
    variable nibble0, nibble1: std_ulogic_vector(3 downto 0);
    variable v0, e0, v1, e1, frame_valid: boolean;
  begin
    deallocate(data);
    ret := new byte_string(1 to 0);
    v0 := false;
    v1 := true;
    frame_valid := true;
    valid := false;

    while true
    loop
      while not v0
      loop
        mii_nibble_get(o, i, nibble0, v0, e0, speed);
      end loop;

      while nibble0 = x"5"
      loop
        mii_nibble_get(o, i, nibble0, v0, e0, speed);
        if e0 then
          return;
        end if;
      end loop;

      if nibble0 /= x"5" then
        exit;
      end if;
    end loop;

    if nibble0 = x"d" then
      while v0 and v1
      loop
        mii_nibble_get(o, i, nibble0, v0, e0, speed);
        mii_nibble_get(o, i, nibble1, v1, e1, speed);
        if v0 and v1 then
          frame_valid := frame_valid and not e0 and not e1;
          write(ret, byte'(nibble1 & nibble0));
        end if;
      end loop;
    end if;

    valid := frame_valid;
    data := ret;
  end procedure;

  procedure mii_frame_check(
    log_context: string;
    signal o: out mii_tx_p2m;
    signal i: in mii_tx_m2p;
    data : in byte_string;
    valid : in boolean;
    constant speed: link_speed_t := LINK_SPEED_100;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable rx_data: byte_stream := new byte_string(1 to 0);
    variable rx_valid: boolean;
  begin
    mii_frame_get(o, i, rx_data, rx_valid, speed);
    
    if valid /= rx_valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** Expected valid = " & to_string(valid));
      return;
    end if;

    if not valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", not valid, as expected");
      return;
    end if;

    if not rx_valid then
      log_info(log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", rx valid: " & to_string(rx_valid)
          & " OK");
      return;
    end if;

    if rx_data.all'length /= data'length
      or rx_data.all /= data then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** BAD");
      log(level, log_context & ": " &
          " * " & to_string(data)
          & ", valid: " & to_string(valid)
          & " *** Expected");
      return;
    end if;

    log_info(log_context & ": " &
             " > " & to_string(rx_data.all)
             & ", valid: " & to_string(rx_valid)
             & " OK");
  end procedure;


  procedure rmii_put_byte(signal ref_clock: in std_ulogic;
                          signal rmii: out rmii_p2m;
                          constant rxd : byte;
                          constant dv, crs, err : boolean;
                          constant speed: link_speed_t)
  is
    constant cycle_time : time := bit_time_ns(speed) * 4 ns;
  begin
    for off in 0 to 3
    loop
      wait until falling_edge(ref_clock);
      rmii.rx_d <= rxd(off*2+1 downto off*2+0);
      rmii.rx_er <= to_logic(err);
      if off = 0 or off = 2 then
        rmii.crs_dv <= to_logic(crs);
      else
        rmii.crs_dv <= to_logic(dv);
      end if;
      wait until rising_edge(ref_clock);
    end loop;
  end procedure;

  procedure rmii_init(signal rmii: out rmii_p2m)
  is
  begin
    rmii.rx_d <= "00";
    rmii.rx_er <= '0';
    rmii.crs_dv <= '0';
  end procedure;

  procedure rmii_interframe_put(signal ref_clock: in std_ulogic;
                                signal rmii: out rmii_p2m;
                                constant ipg_time: natural := 96/8;
                                constant speed: link_speed_t := LINK_SPEED_100)
  is
  begin
    log_debug("* RMII < wait " & to_string(ipg_time) & " bit time");
    
    for i in 0 to ipg_time/8 - 1
    loop
      rmii_put_byte(ref_clock, rmii, "--------", false, false, false, speed);
    end loop;
  end procedure;

  procedure rmii_frame_put(signal ref_clock: in std_ulogic;
                           signal rmii: out rmii_p2m;
                           constant data : byte_string;
                           constant speed: link_speed_t := LINK_SPEED_100;
                           constant pre_count : natural := 8;
                           constant error_at_bit : integer := -1)
  is
    variable error_at_byte : integer;
  begin
    log_debug("* RMII < " & to_string(data) & ", speed: " & to_string(speed));

    error_at_byte := -1;
    if error_at_bit >= 0 then
      error_at_byte := error_at_bit / 8;
    end if;
                     
    if pre_count > 0
    then
      for i in 0 to pre_count-2
      loop
        rmii_put_byte(ref_clock, rmii, x"55", true, true, false, speed);
      end loop;

      rmii_put_byte(ref_clock, rmii, x"d5", true, true, false, speed);
    end if;

    for i in data'range
    loop
      rmii_put_byte(ref_clock, rmii, data(i),
                    true, true, error_at_byte = i, speed);
    end loop;
  end procedure;

  procedure rmii_dibit_get(signal ref_clock: in std_ulogic;
                           signal rmii: in rmii_m2p;
                           data : out std_ulogic_vector(1 downto 0);
                           en : out std_ulogic)
  is
  begin
    wait until rising_edge(ref_clock);
    data := rmii.tx_d;
    en := rmii.tx_en;
  end procedure;

  procedure rmii_frame_get(signal ref_clock: in std_ulogic;
                           signal rmii: in rmii_m2p;
                           data : inout byte_stream;
                           valid : out boolean;
                           constant speed: link_speed_t := LINK_SPEED_100)
  is
    variable ret: byte_stream;
    variable word: std_ulogic_vector(7 downto 0);
    variable en: std_ulogic_vector(3 downto 0);
    variable d: std_ulogic_vector(1 downto 0);
    variable e: std_ulogic;
    variable frame_valid: boolean;
  begin
    deallocate(data);
    ret := new byte_string(1 to 0);
    word := (others => '-');
    frame_valid := true;
    valid := false;

    while true
    loop
      en := (others => '0');

      while en /= "1111"
      loop
        rmii_dibit_get(ref_clock, rmii, d, e);
        en := e & en(3 downto 1);
        word := d & word(7 downto 2);
      end loop;

      while word /= x"55"
      loop
        rmii_dibit_get(ref_clock, rmii, d, e);
        en := e & en(3 downto 1);
        word := d & word(7 downto 2);
        if e = '0' then
          exit;
        end if;
      end loop;

      while word = x"55"
      loop
        rmii_dibit_get(ref_clock, rmii, d, e);
        en := e & en(3 downto 1);
        word := d & word(7 downto 2);
        if e = '0' then
          exit;
        end if;
      end loop;

      if word = x"d5" then
        exit;
      end if;
    end loop;

    while en = "1111"
    loop
      for i in 0 to 3
      loop
        rmii_dibit_get(ref_clock, rmii, d, e);
        en := e & en(3 downto 1);
        word := d & word(7 downto 2);
      end loop;

      if en = "1111" then
        write(ret, byte(word));
      end if;
    end loop;

    valid := true;
    data := ret;
  end procedure;

  procedure rmii_frame_check(
    log_context: string;
    signal ref_clock: in std_ulogic;
    signal rmii: in rmii_m2p;
    data : in byte_string;
    valid : in boolean;
    constant speed: link_speed_t := LINK_SPEED_100;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable rx_data: byte_stream := new byte_string(1 to 0);
    variable rx_valid: boolean;
  begin
    rmii_frame_get(ref_clock, rmii, rx_data, rx_valid, speed);
    
    if valid /= rx_valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** Expected valid = " & to_string(valid));
      return;
    end if;

    if not valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", not valid, as expected");
      return;
    end if;

    if not rx_valid then
      log_info(log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", rx valid: " & to_string(rx_valid)
          & " OK");
      return;
    end if;

    if rx_data.all'length /= data'length
      or rx_data.all /= data then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** BAD");
      log(level, log_context & ": " &
          " * " & to_string(data)
          & ", valid: " & to_string(valid)
          & " *** Expected");
      return;
    end if;

    log_info(log_context & ": " &
             " > " & to_string(rx_data.all)
             & ", valid: " & to_string(rx_valid)
             & " OK");
  end procedure;
  
end testing;
