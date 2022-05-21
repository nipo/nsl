library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

package pca9555 is

  -- PCA9555 GPIO extender reflector.
  --
  -- Takes a bit vector and forwards it to the remote enterder ASAP when it
  -- changes. There is no guarantee on delivery latency. It depends on the
  -- internal transactor usage and bus traffic.
  --
  -- If IRQ is available, reads the inputs as long as IRQ is asserted.
  --
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

      -- Forces refresh
      force_i : in std_ulogic := '0';

      busy_o  : out std_ulogic;

      irq_n_i     : in std_ulogic := '1';

      pin_i       : in std_ulogic_vector(0 to 15);
      pin_o       : out std_ulogic_vector(0 to 15);

      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

  type pca9555_pin_config is
  record
    output : boolean;
    in_inverted : boolean;
    value : std_ulogic;
  end record;

  constant pca9555_out_0 : pca9555_pin_config := (output => true, in_inverted => false, value => '0');
  constant pca9555_out_1 : pca9555_pin_config := (output => true, in_inverted => false, value => '1');
  constant pca9555_in : pca9555_pin_config := (output => false, in_inverted => false, value => '0');
  constant pca9555_in_inv : pca9555_pin_config := (output => false, in_inverted => true, value => '0');

  type pca9555_pin_config_vector is array(integer range 0 to 15) of pca9555_pin_config;

  -- Spawn a byte string suitable for
  -- nsl_bnoc.framed_transactor.framed_transactor_once for
  -- proper initialization of device.
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
    variable value, in_inverted, hiz : std_ulogic_vector(15 downto 0);
  begin
    for i in 0 to 15
    loop
      hiz(i) := to_logic(not config(i).output);
      value(i) := config(i).value;
      in_inverted(i) := to_logic(config(i).in_inverted);
    end loop;

    return pca9555_write_multiple(saddr, x"04", in_inverted)
      & pca9555_write_multiple(saddr, x"02", value)
      & pca9555_write_multiple(saddr, x"06", hiz)
      ;    
  end function;
  
end package body pca9555;
