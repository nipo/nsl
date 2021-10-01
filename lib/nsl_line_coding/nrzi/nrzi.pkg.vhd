library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package nrzi is

  component nrzi_transmitter
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      valid_i : in std_ulogic;
      bit_i : in std_ulogic;

      data_o : out std_ulogic
      );
  end component;

  component nrzi_receiver_recovery
    generic (
      clock_i_hz_c : natural;
      run_length_limit_c : natural := 3;
      signal_hz_c : natural;
      target_ppm_c : natural := 30000
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      data_i : in std_ulogic;

      bit_o : out std_ulogic;
      valid_o : out std_ulogic;

      tick_o : out std_ulogic
      );
  end component;

end package nrzi;
