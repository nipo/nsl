library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.framed.all;
use nsl_bnoc.routed.all;
use nsl_data.bytestream.all;

package framed_transactor is
  
  -- Generates a set of frames defined by a constant instance parameter. Mostly
  -- suited for issuing a bunch of initialization through protocol transactors
  -- (spi, i2c, etc.).
  --
  -- As routed interface is a superset of framed, you may connect this module
  -- to a routed network and issue frames with relevant headers.
  component framed_transactor_once
    generic(
      config_c : byte_string;
      inter_transaction_cycle_count_c : integer := 0
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;
      done_o      : out std_ulogic;

      -- After done_o rises, a 0 to 1 transition restarts the process.
      -- If done, setting enable_o to 0 clears done.
      enable_i   : in std_ulogic := '1';

      cmd_o  : out framed_req;
      cmd_i  : in framed_ack;
      rsp_i  : in framed_req;
      rsp_o  : out framed_ack
      );
  end component;

  function framed_transaction(command : byte_string) return byte_string;

  function routed_transaction(srcid, dstid : component_id;
                              tag : byte;
                              command : byte_string) return byte_string;

  function i2c_div(div: positive) return byte_string;

  function i2c_write(saddr: unsigned;
                     data: byte_string) return byte_string;
  function i2c_write_read(saddr: unsigned;
                          data: byte_string;
                          rsize: integer) return byte_string;

  function smi_c22_write(phyad, addr: natural;
                         data: unsigned) return byte_string;

  function smi_c22_read(phyad, addr: natural) return byte_string;

  function smi_c22x_write(prtad, devad: natural;
                          addr, data: unsigned) return byte_string;

  function smi_c22x_read(prtad, devad: natural;
                         addr: unsigned) return byte_string;

  function smi_c45_addr(prtad, devad: natural;
                        addr: unsigned) return byte_string;

  function smi_c45_write(prtad, devad: natural;
                         data: unsigned) return byte_string;

end package framed_transactor;

