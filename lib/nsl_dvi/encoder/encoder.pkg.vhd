library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_line_coding, nsl_data, work;

-- DVI protocol encoder.
-- Also handles data islands that are used by HDMI.
package encoder is

  type period_t is (
    PERIOD_CONTROL,
    PERIOD_DI_PRE,
    PERIOD_DI_GUARD,
    PERIOD_DI_DATA,
    PERIOD_VIDEO_PRE,
    PERIOD_VIDEO_GUARD,
    PERIOD_VIDEO_DATA
    );
  
  component source_stream_encoder is
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;

      period_i: in period_t;

      -- Pixel data, only valid if period_i = PERIOD_VIDEO_DATA
      pixel_i : in nsl_data.bytestream.byte_string(0 to 2);

      -- Syncs, valid for any non-video period
      -- Maps to channel 0, bit 0 during data island
      hsync_i : in std_ulogic;
      -- Maps to channel 0, bit 1 during data island
      vsync_i : in std_ulogic;

      di_hdr_i : in std_ulogic_vector(1 downto 0) := "00";
      di_data_i : in std_ulogic_vector(7 downto 0) := "00000000";

      tmds_o : out work.dvi.symbol_vector_t
      );
  end component;

  component dvi_10_encoder is
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
      pixel_valid_i : in std_ulogic := '1';
      pixel_i : in nsl_color.rgb.rgb24;
      
      tmds_o : out work.dvi.symbol_vector_t
      );
  end component;

end package encoder;
