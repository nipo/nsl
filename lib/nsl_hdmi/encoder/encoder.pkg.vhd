library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_line_coding, nsl_data, work, nsl_dvi;

package encoder is

  component hdmi_13_encoder is
    generic(
      vendor_name_c: string := "NSL";
      product_description_c: string := "HDMI Encoder";
      source_type_c: integer := 0
      );
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;

      -- Vertical frame parameters
      v_fp_m1_i : in unsigned;
      v_sync_m1_i : in unsigned;
      v_bp_m1_i : in unsigned;
      v_act_m1_i : in unsigned;

      -- Horizontal frame parameters
      h_fp_m1_i : in unsigned;
      h_sync_m1_i : in unsigned;
      h_bp_m1_i : in unsigned;
      h_act_m1_i : in unsigned;

      -- sync values
      vsync_i : in std_ulogic := '1';
      hsync_i : in std_ulogic := '1';

      -- Start of frame strobe. It happens sol_o is not asserted yet
      sof_o : out std_ulogic;
      -- Start of line strobe. It happens pixel_ready_o is not asserted yet
      sol_o : out std_ulogic;
      -- Asserted every cycle pixel data is taken by encoder
      pixel_ready_o : out std_ulogic;
      pixel_i : in nsl_data.bytestream.byte_string(0 to 2);

      -- Data island insertion option. 
      di_valid_i : in std_ulogic := '0';
      di_ready_o : out std_ulogic;
      di_i : in work.hdmi.data_island_t := work.hdmi.di_null;
      
      tmds_o : out nsl_dvi.dvi.symbol_vector_t
      );
  end component;

end package encoder;
