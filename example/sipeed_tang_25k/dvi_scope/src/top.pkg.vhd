library ieee, nsl_video;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_digilent, nsl_video;
use nsl_digilent.pmod.all;

package top is

  component main is
    generic (
      clock_i_hz_c : natural;
      mode_c : nsl_video.mode.mode_t
      );
    port (
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      switch_i : in std_ulogic_vector(0 to 3);
      button_i : in std_ulogic_vector(0 to 3);
      led_o: out std_ulogic_vector(0 to 1);

      pmod_dvi_o : out pmod_double_t
      );
  end component;

  component scope_controls is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      tick_i : in std_ulogic;

      run_i : in std_ulogic;
      freq_down_i : in std_ulogic;
      freq_up_i : in std_ulogic;
      pan_left_i : in std_ulogic;
      pan_right_i : in std_ulogic;

      phase_increment_o : out unsigned(15 downto 0);
      phase_origin_o : out unsigned(15 downto 0);
      periods_text_o : out string(1 to 5);
      phase_angle_o : out unsigned(8 downto 0)
      );
  end component;

  component scope_renderer is
    generic(
      geometry_c : nsl_video.mode.geometry_t;
      config_c : nsl_video.pixel_stream.config_t;
      color_count_l2_c : natural;
      background_color_c : natural;
      grid_color_c : natural;
      trace_color_c : natural;
      trace_amplitude_c : natural;
      grid_pitch_l2_c : natural := 6
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      enable_i : in std_ulogic := '1';

      out_o : out nsl_video.pixel_stream.master_t;
      out_i : in nsl_video.pixel_stream.slave_t;

      phase_increment_i : in unsigned(15 downto 0);
      phase_origin_i : in unsigned(15 downto 0);
      zoom_i : in std_ulogic := '0';
      grid_enable_i : in std_ulogic := '1'
      );
  end component;

  component scope_sine_rom is
    generic(
      address_width_c : natural;
      value_width_c : natural;
      amplitude_c : natural
      );
    port(
      clock_i : in std_ulogic;

      address_i : in unsigned(address_width_c-1 downto 0);
      value_o : out signed(value_width_c-1 downto 0)
      );
  end component;



end package;
