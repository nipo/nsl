library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_bnoc.framed.all;
use nsl_bnoc.framed_transactor.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

package mcp4726 is

  function mcp4726_addr(sel: integer range 0 to 7) return unsigned;

  function mcp4726_init(saddr: unsigned;
                        value: unsigned(11 downto 0)) return byte_string;

  -- MCP4726 writer
  component mcp4726_updater is
    generic(
      i2c_addr_c    : unsigned(6 downto 0)
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      -- allow transactions
      enable_i : in std_ulogic := '1';

      -- Force refresh
      force_i : in std_ulogic := '0';

      valid_i : in std_ulogic := '1';
      value_i : in unsigned(11 downto 0);

      busy_o : out std_ulogic;
      
      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

end package mcp4726;

package body mcp4726 is

  function mcp4726_addr(sel: integer range 0 to 7) return unsigned
  is
  begin
    return to_unsigned((sel mod 8) + 16#60#, 7);
  end function;

  function mcp4726_init(saddr: unsigned;
                        value: unsigned(11 downto 0)) return byte_string
  is
  begin
    return null_byte_string
      & i2c_write(saddr, to_be("0000" & value))
      ;
  end function;

end package body mcp4726;
