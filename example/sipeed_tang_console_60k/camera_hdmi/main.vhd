library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_clocking, nsl_i2c, nsl_io, nsl_omnivision, nsl_sipeed,
  nsl_video, nsl_dvi, nsl_color;

-- A Sipeed PMOD-DVP camera (OV5640) shown on HDMI.
--
-- The sensor is powered up and set up to send 320x240 RGB565.
-- Frames land in a block RAM framebuffer at whatever rate the sensor
-- sends them, and are read back on HDMI at 1280x720p50, every pixel
-- repeated 4 times across and 3 times down.  Nothing ties the two
-- rates together, so a frame may show torn.
--
-- The camera spans two Pmods: its control connector on J7, its data
-- connector on J6, both with the camera's odd pins on the first row.
--
-- S1 shows the sensor test pattern while held.  Ready LED is lit once
-- the sensor is set up, done LED once HDMI output runs.
entity main is
  port (
    clk_i: in std_ulogic;

    s_n_i: in std_ulogic_vector(1 to 2);

    j6_io: inout std_logic_vector(1 to 8);
    j7_io: inout std_logic_vector(1 to 8);

    hdmi_ck_p_o: out std_logic;
    hdmi_ck_n_o: out std_logic;
    hdmi_dp_o: out std_logic_vector(0 to 2);
    hdmi_dn_o: out std_logic_vector(0 to 2);
    hdmi_psv_io: inout std_logic;
    hdmi_hpd_io: inout std_logic;
    hdmi_ddc_sda_io: inout std_logic;
    hdmi_ddc_scl_io: inout std_logic;

    done_led_o: inout std_logic;
    ready_led_o: inout std_logic
    );
end main;

architecture arch of main is

  constant clock_ext_hz_c : integer := 50e6;
  constant clock_cam_hz_c : integer := 24e6;

  constant mode_c : nsl_video.mode.mode_t := nsl_video.mode.mode_std_1280x720p50_c;

  constant fb_width_c : integer := 320;
  constant fb_height_c : integer := 240;
  constant fb_hscale_c : integer := 4;
  constant fb_vscale_c : integer := 3;
  constant fb_depth_c : integer := fb_width_c * fb_height_c;
  constant fb_addr_width_c : integer := 17;

  subtype fb_addr_t is unsigned(fb_addr_width_c-1 downto 0);
  subtype fb_word_t is std_ulogic_vector(15 downto 0);

  use nsl_clocking.pll.all;

  constant pll_config_c: pll_config_t := pll_config(
    input_hz => clock_ext_hz_c,
    o0 => pll_output(clock_cam_hz_c));

  -- See dvi_terminal for why 720p50 takes two PLLs.
  constant intermediate_hz_c : natural := 562_500_000;

  constant ref_config_c : pll_config_t := pll_config(
    input_hz => clock_ext_hz_c,
    o0 => pll_output(intermediate_hz_c,
                     routing => nsl_clocking.pll_backend.pll_routing_id("NONE")));

  constant video_config_c : pll_config_t := pll_config(
    input_hz => intermediate_hz_c,
    o0 => pll_output(nsl_video.mode.serial_clock_hz(mode_c)),
    o1 => pll_output(nsl_video.mode.pixel_clock_hz(mode_c)));

  constant geometry_c : nsl_video.mode.geometry_t := nsl_video.mode.geometry(mode_c);
  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);


  signal clock_ext_s, clock_cam_s, clock_pclk_s : std_ulogic;
  signal pll_clock_s : std_ulogic_vector(0 to pll_config_c.output_count - 1);
  signal video_clock_s : std_ulogic_vector(0 to video_config_c.output_count - 1);
  signal startup_reset_n_s, board_reset_n_s : std_ulogic;
  signal reset_n_s, pclk_reset_n_s : std_ulogic;

  signal dvi_ref_clock_s, dvi_ref_locked_s : std_ulogic;
  signal dvi_pixel_clock_s, dvi_serial_clock_s, dvi_reset_n_s : std_ulogic;
  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;
  signal dvi_clock_s : nsl_io.diff.diff_pair;
  signal dvi_data_s : nsl_io.diff.diff_pair_vector(0 to 2);
  signal pixel_s : nsl_video.pixel_stream.bus_t;
  signal synced_s : std_ulogic;

  signal sccb_cmd_s, sccb_rsp_s: nsl_bnoc.framed.framed_bus_t;
  signal button_n_s, button_s : std_ulogic;
  signal sensor_reset_n_s, sensor_power_down_s, sensor_ready_s : std_ulogic;

  signal i2c_o_s: nsl_i2c.i2c.i2c_o;
  signal i2c_i_s: nsl_i2c.i2c.i2c_i;


  signal dvp_vsync_s, dvp_href_s : std_ulogic;
  signal dvp_data_s : std_ulogic_vector(7 downto 0);
  signal word_valid_s, word_sof_s : std_ulogic;
  signal word_s : fb_word_t;

  signal fb_write_address_s, fb_read_address_s : fb_addr_t;
  signal fb_write_en_s : std_ulogic;
  signal fb_write_data_s, fb_read_data_s : fb_word_t;

  signal req_sof_s, req_sol_s, req_ready_s : std_ulogic;
  signal req_pixel_s : nsl_video.pixel_stream.pixel_t;

