library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;

package axi_fifo16 is

  component axi_fifo16_ep is
    generic(
      master_buffer_depth: natural range 4 to 4096;
      slave_buffer_depth: natural range 4 to 4096
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic := '1';
      
      axi_i: in nsl_axi.axi4_lite.a32_d32_ms;
      axi_o: out nsl_axi.axi4_lite.a32_d32_sm;

      axis_m_i: in nsl_axi.stream.axis_16l_sm;
      axis_m_o: out nsl_axi.stream.axis_16l_ms;

      axis_s_i: in nsl_axi.stream.axis_16l_ms;
      axis_s_o: out nsl_axi.stream.axis_16l_sm
      );
  end component;

end package axi_fifo16;
