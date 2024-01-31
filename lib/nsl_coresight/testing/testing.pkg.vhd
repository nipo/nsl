library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_data, nsl_bnoc, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_data.endian.all;
use nsl_bnoc.testing.all;

package testing is

  procedure dp_swd_init(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    dp_idr: unsigned;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_dp_swd_init(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    dp_idr: unsigned;
    constant level : log_level_t := LOG_LEVEL_WARNING);
  
  procedure memap_passthrough(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant cmd : in byte_string;
    constant rsp : in byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_param_set(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant address: unsigned;
    constant csw: unsigned;
    constant interval: integer range 1 to 64 := 10;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_write(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_read_check(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_write16(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_read16_check(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant lsb: integer;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_write8(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING);

  procedure memap_read8_check(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant lsb: integer;
    constant level : log_level_t := LOG_LEVEL_WARNING);
  
  component swdap
    generic(
      idr: unsigned(31 downto 0) := X"2ba01477"
      );
    port (
      p_swd_c : out nsl_coresight.swd.swd_slave_o;
      p_swd_s : in nsl_coresight.swd.swd_slave_i;
      p_swd_resetn : out std_ulogic;

      p_ap_ready : in std_ulogic;

      p_ap_sel : out unsigned(7 downto 0);

      p_ap_a : out unsigned(5 downto 0);

      p_ap_rdata : in unsigned(31 downto 0);
      p_ap_rok : in std_logic;
      p_ap_ren : out std_logic;
      
      p_ap_wdata : out unsigned(31 downto 0);
      p_ap_wen : out std_logic
      );
  end component;

  component ap_sim
    port (
      p_clk : in std_ulogic;
      p_resetn : in std_ulogic;

      p_ready : out std_ulogic;

      p_ap : in unsigned(7 downto 0);

      p_a : in unsigned(5 downto 0);

      p_rdata : out unsigned(31 downto 0);
      p_rok : out std_logic;
      p_ren : in std_logic;

      p_wdata : in unsigned(31 downto 0);
      p_wen : in std_logic
      );
  end component;

end package testing;

package body testing is
  
  procedure dp_swd_init(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    dp_idr: unsigned;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    constant command : byte_string := from_hex("c105007171717171ef9ee7000071ef9ee7000071717171000290");
    constant response: byte_string := from_hex("c17171717171ef71ef71717171000291") & to_le(dp_idr);
  begin
    framed_txn_check(log_context, cmd_queue, rsp_queue, command, response, level);
  end procedure;

  procedure memap_passthrough(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant cmd : in byte_string;
    constant rsp : in byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    constant rsp_passthrough: byte_string := from_hex("49");
    constant cmd_passthrough: byte_string := from_hex("48");
  begin
    framed_txn_check(log_context, cmd_queue, rsp_queue, rsp_passthrough & cmd_passthrough & cmd, rsp, level);
  end procedure;
  
  procedure memap_dp_swd_init(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    dp_idr: unsigned;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    constant command : byte_string := from_hex("c10a007171717171ef9ee7000071ef9ee7000071717171000290");
    constant response : byte_string := from_hex("c17171717171ef71ef71717171000291") & to_le(dp_idr);
  begin
    memap_passthrough(log_context, cmd_queue, rsp_queue, command, response, level);
  end procedure;

  procedure memap_param_set(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant address: unsigned;
    constant csw: unsigned;
    constant interval: integer range 1 to 64 := 10;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable cmd: byte_stream;
    variable rsp: byte_stream;
  begin
    clear(cmd);
    clear(rsp);
    
    assert address'length = 32
      report "Bad address length"
      severity failure;
    
    assert csw'length = 24
      report "Bad csw length"
      severity failure;
    
    -- Set CSW
    write(cmd, from_hex("46") & to_le(csw));
    -- Set Interval
    write(cmd, to_byte(interval));
    -- Set address
    write(cmd, from_hex("45") & to_le(address));
    write(cmd, from_hex("4f"));
    write(rsp, from_hex("4f"));
    
    framed_txn_check(log_context, cmd_queue, rsp_queue, cmd.all, rsp.all, level);

    clear(cmd);
    clear(rsp);
  end procedure;

  procedure memap_write(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable cmd: byte_stream;
    variable rsp: byte_stream;
  begin
    clear(cmd);
    clear(rsp);

    assert (data'length mod 4) = 0
      report "Unaligned data"
      severity failure;

    assert data'length <= 256
      report "Data too long"
      severity failure;

    write(cmd, to_byte(16#80# + (data'length / 4 - 1)) & data);
    write(rsp, byte'("0-------"));
    
    framed_txn_check(log_context, cmd_queue, rsp_queue, cmd.all, rsp.all, level);

    clear(cmd);
    clear(rsp);
  end procedure;

  procedure memap_read_check(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable cmd: byte_stream;
    variable rsp: byte_stream;
  begin
    clear(cmd);
    clear(rsp);

    assert (data'length mod 4) = 0
      report "Unaligned data"
      severity failure;

    assert data'length <= 256
      report "Data too long"
      severity failure;
    
    write(cmd, to_byte(16#c0# + (data'length / 4 - 1)));
    write(rsp, data);
    write(rsp, byte'("0-------"));
    
    framed_txn_check(log_context, cmd_queue, rsp_queue, cmd.all, rsp.all, level);

    clear(cmd);
    clear(rsp);
  end procedure;

  procedure memap_write16(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable cmd: byte_stream;
    variable rsp: byte_stream;
  begin
    clear(cmd);
    clear(rsp);

    assert data'length = 2
      report "Bad data length"
      severity failure;

    write(cmd, from_hex("43") & data & data);
    write(rsp, byte'("0-------"));

    framed_txn_check(log_context, cmd_queue, rsp_queue, cmd.all, rsp.all, level);

    clear(cmd);
    clear(rsp);
  end procedure;

  procedure memap_read16_check(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant lsb: integer;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable cmd: byte_stream;
    variable rsp: byte_stream;
  begin
    clear(cmd);
    clear(rsp);

    assert data'length = 2
      report "Bad data length"
      severity failure;
    
    write(cmd, from_hex("41"));
    for i in 0 to 1
    loop
      if lsb = i*2 then
        write(rsp, data);
      else
        write(rsp, dontcare_byte_c);
        write(rsp, dontcare_byte_c);
      end if;
    end loop;
    write(rsp, byte'("0-------"));
    
    framed_txn_check(log_context, cmd_queue, rsp_queue, cmd.all, rsp.all, level);

    clear(cmd);
    clear(rsp);
  end procedure;

  procedure memap_write8(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable cmd: byte_stream;
    variable rsp: byte_stream;
  begin
    clear(cmd);
    clear(rsp);

    assert data'length = 1
      report "Bad data length"
      severity failure;

    write(cmd, from_hex("42") & data & data & data & data);
    write(rsp, byte'("0-------"));
    
    framed_txn_check(log_context, cmd_queue, rsp_queue, cmd.all, rsp.all, level);

    clear(cmd);
    clear(rsp);
  end procedure;

  procedure memap_read8_check(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant data: byte_string;
    constant lsb: integer;
    constant level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable cmd: byte_stream;
    variable rsp: byte_stream;
  begin
    clear(cmd);
    clear(rsp);
    
    write(cmd, from_hex("40"));
    for i in 0 to 3
    loop
      if lsb = i then
        write(rsp, data);
      else
        write(rsp, dontcare_byte_c);
      end if;
    end loop;
    write(rsp, byte'("0-------"));
    
    framed_txn_check(log_context, cmd_queue, rsp_queue, cmd.all, rsp.all, level);

    clear(cmd);
    clear(rsp);
  end procedure;

end package body;
