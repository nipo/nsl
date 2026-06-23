library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_jtag, nsl_io, nsl_data, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;

package transactor is
  
  constant JTAG_SHIFT_BYTE      : nsl_bnoc.framed.framed_data_t := "0-------"; -- byte count
  constant JTAG_SHIFT_BYTE_W    : nsl_bnoc.framed.framed_data_t := "-1------";
  constant JTAG_SHIFT_BYTE_R    : nsl_bnoc.framed.framed_data_t := "--1-----";
  constant JTAG_SHIFT_BIT       : nsl_bnoc.framed.framed_data_t := "111-----"; -- bit count
  constant JTAG_SHIFT_BIT_W     : nsl_bnoc.framed.framed_data_t := "---1----";
  constant JTAG_SHIFT_BIT_R     : nsl_bnoc.framed.framed_data_t := "----1---";
  constant JTAG_CMD_DR_CAPTURE  : nsl_bnoc.framed.framed_data_t := "10000000";
  constant JTAG_CMD_IR_CAPTURE  : nsl_bnoc.framed.framed_data_t := "10000001";
  constant JTAG_CMD_SWD_TO_JTAG : nsl_bnoc.framed.framed_data_t := "10000010";
  constant JTAG_CMD_DIVISOR     : nsl_bnoc.framed.framed_data_t := "10000011"; -- Next byte is divisor
  constant JTAG_CMD_SYS_RESET   : nsl_bnoc.framed.framed_data_t := "1000010-"; -- Set system reset (active high)
  constant JTAG_CMD_RESET_CYCLE : nsl_bnoc.framed.framed_data_t := "10011---"; -- cycle count
  constant JTAG_CMD_RTI_CYCLE   : nsl_bnoc.framed.framed_data_t := "10010---"; -- cycle count
  constant JTAG_CMD_RESET       : nsl_bnoc.framed.framed_data_t := "1011----"; -- in packet of 8 cycles
  constant JTAG_CMD_RTI         : nsl_bnoc.framed.framed_data_t := "1010----"; -- in packet of 8 cycles

  -- Send bytes, read TDO or not
  function cmd_shift_bytes(data: byte_string; read_tdo : boolean := true) return byte_string;
  -- Send padding, read TDO
  function cmd_shift_bytes(byte_count: integer range 1 to 32) return byte_string;
  -- Receive parser
  procedure rsp_shift_bytes(rsp_buffer: inout byte_stream; received: out byte_string);
  procedure rsp_shift_bytes(rsp_buffer: inout byte_stream);

  -- Send bits, read TDO or not
  function cmd_shift_bits(data: std_ulogic_vector; read_tdo : boolean := true) return byte_string;
  -- Send padding, read TDO
  function cmd_shift_bits(bit_count: integer range 1 to 8) return byte_string;
  -- Receive parser
  procedure rsp_shift_bits(rsp_buffer: inout byte_stream; received: out std_ulogic_vector);
  procedure rsp_shift_bits(rsp_buffer: inout byte_stream);

  -- Generate multiple shift commands
  function cmd_shift(data: std_ulogic_vector; read_tdo : boolean := true) return byte_string;
  -- Receive parser for read_tdo true
  procedure rsp_shift(rsp_buffer: inout byte_stream; data: out std_ulogic_vector);
  -- Receive parser for read_tdo false
  procedure rsp_shift(rsp_buffer: inout byte_stream; data_len: in integer);

  -- Capture DR
  function cmd_capture_dr return byte_string;
  -- Capture IR
  function cmd_capture_ir return byte_string;
  -- SWD to JTAG fixed sequence
  function cmd_swd_to_jtag return byte_string;
  -- Set divisor
  function cmd_divisor(divisor: integer range 1 to 256) return byte_string;
  -- Set system reset
  function cmd_system_reset(asserted: boolean) return byte_string;
  -- Run for count of cycles x8
  function cmd_run_x8(cycles_x8: integer range 1 to 16) return byte_string;
  -- Reset for count of cycles x8
  function cmd_reset_x8(cycles_x8: integer range 1 to 16) return byte_string;
  -- Run for count of cycles
  function cmd_run(cycles: integer range 1 to 8) return byte_string;
  -- Reset for count of cycles
  function cmd_reset(cycles: integer range 1 to 8) return byte_string;
  -- Generic receiver function for all other functions
  procedure rsp(rsp_buffer: inout byte_stream);
  
  component framed_ate
    port (
      reset_n_i   : in  std_ulogic;
      clock_i      : in  std_ulogic;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;
      rsp_o   : out nsl_bnoc.framed.framed_req;
      rsp_i   : in nsl_bnoc.framed.framed_ack;

      jtag_o : out nsl_jtag.jtag.jtag_ate_o;
      jtag_i : in nsl_jtag.jtag.jtag_ate_i;

      system_reset_n_o : out nsl_io.io.opendrain
      );
  end component;
  
end package transactor;

