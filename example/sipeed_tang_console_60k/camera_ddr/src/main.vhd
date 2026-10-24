library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_clocking, nsl_i2c, nsl_io, nsl_omnivision, nsl_sipeed,
  nsl_video, nsl_dvi, nsl_amba, nsl_ext_ram;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.ddr3.all;

-- A Sipeed PMOD-DVP camera (OV5640) shown on HDMI through a DDR3
-- framebuffer.
--
-- The sensor is set up to send 1280x720 RGB565 at 15 frames a second.
-- Frames are written to DDR3 as they come, two bytes a pixel, into
-- one of three buffers.  HDMI runs 1280x720p50, reads back the newest
-- complete frame once per display frame and unpacks it to RGB888, so
-- a camera frame shows for three or four display frames, never torn.
--
-- The camera spans two Pmods: its control connector on J7, its data
-- connector on J6, both with the camera's odd pins on the first row.
-- The DDR3 part is the board's populated site, run as in the ddr3
-- example: DDR3-800 behind a 100 MHz, 128-bit AXI4 port.
--
-- S1 shows the sensor test pattern while held.  Ready LED is lit once
-- both the sensor and the memory are set up, done LED once HDMI output
-- runs.
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

    ddr3_ck_p_o: out std_ulogic;
    ddr3_ck_n_o: out std_ulogic;
    ddr3_cke_o: out std_ulogic;
    ddr3_cs_n_o: out std_ulogic;
    ddr3_ras_n_o: out std_ulogic;
    ddr3_cas_n_o: out std_ulogic;
    ddr3_we_n_o: out std_ulogic;
    ddr3_odt_o: out std_ulogic;
    ddr3_reset_n_o: out std_ulogic;
    ddr3_ba_o: out std_ulogic_vector(2 downto 0);
    ddr3_a_o: out std_ulogic_vector(15 downto 0);
    ddr3_0_dm_o: out std_ulogic_vector(1 downto 0);
    ddr3_0_dq_io: inout std_logic_vector(15 downto 0);
    ddr3_0_dqs_p_io: inout std_logic_vector(1 downto 0);
    ddr3_0_dqs_n_io: inout std_logic_vector(1 downto 0);

    done_led_o: inout std_logic;
    ready_led_o: inout std_logic
    );
end main;

