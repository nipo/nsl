library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

package pca9555 is

  -- Use routed_transactor_once for initialization of device
  component pca9555_driver is
    generic(
      i2c_addr_c    : unsigned(6 downto 0) := "0100000";
      i2c_divisor_c : unsigned(4 downto 0);
      in_supported_c : boolean := true
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      irq_n_i     : in std_ulogic := '1';

      pin_i       : in std_ulogic_vector(15 downto 0);
      pin_o       : out std_ulogic_vector(15 downto 0);

      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

  type pca9555_pin_config is
  record
    output : boolean;
    inverted : boolean;
    value : std_ulogic;
  end record;

  type pca9555_pin_config_vector is array(integer range 0 to 15) of pca9555_pin_config;
  
  function pca9555_init(saddr: unsigned;
                        config: pca9555_pin_config_vector) return byte_string;
  
end package pca9555;

package body pca9555 is

  function pca9555_write_multiple(saddr: unsigned;
                                  reg_addr: byte;
                                  value: std_ulogic_vector) return byte_string
  is
    variable reg: byte_string(1 to 1);
  begin
    reg(1) := reg_addr;

    return nsl_bnoc.framed_transactor.i2c_write(saddr, reg & nsl_data.endian.to_le(unsigned(value)));
  end function;

  function pca9555_init(saddr: unsigned;
                         config: pca9555_pin_config_vector) return byte_string
  is
    variable value, inverted, hiz : std_ulogic_vector(15 downto 0);
  begin
    for i in 0 to 15
    loop
      hiz(i) := to_logic(not config(i).output);
      value(i) := config(i).value;
      inverted(i) := to_logic(config(i).inverted);
    end loop;

    return pca9555_write_multiple(saddr, x"04", inverted)
      & pca9555_write_multiple(saddr, x"02", value)
      & pca9555_write_multiple(saddr, x"06", hiz)
      ;    
  end function;
  
end package body pca9555;
