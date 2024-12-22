library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_logic, nsl_math;

package usb is

  use nsl_data.bytestream.byte;
  use nsl_data.bytestream.byte_string;
  
  -- Excerpt from USB spec (USB 2.0, 8.3.5):
  --
  -- "For CRC generation and checking, the shift registers in the
  -- generator and checker are seeded with an all-ones pattern. For
  -- each data bit sent or received, the high order bit of the current
  -- remainder is XORed with the data bit and then the remainder is
  -- shifted left one bit and the low-order bit set to zero. If the
  -- result of that XOR is one, then the remainder is XORed with the
  -- generator polynomial.
  --
  -- When the last bit of the checked field is sent, the CRC in the
  -- generator is inverted and sent to the checker MSb first. When the
  -- last bit of the CRC is received by the checker and no errors have
  -- occurred, the remainder will be equal to the polynomial
  -- residual."
  --
  -- Understanding USB spec, this means:
  --
  -- - Initialization is all ones, but result is inverted. If we want CRC
  --   function to be composable, we should have inversion before and after,
  --   and have all zeros as initialization.
  --
  -- - Token CRC Polynomial is x5 + x2 + 1.
  constant token_crc_params_c: nsl_data.crc.crc_params_t := nsl_data.crc.crc_params(
    init => "",
    poly => x"25",
    complement_input => false,
    complement_state => true,
    byte_bit_order   => nsl_data.crc.BIT_ORDER_ASCENDING,
    spill_order      => nsl_data.crc.EXP_ORDER_DESCENDING,
    byte_order       => nsl_data.bytestream.BYTE_ORDER_INCREASING
    );
  
  -- - Data CRC Polynomial is x16 + x15 + x2 + 1.
  constant data_crc_params_c: nsl_data.crc.crc_params_t := nsl_data.crc.crc_params(
    init => "",
    poly => x"18005",
    complement_input => false,
    complement_state => true,
    byte_bit_order   => nsl_data.crc.BIT_ORDER_ASCENDING,
    spill_order      => nsl_data.crc.EXP_ORDER_DESCENDING,
    byte_order       => nsl_data.bytestream.BYTE_ORDER_INCREASING
    );

  subtype device_address_t is unsigned(6 downto 0);
  subtype endpoint_no_t is unsigned(3 downto 0);
  subtype endpoint_idx_t is integer range 0 to 15;
  type pid_t is array(integer range 3 downto 0) of std_ulogic;
  type setup_request_t is array(integer range 7 downto 0) of std_ulogic;
  type descriptor_type_t is array(integer range 7 downto 0) of std_ulogic;
  type feature_selector_t is array(integer range 7 downto 0) of std_ulogic;
  subtype frame_no_t is unsigned(10 downto 0);

  function feature_selector_from_value(value : unsigned(15 downto 0)) return feature_selector_t;
  function feature_selector_to_value(feature: feature_selector_t) return unsigned;
  function descriptor_type_from_value(value : unsigned(15 downto 0)) return descriptor_type_t;
  function descriptor_index_from_value(value : unsigned(15 downto 0)) return unsigned;
  
  -- Compute the resulting 2-byte string for a given (address,
  -- endpoint) pair. This adds the token CRC.
  function token_data(addr : device_address_t;
                      endp : endpoint_no_t)
    return byte_string;

  function sof_data(frame : frame_no_t)
    return byte_string;

  constant PID_OUT      : pid_t := "0001";
  constant PID_IN       : pid_t := "1001";
  constant PID_SOF      : pid_t := "0101";
  constant PID_SETUP    : pid_t := "1101";
  constant PID_DATA0    : pid_t := "0011";
  constant PID_DATA1    : pid_t := "1011";
  constant PID_DATA2    : pid_t := "0111";
  constant PID_MDATA    : pid_t := "1111";
  constant PID_ACK      : pid_t := "0010";
  constant PID_NAK      : pid_t := "1010";
  constant PID_STALL    : pid_t := "1110";
  constant PID_NYET     : pid_t := "0110";
  constant PID_PRE      : pid_t := "1100";
  constant PID_ERR      : pid_t := "1100";
  constant PID_SPLIT    : pid_t := "1000";
  constant PID_PING     : pid_t := "0100";
  constant PID_RESERVED : pid_t := "0000";
  
  -- Create a PID byte from PID.
  function pid_byte(pid : pid_t) return byte;

  -- Asserts PID byte is repeated with inversion as it should be.
  function pid_byte_is_correct(pid : byte) return boolean;

  -- Extract PID from a PID byte
  function pid_get(pid : byte) return pid_t;

  type usb_symbol_t is (
    USB_SYMBOL_SE0,
    USB_SYMBOL_J,
    USB_SYMBOL_K,
    USB_SYMBOL_SE1
    );
  function to_usb_symbol(ls : std_ulogic_vector(1 downto 0)) return usb_symbol_t;
  function to_logic(ls : usb_symbol_t) return std_ulogic_vector;

  type usb_symbol_vector is array(natural range <>) of usb_symbol_t;

  type usb_line_state_t is (
    USB_LINE_STATE_RESET,
    USB_LINE_STATE_RUNNING,
    USB_LINE_STATE_SUSPEND
    );

  type direction_t is (
    HOST_TO_DEVICE,
    DEVICE_TO_HOST
    );

  type setup_type_t is (
    SETUP_TYPE_STANDARD,
    SETUP_TYPE_CLASS,
    SETUP_TYPE_VENDOR,
    SETUP_TYPE_RESERVED
    );

  type setup_recipient_t is (
    SETUP_RECIPIENT_DEVICE,
    SETUP_RECIPIENT_INTERFACE,
    SETUP_RECIPIENT_ENDPOINT,
    SETUP_RECIPIENT_OTHER,
    SETUP_RECIPIENT_RESERVED
    );

  type setup_t is
  record
    direction : direction_t;
    rtype : setup_type_t;
    recipient : setup_recipient_t;
    request : setup_request_t;
    value, index, length : unsigned(15 downto 0);
  end record;
  
  function setup_unpack(data: nsl_data.bytestream.byte_string)
    return setup_t;

  function setup_pack(data : setup_t)
    return nsl_data.bytestream.byte_string;

  function endpoint_index(direction : direction_t;
                          ep_no : integer) return unsigned;

  -- Setup packet offsets
  constant SETUP_PACKET_OFF_REQUESTTYPE : integer := 0;
  constant SETUP_PACKET_OFF_REQUEST     : integer := 1;
  constant SETUP_PACKET_OFF_VALUE_LOW   : integer := 2;
  constant SETUP_PACKET_OFF_VALUE_HIGH  : integer := 3;
  constant SETUP_PACKET_OFF_INDEX_LOW   : integer := 4;
  constant SETUP_PACKET_OFF_INDEX_HIGH  : integer := 5;
  constant SETUP_PACKET_OFF_LENGTH_LOW  : integer := 6;
  constant SETUP_PACKET_OFF_LENGTH_HIGH : integer := 7;
  
  -- Table 9-4. Standard Request Codes
  constant REQUEST_GET_STATUS        : setup_request_t := "00000000";
  constant REQUEST_CLEAR_FEATURE     : setup_request_t := "00000001";
  constant REQUEST_SET_FEATURE       : setup_request_t := "00000011";
  constant REQUEST_SET_ADDRESS       : setup_request_t := "00000101";
  constant REQUEST_GET_DESCRIPTOR    : setup_request_t := "00000110";
  constant REQUEST_SET_DESCRIPTOR    : setup_request_t := "00000111";
  constant REQUEST_GET_CONFIGURATION : setup_request_t := "00001000";
  constant REQUEST_SET_CONFIGURATION : setup_request_t := "00001001";
  constant REQUEST_GET_INTERFACE     : setup_request_t := "00001010";
  constant REQUEST_SET_INTERFACE     : setup_request_t := "00001011";

  -- Table 9-5. Descriptor Types
  constant DESCRIPTOR_TYPE_DEVICE                    : descriptor_type_t := "00000001";
  constant DESCRIPTOR_TYPE_CONFIGURATION             : descriptor_type_t := "00000010";
  constant DESCRIPTOR_TYPE_STRING                    : descriptor_type_t := "00000011";
  constant DESCRIPTOR_TYPE_INTERFACE                 : descriptor_type_t := "00000100";
  constant DESCRIPTOR_TYPE_ENDPOINT                  : descriptor_type_t := "00000101";
  constant DESCRIPTOR_TYPE_DEVICE_QUALIFIER          : descriptor_type_t := "00000110";
  constant DESCRIPTOR_TYPE_OTHER_SPEED_CONFIGURATION : descriptor_type_t := "00000111";
  constant DESCRIPTOR_TYPE_INTERFACE_POWER           : descriptor_type_t := "00001000";

  -- Table 9-6. Standard Feature Selectors
  constant FEATURE_SELECTOR_DEVICE_REMOTE_WAKEUP : feature_selector_t := "00000001";
  constant FEATURE_SELECTOR_ENDPOINT_HALT        : feature_selector_t := "00000000";
  constant FEATURE_SELECTOR_TEST_MODE            : feature_selector_t := "00000010";

  -- 5.8.3: The USB defines the allowable maximum bulk data payload
  -- sizes to be only 8, 16, 32, or 64 bytes for full-speed endpoints
  -- and 512 bytes for high-speed endpoints.
  constant BULK_MPS_FS_MIN: integer := 8;
  constant BULK_MPS_FS_MAX: integer := 64;
  constant BULK_MPS_HS: integer := 512;

  function bit_count_cycles_fs(bit_count : integer; ref_clock_mhz : integer := 60) return integer;
  function bit_count_cycles_hs(bit_count : integer; ref_clock_mhz : integer := 60) return integer;

