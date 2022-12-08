library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.framed.all;
use nsl_bnoc.framed_transactor.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

package is31fl3731 is

  subtype is31fl3731_led_t is natural range 0 to 143;
  type is31fl3731_led_vector is array (integer range <>) of is31fl3731_led_t;

  -- IS31FL3731 datasheet Figure 8. Those names are not the most useful
  constant C1_1 : is31fl3731_led_t := 0;
  constant C1_2 : is31fl3731_led_t := 1;
  constant C1_3 : is31fl3731_led_t := 2;
  constant C1_4 : is31fl3731_led_t := 3;
  constant C1_5 : is31fl3731_led_t := 4;
  constant C1_6 : is31fl3731_led_t := 5;
  constant C1_7 : is31fl3731_led_t := 6;
  constant C1_8 : is31fl3731_led_t := 7;
  constant C1_9  : is31fl3731_led_t := 8;
  constant C1_10 : is31fl3731_led_t := 9;
  constant C1_11 : is31fl3731_led_t := 10;
  constant C1_12 : is31fl3731_led_t := 11;
  constant C1_13 : is31fl3731_led_t := 12;
  constant C1_14 : is31fl3731_led_t := 13;
  constant C1_15 : is31fl3731_led_t := 14;
  constant C1_16 : is31fl3731_led_t := 15;
  constant C2_1 : is31fl3731_led_t := 16;
  constant C2_2 : is31fl3731_led_t := 17;
  constant C2_3 : is31fl3731_led_t := 18;
  constant C2_4 : is31fl3731_led_t := 19;
  constant C2_5 : is31fl3731_led_t := 20;
  constant C2_6 : is31fl3731_led_t := 21;
  constant C2_7 : is31fl3731_led_t := 22;
  constant C2_8 : is31fl3731_led_t := 23;
  constant C2_9  : is31fl3731_led_t := 24;
  constant C2_10 : is31fl3731_led_t := 25;
  constant C2_11 : is31fl3731_led_t := 26;
  constant C2_12 : is31fl3731_led_t := 27;
  constant C2_13 : is31fl3731_led_t := 28;
  constant C2_14 : is31fl3731_led_t := 29;
  constant C2_15 : is31fl3731_led_t := 30;
  constant C2_16 : is31fl3731_led_t := 31;
  constant C3_1 : is31fl3731_led_t := 32;
  constant C3_2 : is31fl3731_led_t := 33;
  constant C3_3 : is31fl3731_led_t := 34;
  constant C3_4 : is31fl3731_led_t := 35;
  constant C3_5 : is31fl3731_led_t := 36;
  constant C3_6 : is31fl3731_led_t := 37;
  constant C3_7 : is31fl3731_led_t := 38;
  constant C3_8 : is31fl3731_led_t := 39;
  constant C3_9  : is31fl3731_led_t := 40;
  constant C3_10 : is31fl3731_led_t := 41;
  constant C3_11 : is31fl3731_led_t := 42;
  constant C3_12 : is31fl3731_led_t := 43;
  constant C3_13 : is31fl3731_led_t := 44;
  constant C3_14 : is31fl3731_led_t := 45;
  constant C3_15 : is31fl3731_led_t := 46;
  constant C3_16 : is31fl3731_led_t := 47;
  constant C4_1 : is31fl3731_led_t := 48;
  constant C4_2 : is31fl3731_led_t := 49;
  constant C4_3 : is31fl3731_led_t := 50;
  constant C4_4 : is31fl3731_led_t := 51;
  constant C4_5 : is31fl3731_led_t := 52;
  constant C4_6 : is31fl3731_led_t := 53;
  constant C4_7 : is31fl3731_led_t := 54;
  constant C4_8 : is31fl3731_led_t := 55;
  constant C4_9  : is31fl3731_led_t := 56;
  constant C4_10 : is31fl3731_led_t := 57;
  constant C4_11 : is31fl3731_led_t := 58;
  constant C4_12 : is31fl3731_led_t := 59;
  constant C4_13 : is31fl3731_led_t := 60;
  constant C4_14 : is31fl3731_led_t := 61;
  constant C4_15 : is31fl3731_led_t := 62;
  constant C4_16 : is31fl3731_led_t := 63;
  constant C5_1 : is31fl3731_led_t := 64;
  constant C5_2 : is31fl3731_led_t := 65;
  constant C5_3 : is31fl3731_led_t := 66;
  constant C5_4 : is31fl3731_led_t := 67;
  constant C5_5 : is31fl3731_led_t := 68;
  constant C5_6 : is31fl3731_led_t := 69;
  constant C5_7 : is31fl3731_led_t := 70;
  constant C5_8 : is31fl3731_led_t := 71;
  constant C5_9  : is31fl3731_led_t := 72;
  constant C5_10 : is31fl3731_led_t := 73;
  constant C5_11 : is31fl3731_led_t := 74;
  constant C5_12 : is31fl3731_led_t := 75;
  constant C5_13 : is31fl3731_led_t := 76;
  constant C5_14 : is31fl3731_led_t := 77;
  constant C5_15 : is31fl3731_led_t := 78;
  constant C5_16 : is31fl3731_led_t := 79;
  constant C6_1 : is31fl3731_led_t := 80;
  constant C6_2 : is31fl3731_led_t := 81;
  constant C6_3 : is31fl3731_led_t := 82;
  constant C6_4 : is31fl3731_led_t := 83;
  constant C6_5 : is31fl3731_led_t := 84;
  constant C6_6 : is31fl3731_led_t := 85;
  constant C6_7 : is31fl3731_led_t := 86;
  constant C6_8 : is31fl3731_led_t := 87;
  constant C6_9  : is31fl3731_led_t := 88;
  constant C6_10 : is31fl3731_led_t := 89;
  constant C6_11 : is31fl3731_led_t := 90;
  constant C6_12 : is31fl3731_led_t := 91;
  constant C6_13 : is31fl3731_led_t := 92;
  constant C6_14 : is31fl3731_led_t := 93;
  constant C6_15 : is31fl3731_led_t := 94;
  constant C6_16 : is31fl3731_led_t := 95;
  constant C7_1 : is31fl3731_led_t := 96;
  constant C7_2 : is31fl3731_led_t := 97;
  constant C7_3 : is31fl3731_led_t := 98;
  constant C7_4 : is31fl3731_led_t := 99;
  constant C7_5 : is31fl3731_led_t := 100;
  constant C7_6 : is31fl3731_led_t := 101;
  constant C7_7 : is31fl3731_led_t := 102;
  constant C7_8 : is31fl3731_led_t := 103;
  constant C7_9  : is31fl3731_led_t := 104;
  constant C7_10 : is31fl3731_led_t := 105;
  constant C7_11 : is31fl3731_led_t := 106;
  constant C7_12 : is31fl3731_led_t := 107;
  constant C7_13 : is31fl3731_led_t := 108;
  constant C7_14 : is31fl3731_led_t := 109;
  constant C7_15 : is31fl3731_led_t := 110;
  constant C7_16 : is31fl3731_led_t := 111;
  constant C8_1 : is31fl3731_led_t := 112;
  constant C8_2 : is31fl3731_led_t := 113;
  constant C8_3 : is31fl3731_led_t := 114;
  constant C8_4 : is31fl3731_led_t := 115;
  constant C8_5 : is31fl3731_led_t := 116;
  constant C8_6 : is31fl3731_led_t := 117;
  constant C8_7 : is31fl3731_led_t := 118;
  constant C8_8 : is31fl3731_led_t := 119;
  constant C8_9  : is31fl3731_led_t := 120;
  constant C8_10 : is31fl3731_led_t := 121;
  constant C8_11 : is31fl3731_led_t := 122;
  constant C8_12 : is31fl3731_led_t := 123;
  constant C8_13 : is31fl3731_led_t := 124;
  constant C8_14 : is31fl3731_led_t := 125;
  constant C8_15 : is31fl3731_led_t := 126;
  constant C8_16 : is31fl3731_led_t := 127;
  constant C9_1 : is31fl3731_led_t := 128;
  constant C9_2 : is31fl3731_led_t := 129;
  constant C9_3 : is31fl3731_led_t := 130;
  constant C9_4 : is31fl3731_led_t := 131;
  constant C9_5 : is31fl3731_led_t := 132;
  constant C9_6 : is31fl3731_led_t := 133;
  constant C9_7 : is31fl3731_led_t := 134;
  constant C9_8 : is31fl3731_led_t := 135;
  constant C9_9  : is31fl3731_led_t := 136;
  constant C9_10 : is31fl3731_led_t := 137;
  constant C9_11 : is31fl3731_led_t := 138;
  constant C9_12 : is31fl3731_led_t := 139;
  constant C9_13 : is31fl3731_led_t := 140;
  constant C9_14 : is31fl3731_led_t := 141;
  constant C9_15 : is31fl3731_led_t := 142;
  constant C9_16 : is31fl3731_led_t := 143;

  -- With CA and CB numbering anode and cathode connections, get index
  -- in LED arrays
  function ca(k, a: integer) return is31fl3731_led_t;
  function cb(k, a: integer) return is31fl3731_led_t;

  -- IS31FL3731 Led controller
  --
  -- Use routed_transactor_once for initialization of device
  component is31fl3731_driver is
    generic(
      i2c_addr_c    : unsigned(6 downto 0) := "1110100";
      led_order_c : is31fl3731_led_vector
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      enable_i : in std_ulogic := '1';

      -- Forces refresh
      force_i : in std_ulogic := '0';

      busy_o  : out std_ulogic;

      led_i : in byte_string(0 to led_order_c'length-1);

      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

  -- Spawn a byte string suitable for
  -- nsl_bnoc.framed_transactor.framed_transactor_once for
  -- proper initialization of device.
  function is31fl3731_init(saddr: unsigned;
                           used_leds: is31fl3731_led_vector) return byte_string;

end package is31fl3731;

package body is31fl3731 is

  function is31fl3731_frame_page_select(saddr: unsigned; frame: integer range 1 to 8) return byte_string
  is
  begin
      return i2c_write(saddr, to_byte(16#fd#) & to_byte(frame - 1));
  end function;

  function is31fl3731_function_page_select(saddr: unsigned) return byte_string
  is
  begin
      return i2c_write(saddr, to_byte(16#fd#) & to_byte(11));
  end function;

  function is31fl3731_init(saddr: unsigned;
                           used_leds: is31fl3731_led_vector) return byte_string
  is
    variable led_enable: unsigned(143 downto 0) := (others => '0');
    variable blink_enable: unsigned(143 downto 0) := (others => '0');
  begin
    for i in used_leds'range
    loop
      led_enable(used_leds(i)) := '1';
      blink_enable(used_leds(i)) := '1';
    end loop;

    return null_byte_string
      & is31fl3731_function_page_select(saddr)
      -- Enable
      & i2c_write(saddr, from_hex("0a01"))
      -- Stil picture
      & i2c_write(saddr, from_hex("0000000000"))
      -- No blink
      & i2c_write(saddr, from_hex("0520"))
      -- No breathe
      & i2c_write(saddr, from_hex("080000"))
      & is31fl3731_frame_page_select(saddr, 1)
      & i2c_write(saddr, to_byte(16#0#) & to_le(led_enable))
      & i2c_write(saddr, to_byte(16#12#) & to_le(blink_enable))
      ;
  end function;

  function ca(k, a: integer) return is31fl3731_led_t
  is
    variable index: integer := 0;
  begin
    assert 1 <= k and k <= 9
      report "Bad cathode mapping"
      severity failure;
    assert 1 <= a and a <= 9
      report "Bad anode mapping"
      severity failure;
    assert a /= k
      report "Bad anode/cathode mapping"
      severity failure;

    index := (k - 1) * 16 + a - 1;
    if k < a then
      index := index - 1;
    end if;
    
    return index;
  end function;
  
  function cb(k, a: integer) return is31fl3731_led_t
  is
  begin
    return 8 + ca(k, a);
  end function;
  
end package body is31fl3731;
