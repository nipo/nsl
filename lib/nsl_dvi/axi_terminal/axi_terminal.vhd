library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_data, nsl_indication, nsl_math;

package axi_terminal is

  component axi4_dvi_terminal is
    generic(
      row_count_l2_c: positive;
      column_count_l2_c: positive;
      character_count_l2_c : positive range 1 to 8;
      color_count_l2_c : positive range 1 to 8;
      underline_support_c: boolean := false;
      font_hscale_c: positive := 1;
      font_vscale_c: positive := 1
      );
    port(
      video_clock_i : in  std_ulogic;
      video_reset_n_i : in std_ulogic;

      sof_i : in  std_ulogic;
      sol_i : in  std_ulogic;
      pixel_ready_i : in std_ulogic;
      pixel_valid_o : out std_ulogic;
      pixel_o : out nsl_color.rgb.rgb24;

      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;

      axi_i: in nsl_amba.axi4_mm.master_t;
      axi_o: in nsl_amba.axi4_mm.slave_t
      );
  end component;

end package;