package body transactor is

  function cmd_shift_bytes(data: byte_string; read_tdo : boolean := true) return byte_string
  is
  begin
    assert data'length > 0
      report "Bad data length: too short"
      severity failure;
    assert data'length <= 32
      report "Bad data length: too long"
      severity failure;

    if read_tdo then
      return to_byte(16#60# + data'length - 1) & data;
    else
      return to_byte(16#40# + data'length - 1) & data;
    end if;
  end function;
  
  function cmd_shift_bytes(byte_count: integer range 1 to 32) return byte_string
  is
  begin
    return (0 => to_byte(16#20# + byte_count - 1));
  end function;

  procedure rsp_shift_bytes(rsp_buffer: inout byte_stream; received: out byte_string)
  is
  begin
    read(rsp_buffer, received);
    rsp(rsp_buffer);
  end procedure;

  procedure rsp_shift_bytes(rsp_buffer: inout byte_stream)
  is
  begin
    rsp(rsp_buffer);
  end procedure;

  function cmd_shift_bits(data: std_ulogic_vector; read_tdo : boolean := true) return byte_string
  is
  begin
    assert data'length >= 1
      report "Bad data length: too short"
      severity failure;
    assert data'length <= 8
      report "Bad data length: too long"
      severity failure;

    if read_tdo then
      return to_byte(16#f8# + data'length - 1) & to_byte(to_integer(unsigned(data)));
    else
      return to_byte(16#f0# + data'length - 1) & to_byte(to_integer(unsigned(data)));
    end if;
  end function;

  function cmd_shift_bits(bit_count: integer range 1 to 8) return byte_string
  is
  begin
    return (0 => to_byte(16#e8# + bit_count - 1));
  end function;

  procedure rsp_shift_bits(rsp_buffer: inout byte_stream; received: out std_ulogic_vector)
  is
    variable tmp: byte;
  begin
    read(rsp_buffer, tmp);
    received := tmp(received'length-1 downto 0);
    rsp(rsp_buffer);
  end procedure;

  procedure rsp_shift_bits(rsp_buffer: inout byte_stream)
  is
  begin
    rsp(rsp_buffer);
  end procedure;

  function cmd_capture_dr return byte_string
  is
  begin
    return (0 => JTAG_CMD_DR_CAPTURE);
  end function;

  function cmd_capture_ir return byte_string
  is
  begin
    return (0 => JTAG_CMD_IR_CAPTURE);
  end function;

  function cmd_swd_to_jtag return byte_string
  is
  begin
    return (0 => JTAG_CMD_SWD_TO_JTAG);
  end function;

  function cmd_divisor(divisor: integer range 1 to 256) return byte_string
  is
  begin
    return (0 => JTAG_CMD_DIVISOR, 1 => to_byte(divisor - 1));
  end function;

  function cmd_system_reset(asserted: boolean) return byte_string
  is
  begin
    if asserted then
      return (0 => x"85");
    else
      return (0 => x"84");
    end if;
  end function;

  function cmd_run_x8(cycles_x8: integer range 1 to 16) return byte_string
  is
  begin
    return (0 => to_byte(16#a0# + cycles_x8 - 1));
  end function;

  function cmd_reset_x8(cycles_x8: integer range 1 to 16) return byte_string
  is
  begin
    return (0 => to_byte(16#b0# + cycles_x8 - 1));
  end function;

  function cmd_run(cycles: integer range 1 to 8) return byte_string
  is
  begin
    return (0 => to_byte(16#90# + cycles - 1));
  end function;

  function cmd_reset(cycles: integer range 1 to 8) return byte_string
  is
  begin
    return (0 => to_byte(16#98# + cycles - 1));
  end function;

  procedure rsp(rsp_buffer: inout byte_stream)
  is
    variable tmp: byte;
  begin
    read(rsp_buffer, tmp);
    assert tmp = x"5a"
      report "Unexpected response from ATE: "&to_string(tmp)
      severity warning;
  end procedure;
  
  function cmd_shift(data: std_ulogic_vector; read_tdo : boolean := true) return byte_string
  is
    alias xdata: std_ulogic_vector(data'length-1 downto 0) is data;
    variable command: byte_stream := null;
    variable point, chunk_len: integer := 0;
  begin
    while point < xdata'length
    loop
      chunk_len := nsl_math.arith.min(xdata'length - point, 32 * 8);
      if chunk_len <= 8 then
        write(command, cmd_shift_bits(xdata(point + chunk_len - 1 downto point), read_tdo));
      else
        chunk_len := chunk_len - (chunk_len mod 8);
        write(command, cmd_shift_bytes(to_le(unsigned(xdata(point + chunk_len - 1 downto point))), read_tdo));
      end if;
      point := point + chunk_len;
    end loop;

    return command.all;
  end function;

  procedure rsp_shift(rsp_buffer: inout byte_stream; data: out std_ulogic_vector)
  is
    variable rdata: std_ulogic_vector(data'length-1 downto 0) := (others => '-');
    variable point, chunk_len: integer := 0;
    variable rx_blob: byte_string(0 to 31);
  begin
    while point < rdata'length
    loop
      chunk_len := nsl_math.arith.min(rdata'length - point, 32 * 8);
      if chunk_len <= 8 then
        rsp_shift_bits(rsp_buffer, rdata(point + chunk_len - 1 downto point));
      else
        chunk_len := chunk_len - (chunk_len mod 8);
        rsp_shift_bytes(rsp_buffer, rx_blob(0 to chunk_len / 8 - 1));
        rdata(point + chunk_len - 1 downto point) := std_ulogic_vector(from_le(rx_blob(0 to chunk_len / 8 - 1)));
      end if;
      point := point + chunk_len;
    end loop;

    data := rdata;
  end procedure;

  procedure rsp_shift(rsp_buffer: inout byte_stream; data_len: in integer)
  is
    variable point, chunk_len: integer := 0;
  begin
    while point < data_len
    loop
      chunk_len := nsl_math.arith.min(data_len - point, 32 * 8);
      if chunk_len <= 8 then
        rsp(rsp_buffer);
      else
        chunk_len := chunk_len - (chunk_len mod 8);
        rsp(rsp_buffer);
      end if;
      point := point + chunk_len;
    end loop;
  end procedure;

end package body;