end package;

package body usb is

  use nsl_data.crc.all;
  use nsl_data.endian.all;
  use nsl_logic.bool.all;
  
  function token_data(addr : device_address_t;
                      endp : endpoint_no_t)
    return byte_string
  is
    variable ret : unsigned(10 downto 0);
    variable tmp : std_ulogic_vector(10 downto 0);
    variable crc : std_ulogic_vector(4 downto 0);
  begin
    ret(6 downto 0) := addr;
    ret(10 downto 7) := endp;
    tmp := std_ulogic_vector(ret);
    crc := crc_spill_vector(token_crc_params_c,
                            crc_update(token_crc_params_c, crc_init(token_crc_params_c),
                                       tmp));

    return to_le(unsigned(crc) & ret);
  end function;

  function sof_data(frame : frame_no_t)
    return byte_string
  is
    variable tmp : std_ulogic_vector(10 downto 0);
    variable crc : std_ulogic_vector(4 downto 0);
  begin
    tmp := std_ulogic_vector(frame);
    crc := crc_spill_vector(token_crc_params_c,
                            crc_update(token_crc_params_c, crc_init(token_crc_params_c),
                                       std_ulogic_vector(tmp)));

    return to_le(unsigned(crc) & frame);
  end function;

  function pid_byte(pid : pid_t)
    return byte
  is
    variable ret : byte;
  begin
    ret(3 downto 0) := std_ulogic_vector(pid);
    ret(7 downto 4) := not std_ulogic_vector(pid);
    return ret;
  end function;

  function pid_get(pid : byte)
    return pid_t
  is
  begin
    return pid_t(pid(3 downto 0));
  end function;

  function pid_byte_is_correct(pid : byte)
    return boolean
  is
  begin
    return pid(3 downto 0) = not pid(7 downto 4);
  end function;

  function setup_unpack(data: nsl_data.bytestream.byte_string)
    return setup_t
  is
    alias raw : nsl_data.bytestream.byte_string(SETUP_PACKET_OFF_REQUESTTYPE
                                                to SETUP_PACKET_OFF_LENGTH_HIGH)
      is data;
    variable ret: setup_t;
  begin
    case raw(SETUP_PACKET_OFF_REQUESTTYPE)(7) is
      when '0' => ret.direction := HOST_TO_DEVICE;
      when others => ret.direction := DEVICE_TO_HOST;
    end case;
    case raw(SETUP_PACKET_OFF_REQUESTTYPE)(6 downto 5) is
      when "00" => ret.rtype := SETUP_TYPE_STANDARD;
      when "01" => ret.rtype := SETUP_TYPE_CLASS;
      when "10" => ret.rtype := SETUP_TYPE_VENDOR;
      when others => ret.rtype := SETUP_TYPE_RESERVED;
    end case;
    case raw(SETUP_PACKET_OFF_REQUESTTYPE)(4 downto 0) is
      when "00000" => ret.recipient := SETUP_RECIPIENT_DEVICE;
      when "00001" => ret.recipient := SETUP_RECIPIENT_INTERFACE;
      when "00010" => ret.recipient := SETUP_RECIPIENT_ENDPOINT;
      when "00011" => ret.recipient := SETUP_RECIPIENT_OTHER;
      when others => ret.recipient := SETUP_RECIPIENT_RESERVED;
    end case;
    ret.request := setup_request_t(raw(SETUP_PACKET_OFF_REQUEST));
    ret.value := from_le(raw(SETUP_PACKET_OFF_VALUE_LOW to SETUP_PACKET_OFF_VALUE_HIGH));
    ret.index := from_le(raw(SETUP_PACKET_OFF_INDEX_LOW to SETUP_PACKET_OFF_INDEX_HIGH));
    ret.length := from_le(raw(SETUP_PACKET_OFF_LENGTH_LOW to SETUP_PACKET_OFF_LENGTH_HIGH));
    return ret;
  end function;

  function setup_pack(data : setup_t)
    return nsl_data.bytestream.byte_string
  is
    variable ret : nsl_data.bytestream.byte_string(0 to 7) := (others => x"00");
  begin
    ret(0)(7) := to_logic(data.direction = DEVICE_TO_HOST);
    case data.rtype is
      when SETUP_TYPE_STANDARD => ret(0)(6 downto 5) := "00";
      when SETUP_TYPE_CLASS => ret(0)(6 downto 5) := "01";
      when SETUP_TYPE_VENDOR => ret(0)(6 downto 5) := "10";
      when SETUP_TYPE_RESERVED => ret(0)(6 downto 5) := "11";
    end case;
    case data.recipient is
      when SETUP_RECIPIENT_DEVICE => ret(0)(4 downto 0) := "00000";
      when SETUP_RECIPIENT_INTERFACE => ret(0)(4 downto 0) := "00001";
      when SETUP_RECIPIENT_ENDPOINT => ret(0)(4 downto 0) := "00010";
      when SETUP_RECIPIENT_OTHER => ret(0)(4 downto 0) := "00011";
      when others => ret(0)(4 downto 0) := "11111";
    end case;
    ret(SETUP_PACKET_OFF_REQUEST) := byte(data.request);
    ret(SETUP_PACKET_OFF_VALUE_LOW to SETUP_PACKET_OFF_VALUE_HIGH) := to_le(data.value);
    ret(SETUP_PACKET_OFF_INDEX_LOW to SETUP_PACKET_OFF_INDEX_HIGH) := to_le(data.index);
    ret(SETUP_PACKET_OFF_LENGTH_LOW to SETUP_PACKET_OFF_LENGTH_HIGH) := to_le(data.length);
    return ret;
  end function;
  
  function bit_count_cycles_fs(bit_count : integer; ref_clock_mhz : integer := 60) return integer
  is
  begin
    return bit_count * ref_clock_mhz / 12;
  end function;

  function bit_count_cycles_hs(bit_count : integer; ref_clock_mhz : integer := 60) return integer
  is
  begin
    return bit_count * ref_clock_mhz / 480;
  end function;

  function to_usb_symbol(ls : std_ulogic_vector(1 downto 0)) return usb_symbol_t
  is
  begin
    case ls is
      when "00" => return USB_SYMBOL_SE0;
      when "01" => return USB_SYMBOL_J;
      when "10" => return USB_SYMBOL_K;
      when others => return USB_SYMBOL_SE1;
    end case;
  end function;

  function to_logic(ls : usb_symbol_t) return std_ulogic_vector
  is
  begin
    case ls is
      when USB_SYMBOL_SE0 => return "00";
      when USB_SYMBOL_J => return "01";
      when USB_SYMBOL_K => return "10";
      when others => return "11";
    end case;
  end function;
  
  function feature_selector_from_value(value : unsigned(15 downto 0)) return feature_selector_t
  is
  begin
    return feature_selector_t(resize(value, feature_selector_t'length));
  end function;

  function feature_selector_to_value(feature: feature_selector_t) return unsigned
  is
  begin
    return resize(unsigned(feature), 16);
  end function;

  function descriptor_type_from_value(value : unsigned(15 downto 0)) return descriptor_type_t
  is
  begin
    return descriptor_type_t(resize(value(15 downto 8), descriptor_type_t'length));
  end function;

  function descriptor_index_from_value(value : unsigned(15 downto 0)) return unsigned
  is
  begin
    return value(8 downto 0);
  end function;

  function endpoint_index(direction : direction_t;
                          ep_no : integer) return unsigned
  is
    variable ret : unsigned(15 downto 0);
  begin
    ret := (others => '0');
    if direction = DEVICE_TO_HOST then
      ret(7) := '1';
    end if;
    ret(3 downto 0) := to_unsigned(ep_no, 4);

    return ret;
  end function;

end package body;
