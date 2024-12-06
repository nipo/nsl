library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;
use nsl_axi.axi4_stream.all;

package stream_routing is
  
  component axi4_stream_funnel is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      source_count_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_vector(0 to source_count_c-1);
      in_o : out slave_vector(0 to source_count_c-1);

      out_o : out master_t;
      out_i : in slave_t
      );
  end component;

  component axi4_stream_dispatch is
    generic(
      in_config_c : config_t;
      out_config_c : config_t;
      destination_count_c : positive
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i : in master_t;
      in_o : out slave_t;

      out_o : out master_vector(0 to destination_count_c-1);
      out_i : in slave_vector(0 to destination_count_c-1)
      );
  end component;

end package stream_routing;
