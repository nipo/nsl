library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

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

  -- Driver for a 74x594 through framed transactor
  component io_extender_framed_driver is
    generic(
      clock_divisor_c : natural range 0 to 2**5-1;
      slave_no_c : natural range 0 to 6
      );
    port(
      reset_n_i    : in std_ulogic;
      clock_i      : in std_ulogic;

      data_i       : in std_ulogic_vector(7 downto 0);

      cmd_i : in  nsl_bnoc.framed.framed_ack;
      cmd_o : out nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack;
      rsp_i : in  nsl_bnoc.framed.framed_req
      );
  end component;

end package io_extender;
