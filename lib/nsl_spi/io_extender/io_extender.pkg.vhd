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

      -- Shifted from left to right. For a 74x59[45], use a descending
      -- vector, it will be shifted MSB first. If multiple chips are
      -- chained, farther from controller is MSB.
      data_i       : in std_ulogic_vector;
      ready_o      : out std_ulogic;

      sr_d_o       : out std_ulogic;
      sr_clock_o   : out std_ulogic;
      sr_strobe_o  : out std_ulogic
      );
  end component;

end package io_extender;
