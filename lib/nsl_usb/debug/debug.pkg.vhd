library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_usb, nsl_data;
use nsl_usb.usb.all;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.endian.all;

package debug is

  function packet_to_string(data : byte_string)
    return string;
  function to_string(rtype : setup_type_t) return string;
  function to_string(recipient : setup_recipient_t) return string;
  function to_string(pid : pid_t) return string;
  function to_string(request : setup_request_t) return string;
  function to_string(setup : setup_t) return string;

end debug;

package body debug is

  function sof_to_string(data : byte_string)
    return string
  is
    alias blob : byte_string(0 to data'length-1) is data;
    variable token : unsigned(15 downto 0);
  begin
    if blob'length < 3 then
      return "Invalid short SOF: " & to_string(blob);
    elsif blob'length > 3 then
      return "Invalid long SOF: " & to_string(blob);
    end if;

    token := from_le(blob(1 to 2));

    if token_crc_update(token_crc_init, blob(1 to 2)) = token_crc_check then
      return "SOF #" & to_string(token(10 downto 0));
    else
      return "SOF #" & to_string(token(10 downto 0)) & " [BAD CRC]";
    end if;
  end function;

  function token_to_string(data : byte_string)
    return string
  is
    alias blob : byte_string(0 to data'length-1) is data;
    variable pid : pid_t;
    variable token : unsigned(15 downto 0);
  begin
    if blob'length < 3 then
      return "Invalid short token: " & to_string(blob);
    elsif blob'length > 3 then
      return "Invalid long token: " & to_string(blob);
    end if;

    pid := pid_get(blob(0));
    token := from_le(blob(1 to 2));

    if token_crc_update(token_crc_init, blob(1 to 2)) = token_crc_check then
      return to_string(pid)
        & " Dev@" & to_string(token(6 downto 0))
        & ", EP#" & to_string(to_integer(token(10 downto 7)));
    else
      return to_string(pid)
        & " Dev@" & to_string(token(6 downto 0))
        & ", EP#" & to_string(to_integer(token(10 downto 7)))
        & " [BAD CRC]";
    end if;
  end function;

  function data_to_string(data : byte_string)
    return string
  is
    alias blob : byte_string(0 to data'length-1) is data;
    variable pid : pid_t;
    variable crc_ok : boolean;
  begin
    if blob'length < 3 then
      return "Invalid short DATA packet: " & to_string(blob);
    end if;

    pid := pid_get(blob(0));
    crc_ok := data_crc_update(data_crc_init, blob(1 to blob'right)) = data_crc_check;

    if crc_ok then
      return to_string(pid)
        & ", " & to_string(blob'length - 3) & " bytes"
        & ": " & to_string(blob(1 to blob'right-2))
        & ", CRC = " & to_string(from_le(blob(blob'right-1 to blob'right)))
        & " [OK]";
    else
      return to_string(pid)
        & ", " & to_string(blob'length - 3) & " bytes"
        & ": " & to_string(blob(1 to blob'right-2))
        & ", CRC = " & to_string(from_le(blob(blob'right-1 to blob'right)))
        & " [BAD]";
    end if;
  end function;
  
  function packet_to_string(data : byte_string)
    return string
  is
    alias blob : byte_string(0 to data'length-1) is data;
  begin
    if not pid_byte_is_correct(blob(0)) then
      return "[Invalid PID :" & to_string(unsigned(blob(0))) & "], added data: " & to_string(blob(1 to blob'right));
    end if;

    case pid_get(blob(0)) is
      when PID_ACK | PID_NAK | PID_STALL | PID_NYET =>
        if blob'length /= 1 then
          return to_string(pid_get(blob(0)))
            & " + invalid trailer: "
            & to_string(blob(1 to blob'right));
        end if;
        return to_string(pid_get(blob(0)));

      when PID_OUT | PID_IN | PID_PING | PID_SETUP =>
        return token_to_string(blob);

      when PID_SOF =>
        return sof_to_string(blob);

      when PID_DATA0 | PID_DATA1 | PID_DATA2 | PID_MDATA =>
        return data_to_string(blob);

      when others =>
        return "[Unimplemented packet " & to_string(blob) & "]";
    end case;
  end function;
  
  function to_string(rtype : setup_type_t) return string
  is
  begin
    case rtype is
      when SETUP_TYPE_STANDARD => return "Standard";
      when SETUP_TYPE_CLASS => return "Class";
      when SETUP_TYPE_VENDOR => return "Vendor";
      when SETUP_TYPE_RESERVED => return "Reserved";
    end case;
  end function;
  
  function to_string(recipient : setup_recipient_t) return string
  is
  begin
    case recipient is
      when SETUP_RECIPIENT_DEVICE => return "Device";
      when SETUP_RECIPIENT_INTERFACE => return "Interface";
      when SETUP_RECIPIENT_ENDPOINT => return "Endpoint";
      when others => return "Other";
    end case;
  end function;
  
  function to_string(request : setup_request_t) return string
  is
  begin
    case request is
      when REQUEST_GET_STATUS => return "Get Status";
      when REQUEST_CLEAR_FEATURE => return "Clear Feature";
      when REQUEST_SET_FEATURE => return "Set Feature";
      when REQUEST_SET_ADDRESS => return "Set Address";
      when REQUEST_GET_DESCRIPTOR => return "Get Descriptor";
      when REQUEST_SET_DESCRIPTOR => return "Set Descriptor";
      when REQUEST_GET_CONFIGURATION => return "Get Configuration";
      when REQUEST_SET_CONFIGURATION => return "Set Configuration";
      when REQUEST_GET_INTERFACE => return "Get Interface";
      when REQUEST_SET_INTERFACE => return "Set Interface";
      when others => return "Other request [" & to_string(unsigned(request)) & "]";
    end case;
  end function;
  
  function to_string(pid : pid_t) return string
  is
  begin
    case pid is
      when PID_OUT => return "Out";
      when PID_IN => return "In";
      when PID_SOF => return "Sof";
      when PID_SETUP => return "Setup";
      when PID_DATA0 => return "Data0";
      when PID_DATA1 => return "Data1";
      when PID_DATA2 => return "Data2";
      when PID_MDATA => return "Mdata";
      when PID_ACK => return "Ack";
      when PID_NAK => return "Nak";
      when PID_STALL => return "Stall";
      when PID_NYET => return "Nyet";
      when PID_PRE => return "Pre/Err";
      when PID_SPLIT => return "Split";
      when PID_PING => return "Ping";
      when PID_RESERVED => return "Reserved";
      when others => return nsl_data.text.to_string(unsigned(pid));
    end case;
  end function;

  function to_string(setup : setup_t) return string
  is
  begin
    if setup.direction = DEVICE_TO_HOST then
      return "Control Read"
        & ", type=" & to_string(setup.rtype)
        & ", recipient=" & to_string(setup.recipient)
        & ", request=" & to_string(setup.request)
        & ", value=" & to_string(setup.value)
        & ", index=" & to_string(setup.index)
        & ", max length=" & to_string(setup.length);
    elsif setup.length /= 0 then
      return "Control Write"
        & ", type=" & to_string(setup.rtype)
        & ", recipient=" & to_string(setup.recipient)
        & ", request=" & to_string(setup.request)
        & ", value=" & to_string(setup.value)
        & ", index=" & to_string(setup.index)
        & ", length=" & to_string(setup.length);
    else
      return "Control (no data)"
        & ", type=" & to_string(setup.rtype)
        & ", recipient=" & to_string(setup.recipient)
        & ", request=" & to_string(setup.request)
        & ", value=" & to_string(setup.value)
        & ", index=" & to_string(setup.index);
    end if;
  end function;

end debug;
