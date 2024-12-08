library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_jtag;

package axi4lite_transactor is

  constant JTAG_TRANSACTOR_REG_DIVISOR     : integer := 0;
  constant JTAG_TRANSACTOR_REG_RESET       : integer := 1;
  constant JTAG_TRANSACTOR_REG_RTI         : integer := 2;
  constant JTAG_TRANSACTOR_REG_SWD_TO_JTAG : integer := 3;
  constant JTAG_TRANSACTOR_REG_DR_CAPTURE  : integer := 4;
  constant JTAG_TRANSACTOR_REG_IR_CAPTURE  : integer := 5;
  constant JTAG_TRANSACTOR_REG_SHIFT1      : integer := 32;
  constant JTAG_TRANSACTOR_REG_SHIFT32     : integer := 32 + 31;

  component axi4lite_jtag_transactor is
    generic (
      prescaler_width_c : natural := 18;
      config_c : nsl_amba.axi4_mm.config_t
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';
      
      axi_i: in nsl_amba.axi4_mm.master_t;
      axi_o: out nsl_amba.axi4_mm.slave_t;

      jtag_o : out nsl_jtag.jtag.jtag_ate_o;
      jtag_i : in nsl_jtag.jtag.jtag_ate_i
      );
  end component;

end package;
