library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_data, nsl_digilent, nsl_logic,
  nsl_math, nsl_memory, nsl_sdio, nsl_sipeed, nsl_uart;
use nsl_data.bytestream.all;
use nsl_sdio.sdio.all;
use nsl_sdio.card.all;
use nsl_sdio.host.all;
use nsl_sdio.link.all;
use nsl_logic.bool.all;

-- Reads the first block of an SD card over and over and spells it out
-- on the serial port, identification first.
--
-- Every round puts four lines out: the card's identification, its
-- specific data, the count of blocks it holds, and then the block
-- itself, sixteen bytes to a line.  A formatted card has a partition
-- table there, which ends in 55aa, so what comes out says whether the
-- whole stack works against a real card rather than against a model.
--
-- The serial port is far slower than the bus, and nothing buffers a
-- block: the card's clock is taken away between bytes and given back,
-- which is what a host on this bus does when the fabric cannot keep
-- up.
entity boundary is
  port (
    clk_i: in std_ulogic;

    j4_io: inout nsl_digilent.pmod.pmod_double_t;

    uart_tx_o: out std_logic;

    -- Lit while a card is identified, and while a block is going out
    ready_led_o: out std_ulogic;
    done_led_o: out std_ulogic
    );
end boundary;

architecture arch of boundary is

  constant board_hz_c: natural := 50000000;
  constant clock_hz_c: natural := 100000000;
  constant uart_hz_c: natural := 115200;

  -- Rounds a second apart, so that a card put in later is picked up
  -- and the serial port has time to spell out what it says.
  constant round_cycle_c: natural := clock_hz_c;

  constant uart_divisor_c: unsigned
    := nsl_math.arith.to_unsigned_auto(clock_hz_c / uart_hz_c - 1);

  use nsl_clocking.pll.all;

  constant pll_config_c: pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(clock_hz_c));

  signal board_clock_s: std_ulogic;
  signal board_reset_n_s, startup_reset_n_s: std_ulogic;
  signal pll_clock_s: std_ulogic_vector(0 to pll_config_c.output_count - 1);
  signal clock_s, reset_n_s: std_ulogic;

  signal bus_o_s: sdio_master_o;
  signal bus_i_s: sdio_master_i;
  signal card_present_s: std_ulogic;
  -- Detect and write protect pins of the socket, then what the
  -- command and first data line idle at
  signal socket_s: std_ulogic_vector(3 downto 0);

  -- Whether the wires were seen moving since the last round, which is
  -- what tells a bus nobody answers on from one nothing goes out on
  signal seen_s: std_ulogic_vector(2 downto 0);

  -- The command line as it actually was, taken every capture_step_c
  -- fabric cycles from the moment a token starts going out.  At the
  -- bus clock identification runs at, this covers a command and the
  -- answer to it.
  constant capture_sample_count_c: natural := 1024;
  constant capture_step_c: natural := 32;

  type capture_state_t is (
    CAPTURE_ARM,
    CAPTURE_RUN,
    CAPTURE_HELD
    );

  type capture_regs_t is
  record
    state: capture_state_t;
    samples: std_ulogic_vector(capture_sample_count_c - 1 downto 0);
    left: natural range 0 to capture_sample_count_c;
    step: natural range 0 to capture_step_c - 1;
    out_left: natural range 0 to capture_sample_count_c / 8;
  end record;

  signal cr, crin: capture_regs_t;

  signal half_cycle_m1_s, sample_phase_s: unsigned(15 downto 0);
  signal width_s: bus_width_t;
  signal info_s: card_info_t;
  signal card_ready_s: std_ulogic;

  signal blk_req_s: block_req_t;
  signal blk_ack_s: block_ack_t;
  signal blk_rsp_s: block_rsp_t;

  signal dev_req_s, host_req_s: txn_req_t;
  signal dev_ack_s, host_ack_s: txn_ack_t;
  signal dev_rsp_s, host_rsp_s: txn_rsp_t;
  signal dev_stop_s: std_ulogic;

  signal rx_valid_s, rx_ready_s: std_ulogic;
  signal rx_data_s: byte;

  -- Bytes on their way to the serial port, and where a line ends
  signal out_valid_s, out_ready_s, out_break_s: std_ulogic;
  signal out_data_s: byte;

  -- What the probe has to say, and what the trace of the
  -- identification sequence has, which wins when both have something
  signal probe_valid_s, probe_ready_s, probe_break_s: std_ulogic;
  signal probe_data_s: byte;
  signal trace_valid_s, trace_ready_s: std_ulogic;
  signal trace_word_s: std_ulogic_vector(8 downto 0);
  signal trace_in_valid_s, trace_in_ready_s: std_ulogic;
  signal trace_in_word_s: std_ulogic_vector(8 downto 0);

  -- Command whose answer is being waited for, and what came back
  constant trace_byte_count_c: natural := 6;

  type trace_state_t is (
    TRACE_IDLE,
    TRACE_OUT
    );

  type trace_regs_t is
  record
    state: trace_state_t;
    index: unsigned(5 downto 0);
    record_bytes: std_ulogic_vector(8 * trace_byte_count_c - 1 downto 0);
    left: natural range 0 to trace_byte_count_c;
  end record;

  signal tr, trin: trace_regs_t;

  function status_code(status: cmd_status_t) return byte
  is
  begin
    case status is
      when CMD_OK => return x"00";
      when CMD_TIMEOUT => return x"01";
      when CMD_CRC_ERROR => return x"02";
      when CMD_FRAMING_ERROR => return x"03";
    end case;
  end function;

  signal uart_valid_s, uart_ready_s: std_ulogic;
  signal uart_data_s: std_ulogic_vector(7 downto 0);

  -- Identification, specific data and size, as they go out
  constant header_byte_count_c: natural := 36;

  type probe_state_t is (
    PROBE_MARK,
    PROBE_CAPTURE,
    PROBE_DELAY,
    PROBE_HEADER,
    PROBE_READ,
    PROBE_STATUS
    );

  type probe_regs_t is
  record
    state: probe_state_t;
    seen_clear: std_ulogic;
    -- Bytes of the block still to spell out, and whether the run it
    -- came from has answered
    block_left: natural range 0 to 512;
    run_done: std_ulogic;
    delay: unsigned(26 downto 0);
    header: std_ulogic_vector(8 * header_byte_count_c - 1 downto 0);
    header_left: natural range 0 to header_byte_count_c;
    status: block_status_t;
  end record;

  type format_state_t is (
    FORMAT_TAKE,
    FORMAT_HIGH,
    FORMAT_LOW,
    FORMAT_CR,
    FORMAT_LF
    );

  type format_regs_t is
  record
    state: format_state_t;
    data: byte;
    line_end: std_ulogic;
    column: natural range 0 to 15;
  end record;

  signal pr, prin: probe_regs_t;
  signal fr, frin: format_regs_t;

  function hex_digit(v: std_ulogic_vector) return std_ulogic_vector
  is
    constant n: unsigned(3 downto 0) := unsigned(v);
  begin
    if n < 10 then
      return std_ulogic_vector(x"30" + n);
    else
      return std_ulogic_vector(x"57" + n);
    end if;
  end function;

  function status_digit(status: block_status_t) return byte
  is
  begin
    case status is
      when BLOCK_OK => return x"00";
      when BLOCK_CMD_ERROR => return x"01";
      when BLOCK_DATA_ERROR => return x"02";
      when BLOCK_WRITE_ERROR => return x"03";
      when BLOCK_UNDERRUN => return x"04";
    end case;
  end function;

