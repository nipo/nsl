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

  type vref_t is (
    VREF_VDD,
    VREF_UNBUFFERED,
    VREF_BUFFERED
    );

  type power_t is (
    POWER_ON,
    POWER_OFF_1k,
    POWER_OFF_100k,
    POWER_OFF_500k
    );
  
  function mcp4726_init(saddr: unsigned;
                        vref: vref_t;
                        power: power_t;
                        gain: integer range 1 to 2;
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
      ready_o : out std_ulogic;
      
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
                        vref: vref_t;
                        power: power_t;
                        gain: integer range 1 to 2;
                        value: unsigned(11 downto 0)) return byte_string
  is
    variable vref_u, pd_u : unsigned(1 downto 0);
    variable g_u: unsigned(0 downto 0);
  begin
    assert vref /= VREF_VDD or gain /= 2
      report "VREF = VDD and GAIN = 2 is not possible"
      severity failure;

    case vref is
      when VREF_VDD => vref_u := "00";
      when VREF_UNBUFFERED => vref_u := "10";
      when others => vref_u := "11";
    end case;

    case power is
      when POWER_ON => pd_u := "00";
      when POWER_OFF_1k => pd_u := "01";
      when POWER_OFF_100k => pd_u := "10";
      when others => pd_u := "11";
    end case;

    if gain = 1 then
      g_u := "0";
    else
      g_u := "1";
    end if;
    
    return null_byte_string
      & i2c_write(saddr, to_be("010" & vref_u & pd_u & g_u
                               & "0000" & value))
      ;
  end function;

end package body mcp4726;
