library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Pixel stream blenders
package blender is

  -- Blends two color-index pixel streams into one.  An overlay pixel
  -- matching key_color_c is replaced by the underlay pixel, any other
  -- overlay pixel is passed through.  One beat is consumed from both
  -- inputs for every output beat, keeping the streams in lockstep.
  --
  -- The datapath is combinational.  Typical usage is between two
  -- color-index generators and a shared
  -- nsl_dvi.colormap.dvi_colormap_lookup instance, with key_color_c
  -- reserved as the transparent entry of the overlay.
  component dvi_blender_color_key is
    generic(
      color_count_l2_c: natural;
      key_color_c: natural := 0
      );
    port(
      overlay_ready_o : out std_ulogic;
      overlay_valid_i : in std_ulogic;
      overlay_color_i : in unsigned(color_count_l2_c-1 downto 0);

      underlay_ready_o : out std_ulogic;
      underlay_valid_i : in std_ulogic;
      underlay_color_i : in unsigned(color_count_l2_c-1 downto 0);

      color_ready_i : in std_ulogic;
      color_valid_o : out std_ulogic;
      color_o : out unsigned(color_count_l2_c-1 downto 0)
      );
  end component;

end package;
