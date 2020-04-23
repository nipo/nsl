library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package io_extender is

  -- Driver for a 74x594
  component io_extender_sync_output is
    generic(
      clock_divisor_c : natural
      );
    port(
      reset_n_i    : in std_ulogic;
      clock_i      : in std_ulogic;

      data_i       : in std_ulogic_vector(7 downto 0);
      ready_o      : out std_ulogic;

      sr_d_o       : out std_ulogic;
      sr_clock_o   : out std_ulogic;
      sr_strobe_o  : out std_ulogic
      );
  end component;

end package io_extender;
