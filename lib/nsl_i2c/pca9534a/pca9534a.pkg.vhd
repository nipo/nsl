library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

package pca9534a is

  -- PCA9534A GPIO extender reflector.
  --
  -- This module is register-compatible with the following:
  -- - TCA6408A (pushpull, 010000-, reset)
  -- - TCA6408 (pushpull, 010000-, reset)
  -- - PCA6107 (pushpull/opendrain, 0011---)
  -- - PCA9534 (pushpull, 0100---)
  -- - PCA9534A (pushpull, 0111---)
  -- - PCA9538 (pushpull, 11100--, reset)
  -- - PCA9554 (pushpull, 0100---)
  -- - PCA9554A (pushpull, 0111---)
  -- - PCA9557 (opendrain, 0011---, reset, no irq)
  --
  -- Takes a bit vector and forwards it to the remote enterder ASAP when it
  -- changes. There is no guarantee on delivery latency. It depends on the
  -- internal transactor usage and bus traffic.
  --
  -- If IRQ is available, reads the inputs as long as IRQ is asserted.
  --
  -- Use routed_transactor_once for initialization of device
  component pca9534a_driver is
    generic(
      i2c_addr_c    : unsigned(6 downto 0) := "0111000";
      in_supported_c : boolean := true
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      -- Forces refresh
      force_i : in std_ulogic := '0';

      busy_o  : out std_ulogic;

      irq_n_i     : in std_ulogic := '1';

      pin_i       : in std_ulogic_vector(0 to 7);
      pin_o       : out std_ulogic_vector(0 to 7);

      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

  type pca9534a_pin_config is
  record
    output : boolean;
    in_inverted : boolean;
    value : std_ulogic;
  end record;

  constant pca9534a_out_0 : pca9534a_pin_config := (output => true, in_inverted => false, value => '0');
  constant pca9534a_out_1 : pca9534a_pin_config := (output => true, in_inverted => false, value => '1');
  constant pca9534a_in : pca9534a_pin_config := (output => false, in_inverted => false, value => '0');
  constant pca9534a_in_inv : pca9534a_pin_config := (output => false, in_inverted => true, value => '0');

  type pca9534a_pin_config_vector is array(integer range 0 to 7) of pca9534a_pin_config;

  -- Spawn a byte string suitable for
  -- nsl_bnoc.framed_transactor.framed_transactor_once for
  -- proper initialization of device.
  function pca9534a_init(saddr: unsigned;
                          config: pca9534a_pin_config_vector) return byte_string;
  
end package pca9534a;

package body pca9534a is

  function pca9534a_write_multiple(saddr: unsigned;
                                    reg_addr: byte;
                                    value: std_ulogic_vector) return byte_string
  is
    variable reg: byte_string(1 to 1);
  begin
    reg(1) := reg_addr;

    return nsl_bnoc.framed_transactor.i2c_write(saddr, reg & nsl_data.endian.to_le(unsigned(value)));
  end function;

  function pca9534a_init(saddr: unsigned;
                          config: pca9534a_pin_config_vector) return byte_string
  is
    variable value, in_inverted, hiz : std_ulogic_vector(7 downto 0);
  begin
    for i in 0 to 7
    loop
      hiz(i) := to_logic(not config(i).output);
      value(i) := config(i).value;
      in_inverted(i) := to_logic(config(i).in_inverted);
    end loop;

    return pca9534a_write_multiple(saddr, x"02", in_inverted)
      & pca9534a_write_multiple(saddr, x"01", value)
      & pca9534a_write_multiple(saddr, x"03", hiz)
      ;    
  end function;
  
end package body pca9534a;