architecture arch of main is

  use nsl_clocking.pll.all;

  constant clock_ext_hz_c : integer := 50e6;
  constant clock_cam_hz_c : integer := 24e6;

  constant mode_c : nsl_video.mode.mode_t := nsl_video.mode.mode_std_1280x720p50_c;
  constant geometry_c : nsl_video.mode.geometry_t := nsl_video.mode.geometry(mode_c);

  constant fb_geometry_c : nsl_video.mode.geometry_t := geometry_c;

  -- One RGB565 pixel a beat from the camera to the display's clock
  -- domain, RGB888 to the encoder.  A line is 2560 bytes, every line
  -- starts on a 4 KiB boundary, so no line straddles one.
  constant fb_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(
      pixels => 1,
      component_bits => 16,
      colorspace => nsl_video.pixel_stream.COLORSPACE_RGB565);
  constant pixel_config_c : nsl_video.pixel_stream.config_t
    := nsl_video.pixel_stream.config(pixels => 1);
  constant stream_config_c : nsl_amba.axi4_stream.config_t
    := nsl_video.pixel_stream.as_stream_config(fb_config_c);
  constant fb_line_bytes_c : integer
    := fb_geometry_c.width * nsl_video.pixel_stream.pixel_bytes(fb_config_c);
  constant fb_stride_c : integer := 4096;
  -- Three frame buffers, 2880 KiB used out of each 4 MiB.
  constant fb_base_c : integer := 0;
  constant fb_buffer_size_c : integer := 4 * 1024 * 1024;

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

  -- Memory side, what example/sipeed_tang_console_60k/ddr3 measured
  -- and validated on this board; see there for every number.
  constant tck_ps_c: natural := 2500;
  constant fast_hz_c: natural := 400000000;
  constant ram_hz_c: natural := fast_hz_c / 4;

  constant ram_config_c: pll_config_t := pll_config(
    input_hz => clock_ext_hz_c,
    o0 => pll_output(ram_hz_c),
    o1 => pll_output(fast_hz_c),
    o2 => pll_output(fast_hz_c, phase => (num => 1, den => 4)),
    o3 => pll_output(ram_hz_c, phase => (num => 1, den => 16)));

  constant board_c: nsl_ext_ram.ddr3_io.serdes_board_t := (
    read_offset => 70,
    read_tap => 47,
    write_slip => 7,
    dq_enable_lead => 0,
    dqs_enable_lead => 0,
    strobe_invert => false
    );

  constant part_c: dram_part_t := h5tq4g63efr_c;
  constant timing_c: dram_timing_t := timings(part_c, tck_ps_c);
  constant dfi_config_c: nsl_ext_ram.dfi.config_t := dfi_config(part_c);
  constant script_c: nsl_ext_ram.dram.init_script_t
    := nsl_ext_ram.dram.ddr3_init_script(part_c, timing_c,
                                         dfi_config_c.phase_count,
                                         rtt_nom_divisor => 4);
  constant axi_config_c: nsl_amba.axi4_mm.config_t := axi_config(part_c);
  constant lane_c: natural := part_c.dq_width / 8;
  constant beat_byte_c: natural := cycle_byte_count(part_c);

  subtype fb_address_t is unsigned(axi_config_c.address_width-1 downto 0);
  subtype fb_size_t is unsigned(15 downto 0);

  -- Two display frames with no frame shown restart the reader.
  constant watchdog_cycles_c : natural
    := 2 * nsl_video.mode.h_total(mode_c) * nsl_video.mode.v_total(mode_c);

  signal clock_ext_s, clock_cam_s, clock_pclk_s : std_ulogic;
  signal pll_clock_s : std_ulogic_vector(0 to pll_config_c.output_count - 1);
  signal video_clock_s : std_ulogic_vector(0 to video_config_c.output_count - 1);
  signal ram_clock_s : std_ulogic_vector(0 to ram_config_c.output_count - 1);
  signal startup_reset_n_s, board_reset_n_s : std_ulogic;
  signal reset_n_s, pclk_reset_n_s : std_ulogic;

  signal ram_s, fast_s, data_s, shifted_s : std_ulogic;
  signal ram_locked_s, ram_reset_n_s, dma_reset_n_s : std_ulogic;

  signal dvi_ref_clock_s, dvi_ref_locked_s : std_ulogic;
  signal dvi_pixel_clock_s, dvi_serial_clock_s, dvi_reset_n_s : std_ulogic;
  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;
  signal dvi_clock_s : nsl_io.diff.diff_pair;
  signal dvi_data_s : nsl_io.diff.diff_pair_vector(0 to 2);
  signal synced_s : std_ulogic;

  signal sccb_cmd_s, sccb_rsp_s: nsl_bnoc.framed.framed_bus_t;
  signal button_n_s, button_s : std_ulogic;
  signal sensor_reset_n_s, sensor_power_down_s, sensor_ready_s : std_ulogic;

  signal i2c_o_s: nsl_i2c.i2c.i2c_o;
  signal i2c_i_s: nsl_i2c.i2c.i2c_i;

  signal dvp_vsync_s, dvp_href_s : std_ulogic;
  signal dvp_data_s : std_ulogic_vector(7 downto 0);
  signal word_valid_s, word_sof_s, word_sol_s : std_ulogic;
  signal word_s : std_ulogic_vector(15 downto 0);

  -- Camera to memory
  signal capture_s, write_s : nsl_video.pixel_stream.bus_t;
  -- Memory to display
  signal read_s, read_sliced_s, display_in_s, display_s : nsl_video.pixel_stream.bus_t;

  signal frame_tick_s, display_request_s : std_ulogic;
  signal writer_base_s, reader_base_s : fb_address_t;
  signal writer_done_s, reader_start_s, reader_ready_s : std_ulogic;
  signal writer_status_s : nsl_video.vdma.frame_status_t;
  signal mem_ready_s, ram_ready_s : std_ulogic;

  signal writer_s, reader_s, dma_s, mem_s : nsl_amba.axi4_mm.bus_t;

  signal cmd_s: nsl_ext_ram.burst.cmd_t;
  signal cmd_ack_s: nsl_ext_ram.burst.cmd_ack_t;
  signal wdata_s: nsl_ext_ram.burst.wdata_t;
  signal wdata_ack_s: nsl_ext_ram.burst.wdata_ack_t;
  signal rdata_s: nsl_ext_ram.burst.rdata_t;
  signal rdata_ack_s: nsl_ext_ram.burst.rdata_ack_t;
  signal dfi_master_s: nsl_ext_ram.dfi.master_t;
  signal dfi_slave_s: nsl_ext_ram.dfi.slave_t;

  signal ram_ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0);
  signal ram_a_s: unsigned(nsl_ext_ram.ddr3.address_width(part_c) - 1 downto 0);
  signal ck_s: nsl_io.diff.diff_pair;
  signal dqs_out_s, dqs_n_out_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);
  signal dq_out_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal dq_in_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);
  -- Bench observation ports, unconstrained, so they need an actual.
  signal delay_mark_s, level_answer_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

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
      mode_c => nsl_omnivision.ov5640.MODE_720P15,
      width_c => fb_geometry_c.width,
      height_c => fb_geometry_c.height
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

  -- Capture, in the sensor's pixel clock

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
      sol_o => word_sol_s,
      data_o => word_s
      );

  -- The sensor cannot be held back, and a beat not taken in time
  -- aborts the frame.  The FIFO right behind takes the writer waiting
  -- on the memory: tens of microseconds of camera line.
  to_stream: nsl_video.dvp.dvp_to_pixel_stream
    generic map(
      config_c => fb_config_c,
      geometry_c => fb_geometry_c
      )
    port map(
      clock_i => clock_pclk_s,
      reset_n_i => pclk_reset_n_s,
      valid_i => word_valid_s,
      sof_i => word_sof_s,
      sol_i => word_sol_s,
      data_i => word_s,
      out_o => capture_s.m,
      out_i => capture_s.s,
      overflow_o => open
      );

  capture_fifo: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => stream_config_c,
      depth_c => 512,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => clock_pclk_s,
      clock_i(1) => ram_s,
      reset_n_i => dma_reset_n_s,
      in_i => capture_s.m,
      in_o => capture_s.s,
      in_free_o => open,
      out_o => write_s.m,
      out_i => write_s.s,
      out_available_o => open
      );

  -- Framebuffer DMAs, in the memory clock

  -- Neither DMA may see the bus before the core is through its
  -- power-up sequence, and the core never goes back to it without a
  -- reset of its own.
  dma_reset: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      ram_ready_s <= '0';
    elsif rising_edge(ram_s) then
      if mem_ready_s = '1' then
        ram_ready_s <= '1';
      end if;
    end if;
  end process;

  dma_reset_n_s <= ram_ready_s;

  writer: nsl_video.vdma.vdma_writer
    generic map(
      mem_config_c => axi_config_c,
      stream_config_c => fb_config_c
      )
    port map(
      clock_i => ram_s,
      reset_n_i => dma_reset_n_s,
      base_i => writer_base_s,
      stride_i => to_unsigned(fb_stride_c, fb_address_t'length),
      max_height_i => to_unsigned(fb_geometry_c.height, fb_size_t'length),
      start_o => open,
      done_o => writer_done_s,
      status_o => writer_status_s,
      stream_i => write_s.m,
      stream_o => write_s.s,
      mem_o => writer_s.m,
      mem_i => writer_s.s
      );

  -- The display always gets the newest complete camera frame, and
  -- the camera never writes the buffer being displayed.  Before the
  -- first complete frame, the display shows whatever the first buffer
  -- holds.
  buffering: nsl_video.vdma.vdma_triple_buffer
    generic map(
      address_width_c => fb_address_t'length,
      base_c => to_unsigned(fb_base_c, fb_address_t'length),
      buffer_size_c => to_unsigned(fb_buffer_size_c, fb_address_t'length)
      )
    port map(
      clock_i => ram_s,
      reset_n_i => dma_reset_n_s,
      writer_base_o => writer_base_s,
      writer_done_i => writer_done_s,
      writer_status_i => writer_status_s,
      display_request_i => display_request_s,
      reader_base_o => reader_base_s,
      reader_start_o => reader_start_s,
      reader_ready_i => reader_ready_s,
      frame_dropped_o => open,
      frame_repeated_o => open,
      frame_skipped_o => open
      );

  reader: nsl_video.vdma.vdma_reader
    generic map(
      mem_config_c => axi_config_c,
      stream_config_c => fb_config_c
      )
    port map(
      clock_i => ram_s,
      reset_n_i => dma_reset_n_s,
      base_i => reader_base_s,
      stride_i => to_unsigned(fb_stride_c, fb_address_t'length),
      width_i => to_unsigned(fb_line_bytes_c, fb_size_t'length),
      height_i => to_unsigned(fb_geometry_c.height, fb_size_t'length),
      start_i => reader_start_s,
      ready_o => reader_ready_s,
      done_o => open,
      status_o => open,
      mem_o => reader_s.m,
      mem_i => reader_s.s,
      stream_o => read_s.m,
      stream_i => read_s.s
      );

  -- The writer only ever uses the write channels and the reader only
  -- ever uses the read channels, so each channel has a single master
  -- and the two merge into one port with no arbitration: both DMAs
  -- issue ID 0 and rely on in-order responses, which a single
  -- direction from a single master gets.  The adapter behind serves
  -- one transaction at a time and arbitrates between a pending write
  -- and a pending read.
  dma_s.m.aw <= writer_s.m.aw;
  dma_s.m.w <= writer_s.m.w;
  dma_s.m.b <= writer_s.m.b;
  dma_s.m.ar <= reader_s.m.ar;
  dma_s.m.r <= reader_s.m.r;
  writer_s.s <= dma_s.s;
  reader_s.s <= dma_s.s;

  -- Memory controller

  ram_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ram_config_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => startup_reset_n_s,
      clock_o => ram_clock_s,
      locked_o => ram_locked_s
      );

  -- Straight off the block, with no buffer in between: the
  -- serialisers want a settled relationship between their fast and
  -- parallel clocks.
  ram_s <= ram_clock_s(0);
  fast_s <= ram_clock_s(1);
  data_s <= ram_clock_s(2);
  shifted_s <= ram_clock_s(3);

  memory_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => ram_s,
      data_i => ram_locked_s,
      data_o => ram_reset_n_s
      );

  mem_s.m.aw <= dma_s.m.aw;
  mem_s.m.w <= dma_s.m.w;
  mem_s.m.b <= dma_s.m.b;
  mem_s.m.ar <= dma_s.m.ar;
  dma_s.s.aw <= mem_s.s.aw;
  dma_s.s.w <= mem_s.s.w;
  dma_s.s.b <= mem_s.s.b;
  dma_s.s.ar <= mem_s.s.ar;

  read_stage: nsl_amba.mm_fifo.axi4_mm_r_slice
    generic map(
      config_c => axi_config_c
      )
    port map(
      clock_i => ram_s,
      reset_n_i => ram_reset_n_s,
      in_i => mem_s.s.r,
      in_o => mem_s.m.r,
      out_o => dma_s.s.r,
      out_i => dma_s.m.r
      );

  adapter: nsl_ext_ram.frontend.axi4_mm_burst_adapter
    generic map(
      axi_config_c => axi_config_c,
      cycle_byte_count_c => beat_byte_c,
      burst_cycle_count_c => 1
      )
    port map(
      clock_i => ram_s,
      reset_n_i => ram_reset_n_s,
      axi_i => mem_s.m,
      axi_o => mem_s.s,
      cmd_o => cmd_s,
      cmd_i => cmd_ack_s,
      wdata_o => wdata_s,
      wdata_i => wdata_ack_s,
      rdata_i => rdata_s,
      rdata_o => rdata_ack_s,
      ready_i => mem_ready_s
      );

  core: nsl_ext_ram.dram.dram_core
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      script_c => script_c,
      burst_length_l2_c => part_c.prefetch_l2,
      keep_row_open_c => true,
      read_ahead_c => 13,
      write_overlap_c => true
      )
    port map(
      clock_i => ram_s,
      reset_n_i => ram_reset_n_s,
      cmd_i => cmd_s,
      cmd_o => cmd_ack_s,
      wdata_i => wdata_s,
      wdata_o => wdata_ack_s,
      rdata_o => rdata_s,
      rdata_i => rdata_ack_s,
      ready_o => mem_ready_s,
      dfi_o => dfi_master_s,
      dfi_i => dfi_slave_s
      );

  phy: nsl_ext_ram.ddr3_io.ddr3_phy_serdes
    generic map(
      part_c => part_c,
      timing_c => timing_c,
      dfi_config_c => dfi_config_c,
      board_c => board_c,
      shift_strobe_c => true,
      early_address_c => true
      )
    port map(
      clock_i => ram_s,
      fast_clock_i => fast_s,
      data_clock_i => data_s,
      shifted_clock_i => shifted_s,
      delay_ref_clock_i => ram_s,
      reset_n_i => ram_reset_n_s,

      dfi_i => dfi_master_s,
      dfi_o => dfi_slave_s,

      dq_delay_shift_i => (dq_in_s'range => '0'),
      dq_delay_mark_o => delay_mark_s,
      write_level_answer_o => level_answer_s,

      ck_o => ck_s,
      cke_o => ddr3_cke_o,
      cs_n_o => ddr3_cs_n_o,
      ras_n_o => ddr3_ras_n_o,
      cas_n_o => ddr3_cas_n_o,
      we_n_o => ddr3_we_n_o,
      ba_o => ram_ba_s,
      a_o => ram_a_s,
      -- The core never asks for termination, so it is held asserted, as
      -- the ddr3 example does.  The part turns its own off while it
      -- drives.
      odt_o => open,
      ram_reset_n_o => ddr3_reset_n_o,

      dm_o => ddr3_0_dm_o,
      dqs_o => dqs_out_s,
      dqs_n_o => dqs_n_out_s,
      dq_o => dq_out_s,
      dq_i => dq_in_s
      );

  ddr3_ck_p_o <= ck_s.p;
  ddr3_ck_n_o <= ck_s.n;
  ddr3_odt_o <= '1';
  ddr3_ba_o <= std_ulogic_vector(ram_ba_s);
  -- A15 addresses nothing at this density, it is held rather than left
  -- floating.
  ddr3_a_o(ram_a_s'length - 1 downto 0) <= std_ulogic_vector(ram_a_s);
  ddr3_a_o(ddr3_a_o'left downto ram_a_s'length) <= (others => '0');

  dq_pads: for i in 0 to part_c.dq_width - 1
  generate
    ddr3_0_dq_io(i) <= nsl_io.io.to_logic(dq_out_s(i));
    dq_in_s(i) <= to_x01(ddr3_0_dq_io(i));
  end generate;

  strobe_pads: for i in 0 to lane_c - 1
  generate
    ddr3_0_dqs_p_io(i) <= nsl_io.io.to_logic(dqs_out_s(i));
    ddr3_0_dqs_n_io(i) <= nsl_io.io.to_logic(dqs_n_out_s(i));
  end generate;

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

  -- The FIFO's ready reaches every register of the reader's gearbox,
  -- which does not fit a memory cycle without a register in between.
  read_slice: nsl_amba.stream_fifo.axi4_stream_slice
    generic map(
      config_c => stream_config_c
      )
    port map(
      clock_i => ram_s,
      reset_n_i => dma_reset_n_s,
      in_i => read_s.m,
      in_o => read_s.s,
      out_o => read_sliced_s.m,
      out_i => read_sliced_s.s
      );

  -- The reader prefetches into its own buffer, more than a line deep,
  -- and waits there through blanking.  This FIFO only crosses clocks.
  display_fifo: nsl_amba.stream_fifo.axi4_stream_fifo
    generic map(
      config_c => stream_config_c,
      depth_c => 32,
      clock_count_c => 2
      )
    port map(
      clock_i(0) => ram_s,
      clock_i(1) => dvi_pixel_clock_s,
      reset_n_i => dma_reset_n_s,
      in_i => read_sliced_s.m,
      in_o => read_sliced_s.s,
      in_free_o => open,
      out_o => display_in_s.m,
      out_i => display_in_s.s,
      out_available_o => open
      );

  unpacker: nsl_video.colorspace.rgb565_unpacker
    generic map(
      in_config_c => fb_config_c,
      out_config_c => pixel_config_c
      )
    port map(
      clock_i => dvi_pixel_clock_s,
      reset_n_i => dvi_reset_n_s,
      in_i => display_in_s.m,
      in_o => display_in_s.s,
      out_o => display_s.m,
      out_i => display_s.s
      );

  -- One reader frame per display frame.
  --
  -- The encoder holds the first beat of a frame until its raster opens
  -- a frame, and shows it from there.  A read started as soon as the
  -- previous frame's last beat is taken has the whole vertical
  -- blanking to bring the next frame's first beat in, and paces the
  -- reader to the display without the raster telling anything.
  --
  -- When the display runs dry in the middle of a frame, the encoder
  -- drops what is left of the reader's frame up to its last beat,
  -- which then starts the next read, and the next display frame is in
  -- sync again.  A frame start lost on the way -- the memory not up
  -- when it was asked, or nothing in flight at reset -- would leave
  -- nothing to restart from, so a frame is also asked for when none
  -- has been shown for two display frames.  A request while the
  -- reader is busy is ignored, so at worst a request is lost and the
  -- watchdog asks again.
  frame_sync: block is
    type regs_t is
    record
      watchdog: natural range 0 to watchdog_cycles_c-1;
      tick: boolean;
    end record;

    signal r, rin: regs_t;
  begin
    regs: process(dvi_pixel_clock_s, dvi_reset_n_s) is
    begin
      if rising_edge(dvi_pixel_clock_s) then
        r <= rin;
      end if;

      if dvi_reset_n_s = '0' then
        r.watchdog <= 0;
        r.tick <= false;
      end if;
    end process;

    transition: process(r, display_s) is
    begin
      rin <= r;

      rin.tick <= false;

      if nsl_video.pixel_stream.is_taken(pixel_config_c, display_s.m, display_s.s)
        and nsl_video.pixel_stream.is_eof(pixel_config_c, display_s.m) then
        rin.tick <= true;
        rin.watchdog <= watchdog_cycles_c-1;
      elsif r.watchdog = 0 then
        rin.tick <= true;
        rin.watchdog <= watchdog_cycles_c-1;
      else
        rin.watchdog <= r.watchdog - 1;
      end if;
    end process;

    moore: process(r) is
    begin
      if r.tick then
        frame_tick_s <= '1';
      else
        frame_tick_s <= '0';
      end if;
    end process;
  end block;

  frame_cross: nsl_clocking.interdomain.interdomain_tick
    port map(
      input_clock_i => dvi_pixel_clock_s,
      output_clock_i => ram_s,
      input_reset_n_i => dvi_reset_n_s,
      tick_i => frame_tick_s,
      tick_o => display_request_s
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
      pixel_i => display_s.m,
      pixel_o => display_s.s,
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

  -- Two domains meet on a pin no logic reads.
  ready_led_o <= sensor_ready_s and ram_ready_s;
  done_led_o <= synced_s;

end arch;