begin

  clock_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => board_clock_s
      );

  startup: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => board_clock_s,
      reset_n_o => startup_reset_n_s
      );

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => board_clock_s,
      data_i => startup_reset_n_s,
      data_o => board_reset_n_s
      );

  pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => pll_config_c
      )
    port map(
      clock_i => board_clock_s,
      clock_o => pll_clock_s,
      reset_n_i => board_reset_n_s,
      locked_o => reset_n_s
      );

  clock_s <= pll_clock_s(0);

  -- Both of the socket's own pins, as the connector carries them.
  -- Write protect is tied high on the board, so it says whether the
  -- pins are where they are thought to be, and detect says whether a
  -- card closed the switch.
  socket_s(0) <= to_x01(j4_io(7));
  socket_s(1) <= to_x01(j4_io(8));
  socket_s(2) <= bus_i_s.cmd;
  socket_s(3) <= bus_i_s.d(0);

  -- The command line only goes low when a token goes out, and the
  -- clock only moves when the host drives it.
  seen: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      if pr.seen_clear = '1' then
        seen_s <= (others => '0');
      else
        if bus_i_s.cmd = '0' then
          seen_s(0) <= '1';
        end if;

        if to_x01(j4_io(4)) = '0' then
          seen_s(1) <= '1';
        end if;

        if to_x01(j4_io(4)) = '1' then
          seen_s(2) <= '1';
        end if;
      end if;
    end if;

    if reset_n_s = '0' then
      seen_s <= (others => '0');
    end if;
  end process;

  pads: nsl_sipeed.pmod_tf_card.pmod_tf_card_pads
    generic map(
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      pmod_io => j4_io,

      sdio_i => bus_o_s,
      sdio_o => bus_i_s,

      card_present_o => card_present_s
      );

  device: nsl_sdio.card.card_block_device
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      info_i => info_s,

      req_i => blk_req_s,
      req_o => blk_ack_s,

      rsp_o => blk_rsp_s,

      host_req_o => dev_req_s,
      host_req_i => dev_ack_s,
      host_rsp_i => dev_rsp_s,
      host_stop_o => dev_stop_s
      );

  initializer: nsl_sdio.card.card_initializer
    generic map(
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,


      half_cycle_m1_o => half_cycle_m1_s,
      sample_phase_o => sample_phase_s,
      width_o => width_s,

      info_o => info_s,
      ready_o => card_ready_s,

      req_i => dev_req_s,
      req_o => dev_ack_s,
      rsp_o => dev_rsp_s,

      host_req_o => host_req_s,
      host_req_i => host_ack_s,
      host_rsp_i => host_rsp_s
      );

  host: nsl_sdio.host.host_controller
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sdio_o => bus_o_s,
      sdio_i => bus_i_s,

      half_cycle_m1_i => half_cycle_m1_s,
      sample_phase_i => sample_phase_s,
      width_i => width_s,
      -- A card is allowed a good fraction of a second to answer with
      -- data, which at this bus clock is a lot of periods.
      timeout_cycle_i => to_unsigned(1000000, 20),

      req_i => host_req_s,
      req_o => host_ack_s,
      stop_i => dev_stop_s,

      rsp_o => host_rsp_s,

      rx_valid_o => rx_valid_s,
      rx_data_o => rx_data_s,
      rx_ready_i => rx_ready_s
      );

  probe_regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      pr <= prin;
    end if;

    if reset_n_s = '0' then
      pr.state <= PROBE_MARK;
    end if;
  end process;

  probe_transition: process(pr, cr, card_ready_s, info_s, blk_rsp_s,
                            probe_ready_s, rx_valid_s) is
  begin
    prin <= pr;
    prin.seen_clear <= '0';

    case pr.state is
      when PROBE_MARK =>
        -- One line a round, whether or not there is a card, so that
        -- the serial port says something either way.
        if probe_ready_s = '1' then
          prin.seen_clear <= '1';

          if card_ready_s = '1' then
            prin.state <= PROBE_HEADER;
            prin.header <= info_s.cid & info_s.csd
                           & std_ulogic_vector(info_s.block_count);
            prin.header_left <= header_byte_count_c;
            prin.block_left <= 512;
            prin.run_done <= '0';
          else
            prin.state <= PROBE_CAPTURE;
          end if;
        end if;

      when PROBE_CAPTURE =>
        if probe_ready_s = '1' and cr.out_left = 1 then
          prin.state <= PROBE_DELAY;
          prin.delay <= to_unsigned(round_cycle_c, 27);
        end if;

      when PROBE_DELAY =>
        if pr.delay = 0 then
          prin.state <= PROBE_MARK;
        else
          prin.delay <= pr.delay - 1;
        end if;

      when PROBE_HEADER =>
        if probe_ready_s = '1' then
          prin.header <= pr.header(pr.header'left - 8 downto 0) & x"00";

          if pr.header_left = 1 then
            prin.state <= PROBE_READ;
          else
            prin.header_left <= pr.header_left - 1;
          end if;
        end if;

      when PROBE_READ =>
        -- The serial port is the slow end, so a run answers long
        -- before its last byte is out.  Both have to be through
        -- before the round is, or what is left over opens the next
        -- one.
        if blk_rsp_s.valid = '1' then
          prin.run_done <= '1';
          prin.status <= blk_rsp_s.status;
        end if;

        if rx_valid_s = '1' and probe_ready_s = '1' and pr.block_left /= 0 then
          prin.block_left <= pr.block_left - 1;
        end if;

        if pr.block_left = 0
          and (pr.run_done = '1' or blk_rsp_s.valid = '1')
        then
          prin.state <= PROBE_STATUS;
        end if;

      when PROBE_STATUS =>
        if probe_ready_s = '1' then
          prin.state <= PROBE_DELAY;
          prin.delay <= to_unsigned(round_cycle_c, 27);
        end if;
    end case;
  end process;

  probe_mealy: process(pr, cr, blk_ack_s, rx_valid_s, rx_data_s,
                      probe_ready_s, socket_s, card_ready_s) is
  begin
    blk_req_s <= block_idle;
    probe_valid_s <= '0';
    probe_data_s <= x"00";
    probe_break_s <= '0';
    rx_ready_s <= '0';

    case pr.state is
      when PROBE_MARK =>
        -- What the bus looks like from here: a card in the socket,
        -- and one that answered.
        probe_valid_s <= '1';
        probe_data_s <= seen_s & card_ready_s & socket_s;
        probe_break_s <= '1';

      when PROBE_CAPTURE =>
        probe_valid_s <= '1';
        probe_data_s <= cr.samples(cr.samples'left downto cr.samples'left - 7);

        -- Sixteen bytes to a line, and a last line whatever is left
        if cr.out_left mod 16 = 1 then
          probe_break_s <= '1';
        end if;

      when PROBE_HEADER =>
        probe_valid_s <= '1';
        probe_data_s <= pr.header(pr.header'left downto pr.header'left - 7);

        -- Identification, specific data and size each get a line.
        if pr.header_left = 21 or pr.header_left = 5
          or pr.header_left = 1
        then
          probe_break_s <= '1';
        end if;

      when PROBE_READ =>
        -- The request stands until it is taken, and the block flows
        -- through to the serial port from there.
        if blk_ack_s.ready = '1' then
          blk_req_s <= block_read(unsigned'(x"00000000"), 1);
        end if;

        probe_valid_s <= rx_valid_s;
        probe_data_s <= rx_data_s;
        rx_ready_s <= probe_ready_s;

      when PROBE_STATUS =>
        probe_valid_s <= '1';
        probe_data_s <= status_digit(pr.status);
        probe_break_s <= '1';

      when others =>
        null;
    end case;
  end process;

  -- Every command the identification sequence sends and what came of
  -- it, two bytes to a line.  It only runs until a card is ready, as
  -- what comes after is the block itself.
  trace_regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      tr <= trin;
    end if;

    if reset_n_s = '0' then
      tr.state <= TRACE_IDLE;
    end if;
  end process;

  trace_transition: process(tr, host_req_s, host_ack_s, host_rsp_s,
                            card_ready_s, trace_in_ready_s) is
  begin
    trin <= tr;

    if host_req_s.valid = '1' and host_ack_s.ready = '1' then
      trin.index <= host_req_s.index;
    end if;

    case tr.state is
      when TRACE_IDLE =>
        if host_rsp_s.valid = '1' and card_ready_s = '0' then
          trin.state <= TRACE_OUT;
          -- What was asked, what came of it, and what the card put in
          -- the answer.
          trin.record_bytes <= "00" & std_ulogic_vector(tr.index)
                               & status_code(host_rsp_s.cmd_status)
                               & host_rsp_s.payload(31 downto 0);
          trin.left <= trace_byte_count_c;
        end if;

      when TRACE_OUT =>
        if trace_in_ready_s = '1' then
          trin.record_bytes <= tr.record_bytes(tr.record_bytes'left - 8 downto 0)
                               & x"00";

          if tr.left = 1 then
            trin.state <= TRACE_IDLE;
          else
            trin.left <= tr.left - 1;
          end if;
        end if;
    end case;
  end process;

  trace_moore: process(tr) is
  begin
    case tr.state is
      when TRACE_IDLE =>
        trace_in_valid_s <= '0';
        trace_in_word_s <= (others => '0');

      when TRACE_OUT =>
        trace_in_valid_s <= '1';
        trace_in_word_s <= to_logic(tr.left = 1)
                           & tr.record_bytes(tr.record_bytes'left
                                             downto tr.record_bytes'left - 7);
    end case;
  end process;

  -- The serial port is slower than the sequence it reports on, so the
  -- trace waits its turn here rather than being dropped.
  trace_buffer: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => 64,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i(0) => clock_s,

      in_data_i => trace_in_word_s,
      in_valid_i => trace_in_valid_s,
      in_ready_o => trace_in_ready_s,

      out_data_o => trace_word_s,
      out_valid_o => trace_valid_s,
      out_ready_i => trace_ready_s
      );

  -- The probe goes first, so a capture comes out in one piece; the
  -- trace waits in its buffer until the probe has nothing to say.
  out_valid_s <= probe_valid_s or trace_valid_s;
  out_data_s <= probe_data_s when probe_valid_s = '1'
                else trace_word_s(7 downto 0);
  out_break_s <= probe_break_s when probe_valid_s = '1'
                 else trace_word_s(8);
  probe_ready_s <= out_ready_s;
  trace_ready_s <= out_ready_s and not probe_valid_s;

  capture_regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      cr <= crin;
    end if;

    if reset_n_s = '0' then
      cr.state <= CAPTURE_ARM;
    end if;
  end process;

  capture_transition: process(cr, pr, bus_i_s, probe_ready_s) is
  begin
    crin <= cr;

    case cr.state is
      when CAPTURE_ARM =>
        -- A token going out opens the window
        if bus_i_s.cmd = '0' then
          crin.state <= CAPTURE_RUN;
          crin.left <= capture_sample_count_c;
          crin.step <= 0;
        end if;

      when CAPTURE_RUN =>
        if cr.step /= 0 then
          crin.step <= cr.step - 1;
        else
          crin.step <= capture_step_c - 1;
          crin.samples <= cr.samples(cr.samples'left - 1 downto 0) & bus_i_s.cmd;

          if cr.left = 1 then
            crin.state <= CAPTURE_HELD;
            crin.out_left <= capture_sample_count_c / 8;
          else
            crin.left <= cr.left - 1;
          end if;
        end if;

      when CAPTURE_HELD =>
        if pr.state = PROBE_CAPTURE and probe_ready_s = '1' then
          crin.samples <= cr.samples(cr.samples'left - 8 downto 0) & x"00";

          if cr.out_left = 1 then
            crin.state <= CAPTURE_ARM;
          else
            crin.out_left <= cr.out_left - 1;
          end if;
        end if;
    end case;
  end process;

  format_regs: process(clock_s, reset_n_s) is
  begin
    if rising_edge(clock_s) then
      fr <= frin;
    end if;

    if reset_n_s = '0' then
      fr.state <= FORMAT_TAKE;
      fr.column <= 0;
    end if;
  end process;

  format_transition: process(fr, out_valid_s, out_data_s, out_break_s,
                             uart_ready_s) is
  begin
    frin <= fr;

    case fr.state is
      when FORMAT_TAKE =>
        if out_valid_s = '1' then
          frin.state <= FORMAT_HIGH;
          frin.data <= out_data_s;
          frin.line_end <= out_break_s;
        end if;

      when FORMAT_HIGH =>
        if uart_ready_s = '1' then
          frin.state <= FORMAT_LOW;
        end if;

      when FORMAT_LOW =>
        if uart_ready_s = '1' then
          if fr.line_end = '1' or fr.column = 15 then
            frin.state <= FORMAT_CR;
            frin.column <= 0;
          else
            frin.state <= FORMAT_TAKE;
            frin.column <= fr.column + 1;
          end if;
        end if;

      when FORMAT_CR =>
        if uart_ready_s = '1' then
          frin.state <= FORMAT_LF;
        end if;

      when FORMAT_LF =>
        if uart_ready_s = '1' then
          frin.state <= FORMAT_TAKE;
        end if;
    end case;
  end process;

  format_moore: process(fr) is
  begin
    out_ready_s <= '0';
    uart_valid_s <= '1';
    uart_data_s <= x"00";

    case fr.state is
      when FORMAT_TAKE =>
        out_ready_s <= '1';
        uart_valid_s <= '0';

      when FORMAT_HIGH =>
        uart_data_s <= hex_digit(fr.data(7 downto 4));

      when FORMAT_LOW =>
        uart_data_s <= hex_digit(fr.data(3 downto 0));

      when FORMAT_CR =>
        uart_data_s <= x"0d";

      when FORMAT_LF =>
        uart_data_s <= x"0a";
    end case;
  end process;

  serial: nsl_uart.serdes.uart_tx
    generic map(
      bit_count_c => 8,
      stop_count_c => 1,
      parity_c => nsl_uart.serdes.PARITY_NONE
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      divisor_i => uart_divisor_c,

      uart_o => uart_tx_o,

      data_i => uart_data_s,
      ready_o => uart_ready_s,
      valid_i => uart_valid_s
      );

  ready_led_o <= card_ready_s;
  done_led_o <= '1' when pr.state = PROBE_READ else '0';

end arch;
