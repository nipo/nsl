library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;

package ram is

  component axi4_lite_a32_d32_ram is
    generic (
      mem_size_log2_c: natural := 12
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';
      
      axi_i: in nsl_axi.axi4_lite.a32_d32_ms;
      axi_o: out nsl_axi.axi4_lite.a32_d32_sm
      );
  end component;

end package ram;
