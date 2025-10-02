library ieee;
use ieee.std_logic_1164.all;

library nsl_io, work;

-- DVI signal driver
package transceiver is

  component dvi_driver is
    generic(
      driver_mode_c : string := "default"
      );
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;
      serial_clock_i : in std_ulogic;
      
      tmds_i : in work.dvi.symbol_vector_t;

      clock_o : out nsl_io.diff.diff_pair;
      data_o : out nsl_io.diff.diff_pair_vector(0 to 2)
      );
  end component;

end package;
