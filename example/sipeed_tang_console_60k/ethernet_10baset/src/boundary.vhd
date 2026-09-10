library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_hwdep, nsl_clocking, nsl_uart, nsl_mii, nsl_bnoc, nsl_inet,
  nsl_digilent, nsl_sipeed;
use nsl_uart.serdes.all;
use nsl_mii.flit.all;
use nsl_bnoc.committed.all;

-- 10BASE-T receive bring-up on the ethernet PMOD, no external Phy.
--
-- The MAU transmits normal link pulses so the partner parallel-detects
-- 10BASE-T half-duplex.  Received frames go through the FCS check of
-- the mac layer, then the head of each frame is dumped on the UART.
--
-- The UART is orders of magnitude slower than the line, so the dump
-- path never backpressures the receive path: the head of a frame is
-- snapshot at line rate, and printed while subsequent frames are
-- counted but not printed.  Frame counters therefore tell the truth
-- about the line even when most frames go unprinted.
--
-- The PMOD wrapper owns the pads and the fabric MAU; pinout.cst
-- carries the differential receive type and the bias pulls it needs.
entity boundary is
  port (
    clk_i: in std_ulogic;

    pmod_io: inout nsl_digilent.pmod.pmod_double_t;

    uart_tx_o: out std_ulogic;
    uart_rx_i: in std_ulogic;

    done_led_o: out std_ulogic;
    ready_led_o: out std_ulogic
    );
end boundary;

