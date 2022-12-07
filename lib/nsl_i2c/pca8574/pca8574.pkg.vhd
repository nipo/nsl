library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

package pca8574 is

  -- PCA8574 GPIO extender reflector.
  --
  -- This module is register-compatible with the following:
  -- - PCA9760
  --
  -- Takes a bit vector and forwards it to the remote enterder ASAP when it
  -- changes. There is no guarantee on delivery latency. It depends on the
  -- internal transactor usage and bus traffic.
  --
  -- If IRQ is available, reads the inputs as long as IRQ is asserted.
  --
  -- Use routed_transactor_once for initialization of device
  component pca8574_driver is
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
  
end package pca8574;