package body framed_transactor is

  function framed_transaction(command : byte_string) return byte_string
  is
    variable header : byte_string(1 to 1);
  begin
    header(1) := to_byte(command'length-1);

    return header & command;
  end function;

  function routed_header(dst: component_id; src: component_id)
    return nsl_bnoc.framed.framed_data_t is
  begin
    return nsl_bnoc.framed.framed_data_t(to_unsigned(src * 16 + dst, 8));
  end;

  function routed_transaction(srcid, dstid : component_id;
                              tag : byte;
                              command : byte_string) return byte_string
  is
    variable route_header : byte := routed_header(dst => dstid, src => srcid);
    variable header : byte_string(1 to 2);
  begin
    header(1) := route_header;
    header(2) := tag;
    return framed_transaction(header & command);
  end function;

  function i2c_div(div: positive) return byte_string
  is
    -- DIV
    variable ret: byte_string(1 to 1);
  begin
    assert 1 <= div and div <= 2**5
      report "Divisor out of bounds"
      severity failure;

     -- Divisor
    ret(1)(7 downto 5) := "000";
    ret(1)(4 downto 0) := std_ulogic_vector(to_unsigned(div-1, 5));
    return ret;
  end function;

  function i2c_write(saddr: unsigned;
                     data: byte_string) return byte_string
  is
    -- START / WRITE / SADDR / DATA... / STOP
    variable ret: byte_string(1 to data'length + 4);
  begin
    assert saddr'length = 7
      report "Bad slave address size"
      severity failure;
    assert data'length < 2**6
      report "Write data too long"
      severity failure;

     -- Start
    ret(1) := "00100000";
    -- Write command
    ret(2)(7 downto 6) := "01";
    ret(2)(5 downto 0) := std_ulogic_vector(to_unsigned(data'length-1+1, 6));
    -- saddr
    ret(3)(7 downto 1) := std_ulogic_vector(saddr);
    ret(3)(0) := '0';
    -- Data
    ret(4 to 4+data'length-1) := data;
    -- Stop
    ret(4 + data'length) := "00100001";
    return ret;
  end function;

  function i2c_write_read(saddr: unsigned;
                          data: byte_string;
                          rsize: integer) return byte_string
  is
    -- START / WRITE / SADDR / DATA... / START / WRITE / SADDR / READ x / STOP
    variable ret: byte_string(1 to data'length + 8);
  begin
    assert saddr'length = 7
      report "Bad slave address size"
      severity failure;
    assert data'length < 2**6
      report "Write data too long"
      severity failure;
    assert rsize < 2**6
      report "Read data too long"
      severity failure;

    -- Start
    ret(1) := "00100000";
    -- Write command
    ret(2) := "01" & std_ulogic_vector(to_unsigned(data'length-1+1, 6));
    -- saddr[W]
    ret(3) := std_ulogic_vector(saddr) & "0";
    -- Data
    ret(4 to 4+data'length-1) := data;
    -- Restart
    ret(4 + data'length) := "00100000";
    -- Write command
    ret(5 + data'length) := "01000000";
    -- saddr[R]
    ret(6 + data'length) := std_ulogic_vector(saddr) & "1";
    -- Read nack command
    ret(7 + data'length) := "10" & std_ulogic_vector(to_unsigned(rsize-1, 6));
    -- Stop
    ret(8 + data'length) := "00100001";
    return ret;
  end function;

  function smi_c22_write(phyad, addr: natural;
                         data: unsigned) return byte_string
  is
    alias xdata: unsigned(data'length-1 downto 0) is data;
    variable ret: byte_string(1 to 4);
  begin
    assert data'length = 16
      report "Bad data size"
      severity failure;
    assert phyad <= 31
      report "Bad phy address"
      severity failure;
    assert addr <= 31
      report "Bad register address"
      severity failure;

    ret(1)(7 downto 5) := "101";
    ret(1)(4 downto 0) := std_ulogic_vector(to_unsigned(phyad, 5));
    ret(2)(7 downto 5) := "000";
    ret(2)(4 downto 0) := std_ulogic_vector(to_unsigned(addr, 5));
    ret(3) := std_ulogic_vector(xdata(15 downto 8));
    ret(4) := std_ulogic_vector(xdata(7 downto 0));
    
    return ret;
  end function;

  function smi_c22_read(phyad, addr: natural) return byte_string
  is
    variable ret: byte_string(1 to 2);
  begin
    assert phyad <= 31
      report "Bad phy address"
      severity failure;
    assert addr <= 31
      report "Bad register address"
      severity failure;

    ret(1)(7 downto 5) := "100";
    ret(1)(4 downto 0) := std_ulogic_vector(to_unsigned(phyad, 5));
    ret(2)(7 downto 5) := "000";
    ret(2)(4 downto 0) := std_ulogic_vector(to_unsigned(addr, 5));
    
    return ret;
  end function;

  function smi_c45_addr(prtad, devad: natural;
                        addr: unsigned) return byte_string
  is
    alias xaddr: unsigned(addr'length-1 downto 0) is addr;
    variable ret: byte_string(1 to 4);
  begin
    assert addr'length = 16
      report "Bad addr size"
      severity failure;
    assert prtad <= 31
      report "Bad port address"
      severity failure;
    assert devad <= 31
      report "Bad device address"
      severity failure;

    ret(1)(7 downto 5) := "000";
    ret(1)(4 downto 0) := std_ulogic_vector(to_unsigned(prtad, 5));
    ret(2)(7 downto 5) := "000";
    ret(2)(4 downto 0) := std_ulogic_vector(to_unsigned(devad, 5));
    ret(3) := std_ulogic_vector(xaddr(15 downto 8));
    ret(4) := std_ulogic_vector(xaddr(7 downto 0));
    
    return ret;
  end function;
     

  function smi_c45_write(prtad, devad: natural;
                         data: unsigned) return byte_string
  is
    alias xdata: unsigned(data'length-1 downto 0) is data;
    variable ret: byte_string(1 to 4);
  begin
    assert data'length = 16
      report "Bad data size"
      severity failure;
    assert prtad <= 31
      report "Bad port address"
      severity failure;
    assert devad <= 31
      report "Bad device address"
      severity failure;

    ret(1)(7 downto 5) := "001";
    ret(1)(4 downto 0) := std_ulogic_vector(to_unsigned(prtad, 5));
    ret(2)(7 downto 5) := "000";
    ret(2)(4 downto 0) := std_ulogic_vector(to_unsigned(devad, 5));
    ret(3) := std_ulogic_vector(xdata(15 downto 8));
    ret(4) := std_ulogic_vector(xdata(7 downto 0));
    
    return ret;
  end function;

  function smi_c22x_write(prtad, devad: natural;
                          addr, data: unsigned) return byte_string
  is
  begin
    return smi_c22_write(prtad, 13, to_unsigned(devad, 16))
      & smi_c22_write(prtad, 14, addr)
      & smi_c22_write(prtad, 13, to_unsigned(16#4000# + devad, 16))
      & smi_c22_write(prtad, 14, data);
  end function;

  function smi_c22x_read(prtad, devad: natural;
                         addr: unsigned) return byte_string
  is
  begin
    return smi_c22_write(prtad, 13, to_unsigned(devad, 16))
      & smi_c22_write(prtad, 14, addr)
      & smi_c22_write(prtad, 13, to_unsigned(16#4000# + devad, 16))
      & smi_c22_read(prtad, 14);
  end function;

end package body framed_transactor;
