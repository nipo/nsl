library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.apb.all;

package ctx is

  component mockup_slave is
    generic (
      config_c: config_t;
      index_c: natural
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';

      apb_i: in master_t;
      apb_o: out slave_t
      );
  end component;

end package;
