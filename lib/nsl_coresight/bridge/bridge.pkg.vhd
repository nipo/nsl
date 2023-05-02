library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
library work;

use work.swd.all;

package bridge is

  component swd_bridge is
    port(
      reset_n_i: in std_ulogic;

      probe_i: in swd_slave_i;
      probe_o: out swd_slave_o;

      target_o: out swd_master_o;
      target_i: in swd_master_i
      );
  end component;

end package bridge;
