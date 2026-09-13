library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_line_coding, nsl_data, nsl_video, work;

-- DVI protocol encoder.
-- Also handles data islands that are used by HDMI.
package encoder is

  -- Stream component each TMDS channel carries.
  --
  -- A colourspace names its components in one order and the wire
  -- sends them in another: RGB names red first and channel 0 carries
  -- blue, YCbCr names luma first and channel 0 carries Cb.
  type channel_map_t is array (natural range 0 to 2) of natural range 0 to 3;
  constant channel_map_rgb_c: channel_map_t := (2, 1, 0);
  constant channel_map_ycbcr_c: channel_map_t := (1, 0, 2);

  -- Channel bytes of a stream pixel.  Components wider than a byte
  -- keep their top eight bits.
  function channel_bytes(cfg: nsl_video.pixel_stream.config_t;
                         channel_map: channel_map_t;
                         pixel: nsl_video.pixel_stream.pixel_t)
    return nsl_data.bytestream.byte_string;

  -- What goes out in place of a pixel the stream did not hold.  Full
  -- scale on the middle channel, which shows as green on an RGB
  -- link: a tell, not a colour.
  constant channel_bytes_starved_c: nsl_data.bytestream.byte_string(0 to 2)
    := (x"00", x"ff", x"00");

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

  -- Sends a pixel stream out as a DVI signal.
  --
  -- The wire cannot wait, so the raster here owns the timing and the
  -- stream follows it: the encoder locks onto the first frame the
  -- stream opens and hands its pixels out from there.  synced_o
  -- states whether it does.  While it does not, blanking colour
  -- goes out in place of pixels.
  component dvi_10_encoder is
    generic(
      config_c : nsl_video.pixel_stream.config_t;
      channel_map_c : channel_map_t := channel_map_rgb_c
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

      pixel_i : in nsl_video.pixel_stream.master_t;
      pixel_o : out nsl_video.pixel_stream.slave_t;

      synced_o : out std_ulogic;

      tmds_o : out work.dvi.symbol_vector_t
      );
  end component;

end package encoder;

package body encoder is

  function channel_bytes(cfg: nsl_video.pixel_stream.config_t;
                         channel_map: channel_map_t;
                         pixel: nsl_video.pixel_stream.pixel_t)
    return nsl_data.bytestream.byte_string
  is
    variable ret: nsl_data.bytestream.byte_string(0 to 2);
    variable v: nsl_video.pixel_stream.component_t;
  begin
    for channel in 0 to 2
    loop
      v := pixel(channel_map(channel));

      if cfg.component_bits >= 8 then
        ret(channel) := nsl_data.bytestream.byte(
          v(cfg.component_bits-1 downto cfg.component_bits-8));
      else
        ret(channel) := nsl_data.bytestream.byte(
          resize(shift_left(v, 8 - cfg.component_bits), 8));
      end if;
    end loop;

    return ret;
  end function;

end package body;
