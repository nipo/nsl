library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;

package fifo is

  component axi4_stream_fifo is
    generic(
      config_c : nsl_axi.axi4_stream.config_t;
      depth_c : positive;
      clock_count_c : integer range 1 to 2 := 1
      );
    port(
      clock_i : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i : in nsl_axi.axi4_stream.master_t;
      in_o : out nsl_axi.axi4_stream.slave_t;
      in_free_o : out integer range 0 to depth_c;

      out_o : out nsl_axi.axi4_stream.master_t;
      out_i : in nsl_axi.axi4_stream.slave_t;
      out_available_o : out integer range 0 to depth_c + 1
      );
  end component;

end package fifo;
