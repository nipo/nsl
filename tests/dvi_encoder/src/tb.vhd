library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_video, nsl_color, nsl_data, nsl_line_coding, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.pixel_stream.all;
use nsl_color.rgb.all;
use nsl_data.text.all;

entity tb is
end entity;

architecture arch of tb is

  -- A frame small enough to walk in simulation, with blanking on
  -- both axes so the encoder has somewhere to put its sync.
  constant mode_c: mode_t := mode_build(16, 10, 2, 4,
                                        4, 5, 1, 2,
                                        60.0, '1', '1');
  constant geometry_c: geometry_t := geometry(mode_c);
  constant config_c: config_t := config(pixels => 1);
  constant bar_width_c: natural := 4;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  signal pixels_s: bus_t;
  signal synced_s: std_ulogic;
  signal tmds_s: nsl_dvi.dvi.symbol_vector_t;

  signal de_s, terc4_s: std_ulogic_vector(0 to 2);
  signal decoded_s: nsl_color.rgb.rgb24;
  type control_vector is array (natural range <>) of std_ulogic_vector(3 downto 0);
  signal control_s: control_vector(0 to 2);

  subtype channel_t is unsigned(7 downto 0);
  type channel_vector is array (natural range <>) of channel_t;
  signal channel_s: channel_vector(0 to 2);

  function bar_color(x: natural) return nsl_color.rgb.rgb24
  is
    constant index: natural := (x / bar_width_c) mod 8;
  begin
    return to_rgb24(rgb3_from_suv(std_ulogic_vector(to_unsigned(index, 3))));
  end function;

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

  bars: nsl_video.pattern.rgb_color_bars
    generic map(
      geometry_c => geometry_c,
      config_c => config_c,
      bar_width_c => bar_width_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      out_o => pixels_s.m,
      out_i => pixels_s.s
      );

  encoder: nsl_dvi.encoder.dvi_10_encoder
    generic map(
      config_c => config_c
      )
    port map(
      reset_n_i => reset_n_s,
      pixel_clock_i => clock_s,

      v_fp_m1_i => v_fp_m1(mode_c),
      v_sync_m1_i => v_sync_m1(mode_c),
      v_bp_m1_i => v_bp_m1(mode_c),
      v_act_m1_i => v_act_m1(mode_c),

      h_fp_m1_i => h_fp_m1(mode_c),
      h_sync_m1_i => h_sync_m1(mode_c),
      h_bp_m1_i => h_bp_m1(mode_c),
      h_act_m1_i => h_act_m1(mode_c),

      vsync_i => mode_c.v.sync,
      hsync_i => mode_c.h.sync,

      pixel_i => pixels_s.m,
      pixel_o => pixels_s.s,
      synced_o => synced_s,

      tmds_o => tmds_s
      );

  -- What a receiver would make of the signal
  channels: for i in 0 to 2
  generate
    decoder: nsl_line_coding.tmds.tmds_decoder
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        symbol_i => tmds_s(i),
        de_o => de_s(i),
        pixel_o => channel_s(i),
        terc4_o => terc4_s(i),
        control_o => control_s(i)
        );
  end generate;

  -- DVI carries blue on channel 0, green on 1, red on 2, and puts
  -- the syncs in the control words of channel 0.
  decoded_s <= nsl_color.rgb.rgb24'(r => channel_s(2),
                                    g => channel_s(1),
                                    b => channel_s(0));

  main: process is
    variable c: nsl_color.rgb.rgb24;
  begin
    done_s <= "0";

    wait until reset_n_s = '1';

    assert synced_s = '0'
      report "Encoder must not claim sync before the stream opened a frame"
      severity failure;

    wait until rising_edge(clock_s) and synced_s = '1';

    -- Two whole frames, taken from what comes back off the wire

    for frame in 0 to 1
    loop
      -- Vertical sync says where a frame starts, and the first
      -- active pixel after it is its top left one.
      wait until rising_edge(clock_s) and de_s(0) = '0' and control_s(0)(1) = '1';
      wait until rising_edge(clock_s) and control_s(0)(1) = '0';

      for y in 0 to geometry_c.height-1
      loop
        for x in 0 to geometry_c.width-1
        loop
          wait until rising_edge(clock_s) and de_s(0) = '1';

          assert de_s = "111"
            report "Channels disagree on whether pixel " & to_string(x)
            & "," & to_string(y) & " is video data"
            severity failure;

          c := decoded_s;
          assert c = bar_color(x)
            report "Frame " & to_string(frame) & " pixel " & to_string(x)
            & "," & to_string(y) & " came off the wire as "
            & to_string(std_ulogic_vector(c.r)) & " "
            & to_string(std_ulogic_vector(c.g)) & " "
            & to_string(std_ulogic_vector(c.b))
            severity failure;
        end loop;
      end loop;

      assert synced_s = '1'
        report "Encoder should hold sync through frame " & to_string(frame)
        severity failure;
    end loop;

    done_s <= "1";
    wait;
  end process;

end architecture;