begin

  clock_ext_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  startup: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => clock_ext_s,
      reset_n_o => startup_reset_n_s
      );

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_ext_s,
      data_i => startup_reset_n_s,
      data_o => board_reset_n_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => board_reset_n_s,

      clock_o => pll_clock_s,
      locked_o => reset_n_s
      );

  clock_cam_s <= pll_clock_s(0);

  -- Sensor control

  sccb: nsl_i2c.transactor.transactor_framed_controller
    generic map(
      clock_i_hz_c => clock_ext_hz_c,
      stuck_timeout_half_cycles_c => 64
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => reset_n_s,

      i2c_o => i2c_o_s,
      i2c_i => i2c_i_s,

      cmd_i => sccb_cmd_s.req,
      cmd_o => sccb_cmd_s.ack,
      rsp_o => sccb_rsp_s.req,
      rsp_i => sccb_rsp_s.ack
      );

  sensor: nsl_omnivision.ov5640.ov5640_driver
    generic map(
      clock_i_hz_c => clock_ext_hz_c,
      width_c => fb_width_c,
      height_c => fb_height_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => reset_n_s,

      i2c_divisor_i => nsl_i2c.transactor.scl_divisor(clock_ext_hz_c, 100000),
      cmd_o => sccb_cmd_s.req,
      cmd_i => sccb_cmd_s.ack,
      rsp_i => sccb_rsp_s.req,
      rsp_o => sccb_rsp_s.ack,

      test_pattern_i => button_s,

      sensor_reset_n_o => sensor_reset_n_s,
      sensor_power_down_o => sensor_power_down_s,

      ready_o => sensor_ready_s
      );

  button_sync: nsl_clocking.async.async_sampler
    generic map(
      data_width_c => 1
      )
    port map(
      clock_i => clock_ext_s,
      data_i(0) => s_n_i(1),
      data_o(0) => button_n_s
      );

  button_s <= not button_n_s;


  camera: nsl_sipeed.pmod_dvp.pmod_dvp_pads
    port map(
      control_io => j7_io,
      data_io => j6_io,

      xclk_i => clock_cam_s,

      i2c_i => i2c_o_s,
      i2c_o => i2c_i_s,

      sensor_reset_n_i => sensor_reset_n_s,
      sensor_power_down_i => sensor_power_down_s,

      pclk_o => clock_pclk_s,
      vsync_o => dvp_vsync_s,
      href_o => dvp_href_s,
      data_o => dvp_data_s
      );

  -- Capture

  pclk_reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_pclk_s,
      data_i => reset_n_s,
      data_o => pclk_reset_n_s
      );

  receiver: nsl_video.dvp.dvp_receiver
    port map(
      pclk_i => clock_pclk_s,
      reset_n_i => pclk_reset_n_s,

      vsync_i => dvp_vsync_s,
      href_i => dvp_href_s,
      data_i => dvp_data_s,

      valid_o => word_valid_s,
      sof_o => word_sof_s,
      sol_o => open,
      data_o => word_s
      );

  writer: block is
    type regs_t is
    record
      address: fb_addr_t;
      write: boolean;
      data: fb_word_t;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(clock_pclk_s, pclk_reset_n_s) is
    begin
      if rising_edge(clock_pclk_s) then
        r <= rin;
      end if;

      if pclk_reset_n_s = '0' then
        r.address <= to_unsigned(fb_depth_c, fb_addr_width_c);
        r.write <= false;
      end if;
    end process;

    -- Address of a word is the one after the previous word's, so the
    -- address in r is that of the last word written.  A frame longer
    -- than the framebuffer stops at its end.
    transition: process(r, word_valid_s, word_sof_s, word_s) is
    begin
      rin <= r;

      rin.write <= false;

      if word_valid_s = '1' then
        rin.data <= word_s;
        if word_sof_s = '1' then
          rin.address <= (others => '0');
          rin.write <= true;
        elsif r.address < fb_depth_c - 1 then
          rin.address <= r.address + 1;
          rin.write <= true;
        else
          rin.address <= to_unsigned(fb_depth_c, fb_addr_width_c);
        end if;
      end if;
    end process;

    moore: process(r) is
    begin
      fb_write_address_s <= r.address;
      fb_write_data_s <= r.data;
      if r.write then
        fb_write_en_s <= '1';
      else
        fb_write_en_s <= '0';
      end if;
    end process;
  end block;

  framebuffer: block is
    type mem_t is array(0 to fb_depth_c-1) of fb_word_t;
    signal mem: mem_t;
  begin
    write_port: process(clock_pclk_s) is
    begin
      if rising_edge(clock_pclk_s) then
        if fb_write_en_s = '1' and fb_write_address_s < fb_depth_c then
          mem(to_integer(fb_write_address_s)) <= fb_write_data_s;
        end if;
      end if;
    end process;

    read_port: process(dvi_pixel_clock_s) is
    begin
      if rising_edge(dvi_pixel_clock_s) then
        if fb_read_address_s < fb_depth_c then
          fb_read_data_s <= mem(to_integer(fb_read_address_s));
        end if;
      end if;
    end process;
  end block;

  -- Display

  ref_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ref_config_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => board_reset_n_s,
      clock_o(0) => dvi_ref_clock_s,
      locked_o => dvi_ref_locked_s
      );

  video_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => video_config_c
      )
    port map(
      clock_i => dvi_ref_clock_s,
      reset_n_i => dvi_ref_locked_s,
      clock_o => video_clock_s,
      locked_o => dvi_reset_n_s
      );

  dvi_serial_clock_s <= video_clock_s(0);
  dvi_pixel_clock_s <= video_clock_s(1);

  reader: block is
    type regs_t is
    record
      line_base, address: fb_addr_t;
      column_rep: integer range 0 to fb_hscale_c-1;
      line_rep: integer range 0 to fb_vscale_c-1;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(dvi_pixel_clock_s, dvi_reset_n_s) is
    begin
      if rising_edge(dvi_pixel_clock_s) then
        r <= rin;
      end if;

      if dvi_reset_n_s = '0' then
        r.line_base <= (others => '0');
        r.address <= (others => '0');
        r.column_rep <= 0;
        r.line_rep <= 0;
      end if;
    end process;

    -- Frame opening leaves the line base one line before the first,
    -- so the first line opening steps to it like any other.
    transition: process(r, req_sof_s, req_sol_s, req_ready_s) is
      variable base: fb_addr_t;
    begin
      rin <= r;

      base := r.line_base;

      if req_sof_s = '1' then
        rin.line_base <= to_unsigned(2**fb_addr_width_c - fb_width_c, fb_addr_width_c);
        rin.line_rep <= fb_vscale_c - 1;
      elsif req_sol_s = '1' then
        if r.line_rep = fb_vscale_c - 1 then
          base := r.line_base + fb_width_c;
          rin.line_rep <= 0;
        else
          rin.line_rep <= r.line_rep + 1;
        end if;
        rin.line_base <= base;
        rin.address <= base;
        rin.column_rep <= 0;
      elsif req_ready_s = '1' then
        if r.column_rep = fb_hscale_c - 1 then
          rin.column_rep <= 0;
          rin.address <= r.address + 1;
        else
          rin.column_rep <= r.column_rep + 1;
        end if;
      end if;
    end process;

    -- The framebuffer answers a cycle after it is asked, so it is
    -- asked for the pixel the next cycle offers.
    fb_read_address_s <= rin.address;

    color: process(fb_read_data_s) is
      variable c: nsl_color.rgb.rgb24;
      variable w: unsigned(15 downto 0);
    begin
      w := unsigned(fb_read_data_s);
      c.r := w(15 downto 11) & w(15 downto 13);
      c.g := w(10 downto 5) & w(10 downto 9);
      c.b := w(4 downto 0) & w(4 downto 2);
      req_pixel_s <= nsl_video.pixel_stream.to_pixel(pixel_config_c, c);
    end process;
  end block;

  requester: nsl_video.raster.pixel_stream_requester
    generic map(
      geometry_c => geometry_c,
      config_c => pixel_config_c
      )
    port map(
      clock_i => dvi_pixel_clock_s,
      reset_n_i => dvi_reset_n_s,

      sof_o => req_sof_s,
      sol_o => req_sol_s,
      ready_o => req_ready_s,
      pixel_i => req_pixel_s,

      out_o => pixel_s.m,
      out_i => pixel_s.s
      );

  dvi_encoder: nsl_dvi.encoder.dvi_10_encoder
    generic map(
      config_c => pixel_config_c
      )
    port map(
      reset_n_i => dvi_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,

      v_fp_m1_i => nsl_video.mode.v_fp_m1(mode_c),
      v_sync_m1_i => nsl_video.mode.v_sync_m1(mode_c),
      v_bp_m1_i => nsl_video.mode.v_bp_m1(mode_c),
      v_act_m1_i => nsl_video.mode.v_act_m1(mode_c),

      h_fp_m1_i => nsl_video.mode.h_fp_m1(mode_c),
      h_sync_m1_i => nsl_video.mode.h_sync_m1(mode_c),
      h_bp_m1_i => nsl_video.mode.h_bp_m1(mode_c),
      h_act_m1_i => nsl_video.mode.h_act_m1(mode_c),

      vsync_i => mode_c.v.sync,
      hsync_i => mode_c.h.sync,

      pixel_i => pixel_s.m,
      pixel_o => pixel_s.s,
      synced_o => synced_s,

      tmds_o => tmds_s
      );

  driver: nsl_dvi.transceiver.dvi_driver
    generic map(
      driver_mode_c => "tlvds"
      )
    port map(
      reset_n_i => dvi_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,
      serial_clock_i => dvi_serial_clock_s,
      tmds_i => tmds_s,
      clock_o => dvi_clock_s,
      data_o => dvi_data_s
      );

  hdmi_ck_p_o <= dvi_clock_s.p;
  hdmi_ck_n_o <= dvi_clock_s.n;
  hdmi_lanes: for i in 0 to 2
  generate
    hdmi_dp_o(i) <= dvi_data_s(i).p;
    hdmi_dn_o(i) <= dvi_data_s(i).n;
  end generate;
  hdmi_hpd_io <= '0';
  hdmi_psv_io <= 'Z';
  hdmi_ddc_sda_io <= 'Z';
  hdmi_ddc_scl_io <= 'Z';

  ready_led_o <= sensor_ready_s;
  done_led_o <= synced_s;

end arch;
