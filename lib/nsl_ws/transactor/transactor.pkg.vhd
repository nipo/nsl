library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_bnoc;

package transactor is

  component ws_2812_framed is
    generic(
      color_order : string := "GRB";
      clk_freq_hz : natural;
      error_ns : natural := 150;
      t0h_ns : natural := 350;
      t0l_ns : natural := 1360;
      t1h_ns : natural := 1360;
      t1l_ns : natural := 350
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      led_o : out std_ulogic;

      cmd_i   : in nsl_bnoc.framed.framed_req;
      cmd_o   : out nsl_bnoc.framed.framed_ack;

      rsp_o   : out nsl_bnoc.framed.framed_req;
      rsp_i   : in nsl_bnoc.framed.framed_ack
      );
  end component;
  
end package transactor;
