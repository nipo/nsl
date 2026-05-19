library ieee;
use ieee.std_logic_1164.all;

library nsl_avalon;

package stream_fifo is

  -- Single or dual-clock Avalon-ST FIFO. Input and output share a
  -- single config; the config must declare ready_latency = 0 (and
  -- consequently ready_allowance = 0).
  component avalon_st_fifo is
    generic(
      config_c      : nsl_avalon.avalon_st.config_t;
      depth_c       : positive range 4 to positive'high;
      clock_count_c : integer  range 1 to 2 := 1
      );
    port(
      clock_i   : in std_ulogic_vector(0 to clock_count_c-1);
      reset_n_i : in std_ulogic;

      in_i      : in  nsl_avalon.avalon_st.source_t;
      in_o      : out nsl_avalon.avalon_st.sink_t;
      in_free_o : out integer range 0 to depth_c;

      out_o           : out nsl_avalon.avalon_st.source_t;
      out_i           : in  nsl_avalon.avalon_st.sink_t;
      out_available_o : out integer range 0 to depth_c + 1
      );
  end component;

end package;