architecture arch of boundary is

  constant clock_ext_hz_c: integer := 50000000;
  constant clock_hz_c: integer := 100000000;
  constant baudrate_c: integer := 115200;
  constant divisor_c: unsigned(15 downto 0)
    := to_unsigned((clock_hz_c + baudrate_c / 2) / baudrate_c - 1, 16);

  -- Frame head kept for the dump
  constant snap_len_c: integer := 16;
  -- "l=xxx G\r\n"
  constant tail_len_c: integer := 9;
  -- "=Lx Px n=xxxx g=xxxx\n"
  constant status_len_c: integer := 21;

  constant flit_idle_c: mii_flit_t := (data => x"00", valid => '0', error => '0');

  signal clock_ext_s, clock_s, por_n_s, reset_n_s: std_ulogic;
  signal flit_s: mii_flit_t;
  signal flit_valid_s: std_ulogic;
  signal l1_req_s, l2_req_s: committed_req;
  signal l1_ack_s, l2_ack_s: committed_ack;
  signal link_up_s, polarity_s: std_ulogic;
  signal ready_s, uart_valid_s: std_ulogic;
  signal uart_data_s: std_ulogic_vector(7 downto 0);

  type snap_t is array(0 to snap_len_c-1) of std_ulogic_vector(7 downto 0);

  type print_state_t is (
    PR_RESET,
    PR_IDLE,
    PR_HEX_H,
    PR_HEX_L,
    PR_SEP,
    PR_TAIL,
    PR_STATUS
    );

  type regs_t is
  record
    -- Capture side, runs at line rate
    snap: snap_t;
    snap_count: integer range 0 to snap_len_c;
    frame_len: unsigned(11 downto 0);
    total: unsigned(15 downto 0);
    good: unsigned(15 downto 0);
    activity: std_ulogic;

    -- Handover to the print side
    pending: std_ulogic;
    pr_snap: snap_t;
    pr_count: integer range 0 to snap_len_c;
    pr_len: unsigned(11 downto 0);
    pr_good: std_ulogic;

    -- Print side, runs at uart rate
    pr_state: print_state_t;
    pr_index: integer range 0 to snap_len_c-1;
    tail_index: integer range 0 to tail_len_c-1;
    status_index: integer range 0 to status_len_c-1;

    second: integer range 0 to clock_hz_c-1;
    sec_pending: std_ulogic;
    st_total: unsigned(15 downto 0);
    st_good: unsigned(15 downto 0);
    st_link: std_ulogic;
    st_pol: std_ulogic;
  end record;

  signal r, rin: regs_t;

  function to_hex_ascii(n: unsigned(3 downto 0)) return std_ulogic_vector
  is
  begin
    if n < 10 then
      return std_ulogic_vector(resize(n, 8) + character'pos('0'));
    else
      return std_ulogic_vector(resize(n, 8) + character'pos('a') - 10);
    end if;
  end function;

  function to_ascii(b: std_ulogic) return std_ulogic_vector
  is
  begin
    if b = '1' then
      return x"31";
    else
      return x"30";
    end if;
  end function;

  function tail_char(index: integer range 0 to tail_len_c-1;
                     len: unsigned(11 downto 0);
                     good: std_ulogic) return std_ulogic_vector
  is
  begin
    case index is
      when 0 => return x"6c"; -- l
      when 1 => return x"3d"; -- =
      when 2 => return to_hex_ascii(len(11 downto 8));
      when 3 => return to_hex_ascii(len(7 downto 4));
      when 4 => return to_hex_ascii(len(3 downto 0));
      when 5 => return x"20";
      when 6 =>
        if good = '1' then
          return x"47"; -- G
        else
          return x"42"; -- B
        end if;
      when 7 => return x"0d";
      when 8 => return x"0a";
    end case;
  end function;

  function status_char(index: integer range 0 to status_len_c-1;
                       link, pol: std_ulogic;
                       total, good: unsigned(15 downto 0))
    return std_ulogic_vector
  is
  begin
    case index is
      when 0 => return x"3d"; -- =
      when 1 => return x"4c"; -- L
      when 2 => return to_ascii(link);
      when 3 => return x"20";
      when 4 => return x"50"; -- P
      when 5 => return to_ascii(pol);
      when 6 => return x"20";
      when 7 => return x"6e"; -- n
      when 8 => return x"3d"; -- =
      when 9 => return to_hex_ascii(total(15 downto 12));
      when 10 => return to_hex_ascii(total(11 downto 8));
      when 11 => return to_hex_ascii(total(7 downto 4));
      when 12 => return to_hex_ascii(total(3 downto 0));
      when 13 => return x"20";
      when 14 => return x"67"; -- g
      when 15 => return x"3d"; -- =
      when 16 => return to_hex_ascii(good(15 downto 12));
      when 17 => return to_hex_ascii(good(11 downto 8));
      when 18 => return to_hex_ascii(good(7 downto 4));
      when 19 => return to_hex_ascii(good(3 downto 0));
      when 20 => return x"0a";
    end case;
  end function;

begin

  clk_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk_i,
      clock_o => clock_ext_s
      );

  por: nsl_hwdep.reset.reset_at_startup
    port map(
      clock_i => clock_ext_s,
      reset_n_o => por_n_s
      );

  pll: nsl_clocking.pll.pll_basic
    generic map(
      input_hz_c => clock_ext_hz_c,
      output_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_ext_s,
      reset_n_i => por_n_s,
      clock_o => clock_s,
      locked_o => reset_n_s
      );

  mau: nsl_sipeed.pmod_ethernet.pmod_ethernet_10baset_mau
    generic map(
      clock_i_hz_c => clock_hz_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      pmod_io => pmod_io,

      flit_i => flit_idle_c,
      ready_o => open,

      flit_o => flit_s,
      valid_o => flit_valid_s,

      link_up_o => link_up_s,
      polarity_inverted_o => polarity_s,
      crs_o => open,
      col_o => open,

      probe_o => open
      );

  to_committed: nsl_mii.flit.mii_flit_to_committed
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      flit_i => flit_s,
      valid_i => flit_valid_s,

      committed_o => l1_req_s,
      committed_i => l1_ack_s
      );

  fcs_check: nsl_inet.mac.mac_receiver
    generic map(
      l1_has_fcs_c => true
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      l1_i => l1_req_s,
      l1_o => l1_ack_s,

      l2_o => l2_req_s,
      l2_i => l2_ack_s
      );

  regs: process(clock_s, reset_n_s)
  begin
    if rising_edge(clock_s) then
      r <= rin;
    end if;
    if reset_n_s = '0' then
      r.pr_state <= PR_RESET;
      r.pending <= '0';
      r.sec_pending <= '0';
      r.activity <= '0';
      r.snap_count <= 0;
      r.frame_len <= (others => '0');
      r.total <= (others => '0');
      r.good <= (others => '0');
      r.second <= clock_hz_c - 1;
    end if;
  end process;

  transition: process(r, l2_req_s, ready_s, link_up_s, polarity_s)
  begin
    rin <= r;

    if r.second /= 0 then
      rin.second <= r.second - 1;
    else
      rin.second <= clock_hz_c - 1;
      rin.st_total <= r.total;
      rin.st_good <= r.good;
      rin.st_link <= link_up_s;
      rin.st_pol <= polarity_s;
      rin.sec_pending <= '1';
    end if;

    -- Capture side, never stalls the receive path.
    if l2_req_s.valid = '1' then
      if l2_req_s.last = '1' then
        rin.total <= r.total + 1;
        if l2_req_s.data(0) = '1' then
          rin.good <= r.good + 1;
        end if;

        if r.pending = '0' then
          rin.pending <= '1';
          rin.pr_snap <= r.snap;
          rin.pr_count <= r.snap_count;
          rin.pr_len <= r.frame_len;
          rin.pr_good <= l2_req_s.data(0);
        end if;

        rin.snap_count <= 0;
        rin.frame_len <= (others => '0');
        rin.activity <= not r.activity;
      else
        if r.snap_count /= snap_len_c then
          rin.snap(r.snap_count) <= l2_req_s.data;
          rin.snap_count <= r.snap_count + 1;
        end if;
        if r.frame_len /= (r.frame_len'range => '1') then
          rin.frame_len <= r.frame_len + 1;
        end if;
      end if;
    end if;

    case r.pr_state is
      when PR_RESET =>
        rin.pr_state <= PR_IDLE;

      when PR_IDLE =>
        if r.pending = '1' then
          rin.pr_index <= 0;
          if r.pr_count = 0 then
            rin.tail_index <= 0;
            rin.pr_state <= PR_TAIL;
          else
            rin.pr_state <= PR_HEX_H;
          end if;
        elsif r.sec_pending = '1' then
          rin.sec_pending <= '0';
          rin.status_index <= 0;
          rin.pr_state <= PR_STATUS;
        end if;

      when PR_HEX_H =>
        if ready_s = '1' then
          rin.pr_state <= PR_HEX_L;
        end if;

      when PR_HEX_L =>
        if ready_s = '1' then
          rin.pr_state <= PR_SEP;
        end if;

      when PR_SEP =>
        if ready_s = '1' then
          if r.pr_index /= r.pr_count - 1 then
            rin.pr_index <= r.pr_index + 1;
            rin.pr_state <= PR_HEX_H;
          else
            rin.tail_index <= 0;
            rin.pr_state <= PR_TAIL;
          end if;
        end if;

      when PR_TAIL =>
        if ready_s = '1' then
          if r.tail_index /= tail_len_c - 1 then
            rin.tail_index <= r.tail_index + 1;
          else
            rin.pending <= '0';
            rin.pr_state <= PR_IDLE;
          end if;
        end if;

      when PR_STATUS =>
        if ready_s = '1' then
          if r.status_index /= status_len_c - 1 then
            rin.status_index <= r.status_index + 1;
          else
            rin.pr_state <= PR_IDLE;
          end if;
        end if;
    end case;
  end process;

  uart: nsl_uart.serdes.uart_tx
    generic map(
      bit_count_c => 8,
      stop_count_c => 1,
      parity_c => PARITY_NONE
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      divisor_i => divisor_c,
      uart_o => uart_tx_o,
      data_i => uart_data_s,
      ready_o => ready_s,
      valid_i => uart_valid_s
      );

  moore: process(r)
  begin
    uart_valid_s <= '0';
    uart_data_s <= (others => '0');

    case r.pr_state is
      when PR_RESET | PR_IDLE =>
        null;

      when PR_HEX_H =>
        uart_valid_s <= '1';
        uart_data_s <= to_hex_ascii(unsigned(r.pr_snap(r.pr_index)(7 downto 4)));

      when PR_HEX_L =>
        uart_valid_s <= '1';
        uart_data_s <= to_hex_ascii(unsigned(r.pr_snap(r.pr_index)(3 downto 0)));

      when PR_SEP =>
        uart_valid_s <= '1';
        uart_data_s <= x"20";

      when PR_TAIL =>
        uart_valid_s <= '1';
        uart_data_s <= tail_char(r.tail_index, r.pr_len, r.pr_good);

      when PR_STATUS =>
        uart_valid_s <= '1';
        uart_data_s <= status_char(r.status_index, r.st_link, r.st_pol,
                                   r.st_total, r.st_good);
    end case;
  end process;

  l2_ack_s.ready <= '1';

  done_led_o <= link_up_s;
  ready_led_o <= r.activity;

end arch;
