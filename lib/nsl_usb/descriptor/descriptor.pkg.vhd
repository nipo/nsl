library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_math, nsl_usb;
use nsl_data.bytestream.all;
use nsl_usb.usb.all;

package descriptor is

  constant TYPE_DEVICE                : integer := 1;
  constant TYPE_CONFIGURATION         : integer := 2;
  constant TYPE_STRING                : integer := 3;
  constant TYPE_INTERFACE             : integer := 4;
  constant TYPE_ENDPOINT              : integer := 5;
  constant TYPE_DEVICE_QUALIFIER      : integer := 6;
  constant TYPE_OTHER_SPEED_CONFIG    : integer := 7; 
  constant TYPE_INTERFACE_POWER       : integer := 8;
  constant TYPE_OTG                   : integer := 9;
  constant TYPE_DEBUG                 : integer := 10;
  constant TYPE_INTERFACE_ASSOCIATION : integer := 11;
  constant TYPE_CDC_CS_INTERFACE      : integer := 16#24#;
  constant TYPE_CDC_CS_ENDPOINT       : integer := 16#25#;

  constant SUBTYPE_CDC_FUNC_HEADER          : integer := 16#00#;
  constant SUBTYPE_CDC_FUNC_CALL_MGMT       : integer := 16#01#;
  constant SUBTYPE_CDC_FUNC_ACM             : integer := 16#02#;
  constant SUBTYPE_CDC_FUNC_DLM             : integer := 16#03#;
  constant SUBTYPE_CDC_FUNC_TEL_RING        : integer := 16#04#;
  constant SUBTYPE_CDC_FUNC_TEL_CALL        : integer := 16#05#;
  constant SUBTYPE_CDC_FUNC_UNION           : integer := 16#06#;
  constant SUBTYPE_CDC_FUNC_COUNTRY_SEL     : integer := 16#07#;
  constant SUBTYPE_CDC_FUNC_TEL_OP_MODE     : integer := 16#08#;
  constant SUBTYPE_CDC_FUNC_USB_TERM        : integer := 16#09#;
  constant SUBTYPE_CDC_FUNC_NETWORK         : integer := 16#0a#;
  constant SUBTYPE_CDC_FUNC_PROTOCOL_UNIT   : integer := 16#0b#;
  constant SUBTYPE_CDC_FUNC_EXTENSION_UNIT  : integer := 16#0c#;
  constant SUBTYPE_CDC_FUNC_CHANNEL_MGMT    : integer := 16#0d#;
  constant SUBTYPE_CDC_FUNC_CAPI            : integer := 16#0e#;
  constant SUBTYPE_CDC_FUNC_ETHERNET        : integer := 16#0f#;
  constant SUBTYPE_CDC_FUNC_ATM             : integer := 16#10#;
  
  function device(
    hs_support : boolean;
    class, subclass, protocol : natural := 0;
    mps : natural;
    vendor_id, product_id, device_version : unsigned(15 downto 0);
    manufacturer_str_index, product_str_index, serial_str_index : natural := 0;
    config_count : natural := 1)
    return byte_string;

  function endpoint(
    direction : direction_t;
    number : natural;
    ttype : unsigned(1 downto 0);
    mps : natural;
    interval : natural := 0)
    return byte_string;

  function config(
    config_no : natural;
    str_index : natural := 0;
    self_powered, remote_wakeup : boolean := false;
    max_power : natural;
    interface0 : byte_string;
    interface1, interface2, interface3, other_desc : byte_string := null_byte_string)
    return byte_string;

  function device_qualifier(
    usb_version : natural;
    class, subclass, protocol : natural := 0;
    mps0 : natural;
    config_count : natural := 1)
    return byte_string;

  function interface(
    interface_number : natural;
    alt_setting : natural := 0;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0;
    endpoint0, endpoint1, endpoint2, endpoint3, functional_desc : byte_string := null_byte_string)
    return byte_string;

  function interface_association(
    first_interface, interface_count : natural;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0)
    return byte_string;

  function cdc_functional_header(
    cdc_version : natural := 16#0120#)
    return byte_string;

  function cdc_functional_acm(
    capabilities : natural := 0)
    return byte_string;

  function cdc_functional_union(
    control, sub0 : natural)
    return byte_string;

  function cdc_functional_call_management(
    capabilities, data_interface : natural)
    return byte_string;

  function language(
    langid : natural := 16#409#)
    return byte_string;

  function string_from_ascii(
    str : string)
    return byte_string;

  function string_descriptor_length(s: in string)
    return natural;

end package;

package body descriptor is

  use nsl_data.endian.all;
  use nsl_logic.bool.all;

  function bv(n: unsigned)
    return byte_string
  is
    variable ret : byte_string(1 to 1);
  begin
    assert n'length <= 8 severity failure;
    ret(1) := byte(resize(n, 8));
    return ret;
  end function;

  function bv(n: integer range 0 to 255)
    return byte_string
  is
    variable ret : byte_string(1 to 1);
  begin
    ret(1) := byte(to_unsigned(n, 8));
    return ret;
  end function;

  function wv(n: unsigned)
    return byte_string
  is
  begin
    assert n'length <= 16 severity failure;
    return to_le(resize(n, 16));
  end function;

  function wv(n: integer range 0 to 65535)
    return byte_string
  is
  begin
    return wv(to_unsigned(n, 16));
  end function;

  function sized(
    dtype : integer range 0 to 255;
    desc : byte_string)
    return byte_string
  is
  begin
    return bv(integer(desc'length+2)) & bv(dtype) & desc;
  end function;
  
  function device(
    hs_support : boolean;
    class, subclass, protocol : natural := 0;
    mps : natural;
    vendor_id, product_id, device_version : unsigned(15 downto 0);
    manufacturer_str_index, product_str_index, serial_str_index : natural := 0;
    config_count : natural := 1)
    return byte_string
  is
  begin
    return sized(
      TYPE_DEVICE,
      wv(if_else(hs_support, 16#0200#, 16#0110#))
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(mps)
      & wv(vendor_id)
      & wv(product_id)
      & wv(device_version)
      & bv(manufacturer_str_index)
      & bv(product_str_index)
      & bv(serial_str_index)
      & bv(config_count)
      );
  end device;

  function endpoint(
    direction : direction_t;
    number : natural;
    ttype : unsigned(1 downto 0);
    mps : natural;
    interval : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_ENDPOINT,
      bv(if_else(direction = DEVICE_TO_HOST, 16#80#, 0) + number)
      & bv(ttype)
      & wv(mps)
      & bv(interval)
      );
  end endpoint;

  function config(
    config_no : natural;
    str_index : natural := 0;
    self_powered, remote_wakeup : boolean := false;
    max_power : natural;
    interface0 : byte_string;
    interface1, interface2, interface3, other_desc : byte_string := null_byte_string)
    return byte_string
  is
    variable attrs : byte;
    variable interface_count : natural := 1;
  begin
    if interface1'length /= 0 then
      interface_count := interface_count + 1;
    end if;
    if interface2'length /= 0 then
      interface_count := interface_count + 1;
    end if;
    if interface3'length /= 0 then
      interface_count := interface_count + 1;
    end if;
    
    attrs := x"80";
    attrs(6) := to_logic(self_powered);
    attrs(5) := to_logic(remote_wakeup);

    return sized(
      TYPE_CONFIGURATION,
      wv(interface0'length + interface1'length
         + interface2'length + interface3'length
         + other_desc'length + 9)
      & bv(interface_count)
      & bv(config_no)
      & bv(str_index)
      & attrs
      & bv(nsl_math.arith.min(max_power, 500) / 2)
      ) & other_desc & interface0 & interface1 & interface2 & interface3;
  end config;

  function interface(
    interface_number : natural;
    alt_setting : natural := 0;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0;
    endpoint0, endpoint1, endpoint2, endpoint3, functional_desc : byte_string := null_byte_string)
    return byte_string
  is
    variable endpoint_count : natural := 0;
  begin
    if endpoint0'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;
    if endpoint1'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;
    if endpoint2'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;
    if endpoint3'length /= 0 then
      endpoint_count := endpoint_count + 1;
    end if;

    return sized(
      TYPE_INTERFACE,
      bv(interface_number)
      & bv(alt_setting)
      & bv(endpoint_count)
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(str_index)
      ) & functional_desc & endpoint0 & endpoint1 & endpoint2 & endpoint3;
  end interface;

  function cdc_functional_header(
    cdc_version : natural := 16#0120#)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_HEADER)
      & wv(cdc_version));
  end function cdc_functional_header;

  function cdc_functional_acm(
    capabilities : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_ACM)
      & bv(capabilities));
  end function cdc_functional_acm;

  function cdc_functional_union(
    control, sub0 : natural)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_UNION)
      & bv(control)
      & bv(sub0));
  end function cdc_functional_union;

  function cdc_functional_call_management(
    capabilities, data_interface : natural)
    return byte_string
  is
  begin
    return sized(
      TYPE_CDC_CS_INTERFACE,
      bv(SUBTYPE_CDC_FUNC_CALL_MGMT)
      & bv(capabilities)
      & bv(data_interface));
  end function cdc_functional_call_management;

  function language(
    langid : natural := 16#409#)
    return byte_string
  is
  begin
    return sized(
      TYPE_STRING,
      wv(langid));
  end function language;

  function string_from_ascii(
    str : string)
    return byte_string
  is
    alias sstr: string(1 to str'length) is str;
    variable utf16: byte_string(1 to str'length*2);
  begin
    if sstr'length = 0 then
      return null_byte_string;
    end if;

    for i in sstr'range loop
      utf16(i*2-1 to i*2) := wv(character'pos(sstr(i)));
    end loop;
    return sized(TYPE_STRING, utf16);
  end function string_from_ascii;

  function string_descriptor_length(s: in string)
    return natural is
  begin
    assert s'length <= 126;

    if s'length = 0 then
      return 0;
    else
      return 2 + 2 * s'length;
    end if;
  end function;

  function device_qualifier(
    usb_version : natural;
    class, subclass, protocol : natural := 0;
    mps0 : natural;
    config_count : natural := 1)
    return byte_string
  is
  begin
    return sized(
      TYPE_DEVICE_QUALIFIER,
      wv(usb_version)
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(mps0)
      & bv(config_count)
      & bv(0)
      );
  end function device_qualifier;

  function interface_association(
    first_interface, interface_count : natural;
    class : natural;
    subclass, protocol : natural := 0;
    str_index : natural := 0)
    return byte_string
  is
  begin
    return sized(
      TYPE_INTERFACE_ASSOCIATION,
      bv(first_interface)
      & bv(interface_count)
      & bv(class)
      & bv(subclass)
      & bv(protocol)
      & bv(str_index));
  end function interface_association;

end package body;
