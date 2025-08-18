library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_smi, nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

package transactor is

  constant SMI_C45_ADDR      : nsl_bnoc.framed.framed_data_t := "000-----";
  constant SMI_C45_WRITE     : nsl_bnoc.framed.framed_data_t := "001-----";
  constant SMI_C45_READINC   : nsl_bnoc.framed.framed_data_t := "010-----";
  constant SMI_C45_READ      : nsl_bnoc.framed.framed_data_t := "011-----";
  constant SMI_C22_READ      : nsl_bnoc.framed.framed_data_t := "100-----";
  constant SMI_C22_WRITE     : nsl_bnoc.framed.framed_data_t := "101-----";

  constant SMI_STATUS_OK     : nsl_bnoc.framed.framed_data_t := "-------0";
  constant SMI_STATUS_ERROR  : nsl_bnoc.framed.framed_data_t := "-------1";

  -- Command structure:
  -- [C22_READ    | PHYAD] [000 |  ADDR] -> [DATA_H] [DATA_L] [STATUS]
  -- [C22_WRITE   | PHYAD] [000 |  ADDR] [DATA_H] [DATA_L] -> [STATUS]
  -- [C45_ADDR    | PRTAD] [000 | DEVAD] [ADDR_H] [ADDR_L] -> [STATUS]
  -- [C45_WRITE   | PRTAD] [000 | DEVAD] [DATA_H] [DATA_L] -> [STATUS]
  -- [C45_READ    | PRTAD] [000 | DEVAD] -> [DATA_H] [DATA_L] [STATUS]
  -- [C45_READINC | PRTAD] [000 | DEVAD] -> [DATA_H] [DATA_L] [STATUS]
  
  component smi_framed_transactor
    generic(
      clock_freq_c : natural := 150000000;
      mdc_freq_c : natural := 25000000
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      smi_o  : out nsl_smi.smi.smi_master_o;
      smi_i  : in  nsl_smi.smi.smi_master_i;

      cmd_i  : in nsl_bnoc.framed.framed_req;
      cmd_o  : out nsl_bnoc.framed.framed_ack;
      rsp_o  : out nsl_bnoc.framed.framed_req;
      rsp_i  : in nsl_bnoc.framed.framed_ack
      );
  end component;

  function c22_write(phyad, addr: natural;
                         data: unsigned) return byte_string;

  function c22_read(phyad, addr: natural) return byte_string;

  function write_rsp return byte_string;
  function read_rsp(data: unsigned; ok: boolean := true) return byte_string;

  function c22x_write(prtad, devad: natural;
                          addr, data: unsigned) return byte_string;

  function c22x_read(prtad, devad: natural;
                         addr: unsigned) return byte_string;

  function c45_addr(prtad, devad: natural;
                        addr: unsigned) return byte_string;

  function c45_write(prtad, devad: natural;
                         data: unsigned) return byte_string;

end package transactor;

package body transactor is

  use nsl_data.endian.all;
  
  function c22_write(phyad, addr: natural;
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

  function c22_read(phyad, addr: natural) return byte_string
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

  function c45_addr(prtad, devad: natural;
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
     

  function c45_write(prtad, devad: natural;
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

  function c22x_write(prtad, devad: natural;
                          addr, data: unsigned) return byte_string
  is
  begin
    return c22_write(prtad, 13, to_unsigned(devad, 16))
      & c22_write(prtad, 14, addr)
      & c22_write(prtad, 13, to_unsigned(16#4000# + devad, 16))
      & c22_write(prtad, 14, data);
  end function;

  function c22x_read(prtad, devad: natural;
                         addr: unsigned) return byte_string
  is
  begin
    return c22_write(prtad, 13, to_unsigned(devad, 16))
      & c22_write(prtad, 14, addr)
      & c22_write(prtad, 13, to_unsigned(16#4000# + devad, 16))
      & c22_read(prtad, 14);
  end function;

  function write_rsp return byte_string
  is
    constant st_ok: byte_string(0 to 0) := (others => SMI_STATUS_OK);
  begin
    return st_ok;
  end function;

  function read_rsp(data: unsigned; ok: boolean := true) return byte_string
  is
    constant st_ok: byte_string(0 to 0) := (others => SMI_STATUS_OK);
    constant st_err: byte_string(0 to 0) := (others => SMI_STATUS_ERROR);
    constant bdata: byte_string(0 to 1) := to_be(data);
  begin
    if ok then
      return bdata & st_ok;
    else
      return bdata & st_err;
    end if;
  end function;

end package body;  
