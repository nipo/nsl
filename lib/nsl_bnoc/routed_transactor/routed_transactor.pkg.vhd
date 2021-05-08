library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.routed.all;
use nsl_data.bytestream.all;

package routed_transactor is
  
  component routed_transactor_once
    generic(
      config_c : byte_string
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;
      done_o      : out std_ulogic;

      cmd_o  : out routed_req;
      cmd_i  : in routed_ack;
      rsp_i  : in routed_req;
      rsp_o  : out routed_ack
      );
  end component;

  function transaction(srcid, dstid : component_id;
                       tag : byte;
                       command : byte_string) return byte_string;

  function i2c_div(div: positive) return byte_string;

  function i2c_write(saddr: unsigned;
                     data: byte_string) return byte_string;

  function smi_c22_write(phyad, addr: natural;
                         data: unsigned) return byte_string;

  function smi_c22x_write(prtad, devad: natural;
                          addr, data: unsigned) return byte_string;

  function smi_c45_addr(prtad, devad: natural;
                        addr: unsigned) return byte_string;

  function smi_c45_write(prtad, devad: natural;
                         data: unsigned) return byte_string;

end package routed_transactor;

package body routed_transactor is

  function transaction(srcid, dstid : component_id;
                       tag : byte;
                       command : byte_string) return byte_string
  is
    variable route_header : byte := routed_header(dst => dstid, src => srcid);
    variable ret : byte_string(1 to command'length + 3);
  begin
    ret(1) := to_byte(ret'length-2);
    ret(2) := route_header;
    ret(3) := tag;
    for i in 0 to command'length-1
    loop
      ret(4+i) := command(command'left + i);
    end loop;
    return ret;
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

end package body routed_transactor;
