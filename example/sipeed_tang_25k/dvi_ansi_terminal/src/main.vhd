library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_color, nsl_clocking, nsl_data, nsl_dvi, nsl_math, nsl_digilent, nsl_sipeed, nsl_indication, nsl_uart, nsl_memory, nsl_terminal, nsl_usb, nsl_amba, nsl_logic;
use nsl_color.rgb.all;
use nsl_digilent.pmod.all;
use nsl_indication.font.all;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;
use nsl_logic.bool.all;

-- Serial ANSI terminal on a DVI display, with a USB keyboard.
--
-- UART bytes at 115200 8N1 go through a FIFO into
-- nsl_terminal.ansi.ansi_terminal, which drives the user port of a
-- terminal_text_buffer. Escape sequences move the cursor, erase and
-- color text with the 16-color ANSI palette; scrolling rolls the
-- buffer through the text buffer row offset.
--
-- Keystrokes from a low-speed USB keyboard cross from their 12MHz
-- domain and go out on the UART transmitter, behind engine replies;
-- while the engine requests local echo (SRM), each keystroke is also
-- looped into its input stream.
entity main is
  generic (
    clock_i_hz_c : natural
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    uart_i : in std_ulogic;
    uart_o : out std_ulogic;
    led_o: out std_ulogic_vector(0 to 1);

    usb_c_o : out nsl_usb.io.usb_io_c;
    usb_s_i : in nsl_usb.io.usb_io_s;

    pmod_dvi_o : out pmod_double_t
    );
end entity;

architecture beh of main is

  -- Frame timings, XGA 1024x768 at 60Hz, 65MHz pixel clock, both
  -- syncs active low.
  constant v_fp_c   : integer := 3;
  constant v_sync_c : integer := 6;
  constant v_bp_c   : integer := 29;
  constant v_act_c  : integer := 768;
  constant h_fp_c   : integer := 24;
  constant h_sync_c : integer := 136;
  constant h_bp_c   : integer := 160;
  constant h_act_c  : integer := 1024;

  -- The matching clocks are set inside the PLL wrappers:
  -- stage1_pll: 50 MHz / 2 * 40 / 2 = 500 MHz reference,
  -- dvi_pll: 500 MHz / 20 * 52 = 1300 MHz VCO, / 4 = 325 MHz serial
  -- clock, / 20 = 65 MHz pixel clock.

  -- Translation to constants needed by components
  constant v_fp_m1_c   : unsigned(2-1 downto 0)  := to_unsigned(v_fp_c-1, 2);
  constant v_sync_m1_c : unsigned(3-1 downto 0)  := to_unsigned(v_sync_c-1, 3);
  constant v_bp_m1_c   : unsigned(5-1 downto 0)  := to_unsigned(v_bp_c-1, 5);
  constant v_act_m1_c  : unsigned(10-1 downto 0) := to_unsigned(v_act_c-1, 10);
  constant h_fp_m1_c   : unsigned(5-1 downto 0)  := to_unsigned(h_fp_c-1, 5);
  constant h_sync_m1_c : unsigned(8-1 downto 0)  := to_unsigned(h_sync_c-1, 8);
  constant h_bp_m1_c   : unsigned(8-1 downto 0)  := to_unsigned(h_bp_c-1, 8);
  constant h_act_m1_c  : unsigned(10-1 downto 0) := to_unsigned(h_act_c-1, 10);

  -- Interconnection
  signal blinker_s: unsigned(26 downto 0);

  signal dvi_ref_clock_s, dvi_pll_reset, dvi_pixel_clock_reset_n_s : std_ulogic;
  signal dvi_pixel_clock_s, dvi_serial_clock_s : std_ulogic;
  signal dvi_pixel_clock_unb_s, dvi_serial_clock_unb_s : std_ulogic;
  signal pll_locked_s, pll_reset_s: std_ulogic;

  signal tmds_s : nsl_dvi.dvi.symbol_vector_t;

  signal sol_s, sof_s, pixel_ready_s, pixel_valid_s : std_ulogic;
  signal pixel_s : nsl_color.rgb.rgb24;

