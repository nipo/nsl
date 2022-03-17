library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_mii, nsl_data, nsl_simulation, nsl_math, nsl_logic;
use nsl_mii.mii.all;
use nsl_data.crc.all;
use nsl_simulation.logging.all;
use nsl_logic.bool.all;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;

package testing is

  procedure mii_status_init(signal mii: out mii_status_p2m);
  procedure mii_tx_init(signal mii: out mii_tx_p2m);
  procedure mii_rx_init(signal mii: out mii_rx_p2m);
  procedure mii_interframe_put(signal mii: out mii_rx_p2m;
                               constant ipg_time: natural := 96/8;
                               constant rate: natural := 100);
  procedure mii_frame_put(signal mii: out mii_rx_p2m;
                            constant data : byte_string;
                            constant rate: natural := 100;
                            constant pre_count : natural := 8;
                            constant error_at_bit : integer := -1);

  procedure mii_frame_get(signal o: out mii_tx_p2m;
                          signal i: in mii_tx_m2p;
                          data : inout byte_stream;
                          valid : out boolean;
                          constant rate: natural := 100);

  procedure mii_frame_check(
    log_context: string;
    signal o: out mii_tx_p2m;
    signal i: in mii_tx_m2p;
    data : in byte_string;
    valid : in boolean;
    constant rate: natural := 100;
    level : log_level_t := LOG_LEVEL_WARNING);
  
end testing;

package body testing is

  procedure mii_put_byte(signal mii: out mii_rx_p2m;
                         constant rxd : byte;
                         constant dv, err : boolean;
                         constant rate: integer)
  is
    constant cycle_time: time := 4 * 1e6 ps / rate;
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
                               constant rate: natural := 100)
  is
  begin
    log_debug("* MII < wait " & to_string(ipg_time) & " bit time");
    
    for i in 0 to ipg_time/8 - 1
    loop
      mii_put_byte(mii, "--------", false, false, rate);
    end loop;
  end procedure;

  procedure mii_frame_put(signal mii: out mii_rx_p2m;
                            constant data : byte_string;
                            constant rate: natural := 100;
                            constant pre_count : natural := 8;
                            constant error_at_bit : integer := -1)
  is
    variable error_at_byte : integer;
  begin
    log_debug("* MII < " & to_string(data) & ", rate: " & to_string(rate));

    error_at_byte := -1;
    if error_at_bit >= 0 then
      error_at_byte := error_at_bit / 8;
    end if;
                     
    if pre_count > 0
    then
      for i in 0 to pre_count-2
      loop
        mii_put_byte(mii, x"55", true, false, rate);
      end loop;

      mii_put_byte(mii, x"d5", true, false, rate);
    end if;

    for i in data'range
    loop
      mii_put_byte(mii, data(i), error_at_byte /= i, error_at_byte = i, rate);
    end loop;
  end procedure;

  procedure mii_nibble_get(signal o: out mii_tx_p2m;
                           signal i: in mii_tx_m2p;
                           data : out std_ulogic_vector(3 downto 0);
                           valid : out boolean;
                           error: out boolean;
                           constant rate: natural)
  is
    constant cycle_time: time := 4 * 1e6 ps / rate;
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
                          constant rate: natural := 100)
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
        mii_nibble_get(o, i, nibble0, v0, e0, rate);
      end loop;

      while nibble0 = x"5"
      loop
        mii_nibble_get(o, i, nibble0, v0, e0, rate);
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
        mii_nibble_get(o, i, nibble0, v0, e0, rate);
        mii_nibble_get(o, i, nibble1, v1, e1, rate);
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
    constant rate: natural := 100;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable rx_data: byte_stream := new byte_string(1 to 0);
    variable rx_valid: boolean;
  begin
    mii_frame_get(o, i, rx_data, rx_valid, rate);
    
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