begin

  blinker_counter: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      blinker_s <= (others => '0');
    elsif rising_edge(clock_i) then
      blinker_s <= blinker_s + 1;
    end if;
  end process;

  led_o <= std_ulogic_vector(blinker_s(blinker_s'left downto blinker_s'left-1));

  pll_reset_s <= not reset_n_i;

  clock: work.top.stage1_pll
    port map(
      clkin => clock_i,
      clkout0 => dvi_ref_clock_s,
      mdclk => clock_i,
      reset => pll_reset_s,
      lock => pll_locked_s
      );

  dvi_pll_reset <= not pll_locked_s;

  dvi_clock_gen: work.top.dvi_pll
    port map(
      reset    => dvi_pll_reset,
      clkin    => dvi_ref_clock_s,
      clkout0  => dvi_serial_clock_unb_s,
      clkout1  => dvi_pixel_clock_unb_s,
      lock     => dvi_pixel_clock_reset_n_s,
      mdclk    => clock_i
      );

  serial_clockbuf: nsl_clocking.distribution.clock_buffer
    port map (
      clock_i => dvi_serial_clock_unb_s,
      clock_o => dvi_serial_clock_s
      );

  pixel_clockbuf: nsl_clocking.distribution.clock_buffer
    port map (
      clock_i => dvi_pixel_clock_unb_s,
      clock_o => dvi_pixel_clock_s
      );

  driver: nsl_sipeed.pmod_dvi.pmod_dvi_output
    port map(
      reset_n_i => dvi_pixel_clock_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,
      serial_clock_i => dvi_serial_clock_s,
      tmds_i => tmds_s,
      pmod_o => pmod_dvi_o
      );

  dvi_encoder: nsl_dvi.encoder.dvi_10_encoder
    port map(
      reset_n_i => dvi_pixel_clock_reset_n_s,
      pixel_clock_i => dvi_pixel_clock_s,

      v_fp_m1_i => v_fp_m1_c,
      v_sync_m1_i => v_sync_m1_c,
      v_bp_m1_i => v_bp_m1_c,
      v_act_m1_i => v_act_m1_c,

      h_fp_m1_i => h_fp_m1_c,
      h_sync_m1_i => h_sync_m1_c,
      h_bp_m1_i => h_bp_m1_c,
      h_act_m1_i => h_act_m1_c,

      vsync_i => '0',
      hsync_i => '0',

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_valid_i => pixel_valid_s,
      pixel_i => pixel_s,

      tmds_o => tmds_s
      );

  term: block is
    constant font_c: font_t := nsl_indication.font_6x8.font_6x8_c;
    constant font_hscale_c: natural := 2;
    constant font_vscale_c: natural := 2;
    constant cell_width_c : natural := font_width(font_c) * font_hscale_c;
    constant cell_height_c : natural := font_height(font_c) * font_vscale_c;
    constant row_count_c : natural := v_act_c / cell_height_c;
    constant column_count_c : natural := h_act_c / cell_width_c;
    constant row_count_l2_c : natural := nsl_math.arith.log2(row_count_c);
    constant column_count_l2_c : natural := nsl_math.arith.log2(column_count_c);

    -- Standard ANSI colors and their bright variants
    constant palette_c : rgb24_vector(0 to 15) := (
      rgb24_black,
      (x"CD", x"00", x"00"),
      (x"00", x"CD", x"00"),
      (x"CD", x"CD", x"00"),
      (x"00", x"00", x"EE"),
      (x"CD", x"00", x"CD"),
      (x"00", x"CD", x"CD"),
      (x"E5", x"E5", x"E5"),
      (x"7F", x"7F", x"7F"),
      (x"FF", x"00", x"00"),
      (x"00", x"FF", x"00"),
      (x"FF", x"FF", x"00"),
      (x"5C", x"5C", x"FF"),
      (x"FF", x"00", x"FF"),
      (x"00", x"FF", x"FF"),
      rgb24_white
      );

    constant uart_divisor_c : unsigned
      := nsl_math.arith.to_unsigned_auto(clock_i_hz_c / 115200 - 1);

    signal uart_resync_s : std_ulogic_vector(0 downto 0);
    signal uart_data_s : std_ulogic_vector(7 downto 0);
    signal uart_valid_s : std_ulogic;

    signal char_data_s : std_ulogic_vector(7 downto 0);
    signal char_valid_s, char_ready_s : std_ulogic;

    signal reply_data_s : std_ulogic_vector(7 downto 0);
    signal reply_valid_s, reply_ready_s : std_ulogic;
    signal txfifo_data_s : std_ulogic_vector(7 downto 0);
    signal txfifo_valid_s, txfifo_ready_s : std_ulogic;

    -- USB keyboard, 12MHz domain
    signal usb_clock_s, usb_locked_s : std_ulogic;
    signal usb_reset_merged_s, usb_reset_n_s : std_ulogic;
    signal matched_s, kbd_clear_s : std_ulogic;
    signal modifiers_s : byte;
    signal keys_s : byte_string(0 to 5);
    signal report_valid_s : std_ulogic;
    signal event_s, repeated_s : keyboard_event_t;
    signal event_valid_s, event_ready_s : std_ulogic;
    signal repeated_valid_s, repeated_ready_s : std_ulogic;
    signal kchar_s : nsl_amba.axi4_stream.bus_t;
    signal kchar_byte_s : std_ulogic_vector(7 downto 0);
    signal kchar_valid_s, kchar_fifo_ready_s : std_ulogic;

    -- Keyboard bytes, terminal clock domain
    signal kbd_data_s : std_ulogic_vector(7 downto 0);
    signal kbd_valid_s : std_ulogic;
    signal local_echo_s : std_ulogic;

    -- Each keyboard byte goes to the transmitter, then, while local
    -- echo is requested, into the engine input stream.
    type kdisp_state_t is (
      KDISP_IDLE,
      KDISP_TX,
      KDISP_ECHO
      );

    type kdisp_regs_t is
    record
      state : kdisp_state_t;
      data : std_ulogic_vector(7 downto 0);
    end record;

    signal kr, krin : kdisp_regs_t;

    signal kbd_ready_s, ktx_valid_s : std_ulogic;
    signal kecho_valid_s : std_ulogic;

    signal uart_tx_data_s : std_ulogic_vector(7 downto 0);
    signal uart_tx_valid_s, uart_tx_ready_s : std_ulogic;
    signal fifo_in_data_s : std_ulogic_vector(7 downto 0);
    signal fifo_in_valid_s, fifo_in_ready_s : std_ulogic;

    signal offset_s : unsigned(row_count_l2_c-1 downto 0);
    signal term_row_s : unsigned(row_count_l2_c-1 downto 0);
    signal term_column_s : unsigned(column_count_l2_c-1 downto 0);
    signal term_enable_s, term_write_s, term_underline_s : std_ulogic;
    signal term_character_s : unsigned(7 downto 0);
    signal term_fg_s, term_bg_s : unsigned(3 downto 0);

    -- Buffer read-back to the engine, for the cursor and in-place
    -- editing
    signal rd_character_s : unsigned(7 downto 0);
    signal rd_underline_s : std_ulogic;
    signal rd_fg_s, rd_bg_s : unsigned(3 downto 0);
  begin

    -- uart_rx state machine needs a synchronous input, the pin is
    -- asynchronous
    rx_resync: nsl_clocking.async.async_sampler
      generic map(
        cycle_count_c => 2,
        data_width_c => 1
        )
      port map(
        clock_i => clock_i,
        data_i(0) => uart_i,
        data_o => uart_resync_s
        );

    rx: nsl_uart.serdes.uart_rx
      generic map(
        bit_count_c => 8,
        stop_count_c => 1,
        parity_c => nsl_uart.serdes.PARITY_NONE
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        divisor_i => uart_divisor_c,
        uart_i => uart_resync_s(0),

        data_o => uart_data_s,
        valid_o => uart_valid_s
        );

    -- The receiver cannot be backpressured, so it wins the input
    -- stream over an echoed keystroke; the echo side waits.
    fifo_in_valid_s <= uart_valid_s or kecho_valid_s;
    fifo_in_data_s <= uart_data_s when uart_valid_s = '1' else kr.data;

    input_fifo: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => 8,
        word_count_c => 512,
        clock_count_c => 1
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i(0) => clock_i,

        in_data_i => fifo_in_data_s,
        in_valid_i => fifo_in_valid_s,
        in_ready_o => fifo_in_ready_s,

        out_data_o => char_data_s,
        out_valid_o => char_valid_s,
        out_ready_i => char_ready_s
        );

    engine: nsl_terminal.ansi.ansi_terminal
      generic map(
        row_count_c => row_count_c,
        column_count_c => column_count_c,
        row_count_l2_c => row_count_l2_c,
        column_count_l2_c => column_count_l2_c,
        -- The text buffer registers its read output
        read_latency_c => 2
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        valid_i => char_valid_s,
        ready_o => char_ready_s,
        data_i => char_data_s,

        cursor_blink_i => blinker_s(24),

        reply_valid_o => reply_valid_s,
        reply_ready_i => reply_ready_s,
        reply_data_o => reply_data_s,

        bell_o => open,
        local_echo_o => local_echo_s,

        row_offset_o => offset_s,

        row_o => term_row_s,
        column_o => term_column_s,
        enable_o => term_enable_s,
        write_o => term_write_s,
        character_o => term_character_s,
        underline_o => term_underline_s,
        foreground_o => term_fg_s,
        background_o => term_bg_s,
        character_i => rd_character_s,
        underline_i => rd_underline_s,
        foreground_i => rd_fg_s,
        background_i => rd_bg_s
        );

    display: nsl_dvi.terminal.terminal_text_buffer
      generic map(
        row_count_l2_c => row_count_l2_c,
        column_count_l2_c => column_count_l2_c,
        character_count_l2_c => 8,
        color_palette_c => palette_c,
        font_c => font_c,
        underline_support_c => true,
        font_hscale_c => font_hscale_c,
        font_vscale_c => font_vscale_c
        )
      port map(
        video_clock_i => dvi_pixel_clock_s,
        video_reset_n_i => dvi_pixel_clock_reset_n_s,

        sof_i => sof_s,
        sol_i => sol_s,
        pixel_ready_i => pixel_ready_s,
        pixel_valid_o => pixel_valid_s,
        pixel_o => pixel_s,

        term_clock_i => clock_i,
        term_reset_n_i => reset_n_i,

        row_offset_i => offset_s,

        row_i => term_row_s,
        column_i => term_column_s,
        enable_i => term_enable_s,
        write_i => term_write_s,
        character_i => term_character_s,
        underline_i => term_underline_s,
        foreground_i => term_fg_s,
        background_i => term_bg_s,

        character_o => rd_character_s,
        underline_o => rd_underline_s,
        foreground_o => rd_fg_s,
        background_o => rd_bg_s
        );

    -- Reply path: engine answers -> FIFO -> host TX
    reply_fifo: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => 8,
        word_count_c => 32,
        clock_count_c => 1
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i(0) => clock_i,

        in_data_i => reply_data_s,
        in_valid_i => reply_valid_s,
        in_ready_o => reply_ready_s,

        out_data_o => txfifo_data_s,
        out_valid_o => txfifo_valid_s,
        out_ready_i => txfifo_ready_s
        );

    -- Engine replies win the transmitter over keystrokes.  A reply
    -- burst is written to its FIFO at engine speed, far faster than
    -- the transmitter drains it, so a keystroke cannot split a reply
    -- sequence in practice.
    uart_tx_valid_s <= txfifo_valid_s or ktx_valid_s;
    uart_tx_data_s <= txfifo_data_s when txfifo_valid_s = '1' else kr.data;
    txfifo_ready_s <= uart_tx_ready_s;

    tx: nsl_uart.serdes.uart_tx
      generic map(
        bit_count_c => 8,
        stop_count_c => 1,
        parity_c => nsl_uart.serdes.PARITY_NONE
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        divisor_i => uart_divisor_c,
        uart_o => uart_o,

        data_i => uart_tx_data_s,
        valid_i => uart_tx_valid_s,
        ready_o => uart_tx_ready_s
        );

    usb_pll: nsl_clocking.pll.pll_basic
      generic map(
        input_hz_c => clock_i_hz_c,
        output_hz_c => 12_000_000
        )
      port map(
        clock_i => clock_i,
        clock_o => usb_clock_s,
        reset_n_i => '1',
        locked_o => usb_locked_s
        );

    usb_reset_merged_s <= reset_n_i and usb_locked_s;

    usb_resync: nsl_clocking.async.async_edge
      port map(
        clock_i => usb_clock_s,
        data_i => usb_reset_merged_s,
        data_o => usb_reset_n_s
        );

    keyboard: nsl_usb.hid_host.hid_host_keyboard
      port map(
        reset_n_i => usb_reset_n_s,
        clock_i => usb_clock_s,

        bus_o => usb_c_o,
        bus_i => usb_s_i,

        identity_o => open,
        status_o => open,
        matched_o => matched_s,

        modifiers_o => modifiers_s,
        keys_o => keys_s,
        valid_o => report_valid_s
        );

    kbd_clear_s <= not matched_s;

    events: nsl_usb.hid_host.hid_host_keyboard_events
      port map(
        reset_n_i => usb_reset_n_s,
        clock_i => usb_clock_s,
        clear_i => kbd_clear_s,
        modifiers_i => modifiers_s,
        keys_i => keys_s,
        valid_i => report_valid_s,
        event_o => event_s,
        valid_o => event_valid_s,
        ready_i => event_ready_s
        );

    repeat: nsl_usb.hid_host.hid_host_keyboard_repeat
      port map(
        reset_n_i => usb_reset_n_s,
        clock_i => usb_clock_s,
        event_i => event_s,
        valid_i => event_valid_s,
        ready_o => event_ready_s,
        event_o => repeated_s,
        valid_o => repeated_valid_s,
        ready_i => repeated_ready_s
        );

    chars: nsl_usb.hid_host.hid_host_keyboard_chars
      port map(
        reset_n_i => usb_reset_n_s,
        clock_i => usb_clock_s,
        event_i => repeated_s,
        valid_i => repeated_valid_s,
        ready_o => repeated_ready_s,
        data_o => kchar_s.m,
        data_i => kchar_s.s
        );

    kchar_s.s <= nsl_amba.axi4_stream.accept(report_cfg_c,
                                             kchar_fifo_ready_s = '1');
    kchar_byte_s <= std_ulogic_vector(
      nsl_amba.axi4_stream.bytes(report_cfg_c, kchar_s.m)(0));
    kchar_valid_s <= to_logic(
      nsl_amba.axi4_stream.is_valid(report_cfg_c, kchar_s.m));

    kbd_cdc: nsl_memory.fifo.fifo_homogeneous
      generic map(
        data_width_c => 8,
        word_count_c => 16,
        clock_count_c => 2
        )
      port map(
        reset_n_i => usb_reset_n_s,
        clock_i(0) => usb_clock_s,
        clock_i(1) => clock_i,

        in_data_i => kchar_byte_s,
        in_valid_i => kchar_valid_s,
        in_ready_o => kchar_fifo_ready_s,

        out_data_o => kbd_data_s,
        out_valid_o => kbd_valid_s,
        out_ready_i => kbd_ready_s
        );

    kdisp_regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        kr <= krin;
      end if;
      if reset_n_i = '0' then
        kr.state <= KDISP_IDLE;
        kr.data <= (others => '0');
      end if;
    end process;

    kdisp_transition: process(kr, kbd_valid_s, kbd_data_s,
                              uart_tx_ready_s, txfifo_valid_s,
                              fifo_in_ready_s, uart_valid_s,
                              local_echo_s) is
    begin
      krin <= kr;

      case kr.state is
        when KDISP_IDLE =>
          if kbd_valid_s = '1' then
            krin.data <= kbd_data_s;
            krin.state <= KDISP_TX;
          end if;

        when KDISP_TX =>
          if uart_tx_ready_s = '1' and txfifo_valid_s = '0' then
            if local_echo_s = '1' then
              krin.state <= KDISP_ECHO;
            else
              krin.state <= KDISP_IDLE;
            end if;
          end if;

        when KDISP_ECHO =>
          if fifo_in_ready_s = '1' and uart_valid_s = '0' then
            krin.state <= KDISP_IDLE;
          end if;
      end case;
    end process;

    kdisp_moore: process(kr) is
    begin
      kbd_ready_s <= to_logic(kr.state = KDISP_IDLE);
      ktx_valid_s <= to_logic(kr.state = KDISP_TX);
      kecho_valid_s <= to_logic(kr.state = KDISP_ECHO);
    end process;

  end block;

end architecture;
