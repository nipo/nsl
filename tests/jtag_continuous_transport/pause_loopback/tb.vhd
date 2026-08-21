library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_jtag, nsl_memory, nsl_simulation, nsl_data;
use nsl_jtag.continuous_transport.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

-- Loopback test of continuous_transport_core across Pause-DR gaps.
--
-- The ATE model here drives the TAP strobes directly, one bit per TCK, so it
-- can suspend a batch anywhere: this is what an adapter does when it enters
-- Pause-DR, and no shift happens on those TCK cycles. Gaps of 1, 2 and 10 TCK
-- are injected at pseudo-random bit positions (so most of them fall in the
-- middle of a byte), plus a gap between the last shifted bit and Update-DR.
-- Nothing may move on those cycles: TDO must keep presenting the bit it
-- stopped on and no byte may be consumed from the framer, otherwise the
-- echoed packets come back short.
--
-- The core's RX side is looped back into its TX side through a small FIFO, so
-- packets pushed on TDI come back on TDO and are checked byte-exact. The FIFO
-- is deliberately small, so the RX credit loop binds as it does on a real link.
entity tb is
end entity;

architecture arch of tb is

  constant packet_count_c : integer := 12;
  constant fifo_depth_c : integer := 16;
  -- Same derating as continuous_transport_slave: bytes in the receive pipeline
  -- not yet reflected in the FIFO free count.
  constant rx_credit_margin_c : integer := (tap_rx_latency_c + 7) / 8 + 1;

  signal clock : std_ulogic := '0';
  signal async_reset_n, reset_n : std_ulogic;

  signal shift, capture, update : std_ulogic := '0';
  signal tdi : std_ulogic := '0';
  signal tdo : std_ulogic;

  signal rx_data, tx_data : byte;
  signal rx_last, rx_valid, rx_ready : std_ulogic;
  signal tx_last, tx_valid, tx_ready : std_ulogic;
  signal rx_free : integer range 0 to fifo_depth_c;
  signal tx_level : integer range 0 to fifo_depth_c;
  signal rx_free_uns, tx_level_uns : unsigned(credit_bits_c-1 downto 0);

  signal done_s : std_ulogic_vector(0 to 0);

  -- 16-bit preamble+SOF pattern in wire-bit order.
  function sync_pattern return std_ulogic_vector is
  begin
    return std_ulogic_vector(from_le(byte_string'(x"55", x"d5")));
  end function;

  -- First wire-bit index after the preamble->SOF in v, or -1.
  function find_sof(v : std_ulogic_vector; len : integer) return integer is
    constant pat : std_ulogic_vector := sync_pattern;
    variable ok : boolean;
  begin
    for k in 0 to len - pat'length loop
      ok := true;
      for j in 0 to pat'length - 1 loop
        if v(k + j) /= pat(j) then
          ok := false;
        end if;
      end loop;
      if ok then
        return k + pat'length;
      end if;
    end loop;
    return -1;
  end function;

  -- Byte at wire-bit position pos (LSB first).
  function byte_at(v : std_ulogic_vector; pos : integer) return byte is
    variable b : byte;
  begin
    for j in 0 to 7 loop
      b(j) := v(pos + j);
    end loop;
    return b;
  end function;

  -- Deterministic per-index test packet.
  function gen_packet(i : integer) return byte_string is
    constant len : integer := 4 + (i mod 4);
    variable r : byte_string(0 to len - 1);
  begin
    for j in 0 to len - 1 loop
      r(j) := to_byte((i * 16 + j) mod 256);
    end loop;
    return r;
  end function;

begin

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock,
      data_i => async_reset_n,
      data_o => reset_n
      );

  dut: nsl_jtag.continuous_transport.continuous_transport_core
    generic map(
      preamble_count_c => 2
      )
    port map(
      clock_i => clock,
      reset_n_i => reset_n,
      shift_i => shift,
      capture_i => capture,
      update_i => update,
      tdi_i => tdi,
      tdo_o => tdo,
      rx_data_o => rx_data,
      rx_last_o => rx_last,
      rx_valid_o => rx_valid,
      rx_free_i => rx_free_uns,
      tx_data_i => tx_data,
      tx_last_i => tx_last,
      tx_valid_i => tx_valid,
      tx_ready_o => tx_ready,
      tx_level_i => tx_level_uns
      );

  rx_free_uns <= to_unsigned(rx_free - rx_credit_margin_c, credit_bits_c)
                 when rx_free > rx_credit_margin_c
                 else (others => '0');
  tx_level_uns <= to_unsigned(tx_level, credit_bits_c);

  -- RX back into TX: what the ATE sends is echoed on the next batches.
  loopback_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 9,
      word_count_c => fifo_depth_c,
      clock_count_c => 1
      )
    port map(
      reset_n_i => reset_n,
      clock_i(0) => clock,

      in_data_i(8) => rx_last,
      in_data_i(7 downto 0) => rx_data,
      in_valid_i => rx_valid,
      in_ready_o => rx_ready,
      in_free_o => rx_free,

      out_data_o(8) => tx_last,
      out_data_o(7 downto 0) => tx_data,
      out_valid_o => tx_valid,
      out_ready_i => tx_ready,
      out_available_min_o => tx_level,
      out_available_o => open
      );

  -- The credit discipline must keep the RX FIFO from ever overflowing: the
  -- core has no back-pressure path on a shifted bus.
  overflow_check: process(clock)
  begin
    if rising_edge(clock) then
      assert not (rx_valid = '1' and rx_ready = '0')
        report "RX FIFO overrun: credit was over-granted"
        severity failure;
    end if;
  end process;

  stim: process
    variable rx_partial : byte_stream := null;
    variable pb, batch_body, received : byte_stream;
    -- A packet generated but not yet sent (held when RX credit is too low).
    variable pending : byte_stream := null;
    variable tx_count, rx_count : integer := 0;
    variable batch_no : integer := 0;
    variable pad : integer;
    -- Latest RX free space advertised by the TAP, and the budget left to spend
    -- on data this batch.
    variable rx_credit : integer := 0;
    variable credit_left, budget : integer;
    variable lfsr : std_ulogic_vector(15 downto 0) := x"ace1";
    variable pause_count, mid_byte_pause_count : integer := 0;
    variable throttled_ever : boolean := false;

    -- Pseudo-random value in 0 .. m-1, from a fixed seed so runs are
    -- reproducible.
    impure function rand(m : integer) return integer is
    begin
      for i in 0 to 7 loop
        lfsr := lfsr(14 downto 0)
                & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
      end loop;
      return to_integer(unsigned(lfsr(7 downto 0))) mod m;
    end function;

    -- Hold the TAP strobes idle for count TCK cycles, checking TDO does not
    -- move: outside a shift the transport must present the same bit.
    procedure hold(count : integer; context : string) is
      variable held : std_ulogic;
    begin
      held := tdo;
      for i in 1 to count loop
        wait until falling_edge(clock);
        assert tdo = held
          report "TDO moved while not shifting (" & context & ")"
          severity failure;
      end loop;
    end procedure;

    -- Shift one batch through the TAP strobes, with Pause-DR gaps, and return
    -- every byte after the TAP's SOF on TDO.
    procedure exchange(protocol_data : byte_string; rx_bytes : out byte_stream) is
      constant batch : byte_string := byte_string'(x"55", x"55", x"d5")
                                      & protocol_data;
      constant bits : std_ulogic_vector(batch'length * 8 - 1 downto 0)
        := std_ulogic_vector(from_le(batch));
      variable tdo_bits : std_ulogic_vector(bits'range);
      variable gap, sof, pos : integer;
      variable acc : byte_stream := null;
    begin
      -- Capture-DR.
      capture <= '1';
      wait until falling_edge(clock);
      capture <= '0';

      for k in 0 to bits'length - 1 loop
        if rand(16) = 0 then
          case rand(3) is
            when 0 => gap := 1;
            when 1 => gap := 2;
            when others => gap := 10;
          end case;
          shift <= '0';
          pause_count := pause_count + 1;
          if k mod 8 /= 0 then
            mid_byte_pause_count := mid_byte_pause_count + 1;
          end if;
          hold(gap, "Pause-DR");
        end if;

        shift <= '1';
        tdi <= bits(k);
        tdo_bits(k) := tdo;
        wait until falling_edge(clock);
      end loop;

      -- Exit1-DR, on odd batches followed by a Pause-DR/Exit2-DR run, then
      -- Update-DR.
      shift <= '0';
      if batch_no mod 2 = 0 then
        gap := 1;
      else
        gap := 4 + rand(9);
      end if;
      hold(gap, "batch tail");
      update <= '1';
      wait until falling_edge(clock);
      update <= '0';

      sof := find_sof(tdo_bits, tdo_bits'length);
      if sof >= 0 then
        pos := sof;
        while pos + 8 <= tdo_bits'length loop
          write(acc, byte_at(tdo_bits, pos));
          pos := pos + 8;
        end loop;
      end if;
      rx_bytes := acc;
    end procedure;

    -- Append one packet as one or more data frames (split at 64 bytes; last
    -- frame carries the end-of-packet bit).
    procedure append_data_frames(stream : inout byte_stream; pkt : byte_string) is
      variable off : integer := 0;
      variable remaining : integer := pkt'length;
      variable chunk : integer;
      variable last_bit : std_ulogic;
      variable header : byte;
    begin
      while remaining > 0 loop
        chunk := remaining;
        if chunk > data_bytes_max_c then
          chunk := data_bytes_max_c;
        end if;
        if chunk = remaining then
          last_bit := '1';
        else
          last_bit := '0';
        end if;
        header := "0" & last_bit & std_ulogic_vector(to_unsigned(chunk - 1, 6));
        write(stream, header);
        write(stream, pkt(pkt'left + off to pkt'left + off + chunk - 1));
        off := off + chunk;
        remaining := remaining - chunk;
      end loop;
    end procedure;

    -- Walk protocol bytes; accumulate data into rx_partial and check a
    -- complete packet against what was sent.
    procedure deframe(data : byte_string) is
      variable pos : integer := data'left;
      variable hdr : byte;
      variable len : integer;
      variable got_all : boolean;
    begin
      while pos <= data'right loop
        hdr := data(pos);
        pos := pos + 1;
        if std_match(hdr, data_header_mask_c) then
          len := to_integer(unsigned(hdr(5 downto 0))) + 1;
          got_all := true;
          for i in 0 to len - 1 loop
            if pos > data'right then
              got_all := false;
              exit;
            end if;
            write(rx_partial, data(pos));
            pos := pos + 1;
          end loop;
          -- The TAP only emits a data frame it can finish within the TX budget
          -- granted for this batch, so a body cut short by the end of the
          -- batch means bytes were lost for good.
          assert got_all
            report "data frame body truncated by the end of the batch"
            severity failure;
          if hdr(hdr_last_bit_c) = '1' then
            assert_equal("loopback", rx_partial.all, gen_packet(rx_count),
                         failure);
            rx_count := rx_count + 1;
            deallocate(rx_partial);
            rx_partial := null;
          end if;
        elsif hdr = ctl_credit_c then
          -- TAP-advertised RX free space (absolute, little-endian). Ignore a
          -- credit frame truncated at the batch tail.
          if pos + 1 <= data'right then
            rx_credit := to_integer(unsigned(data(pos)))
                         + 256 * to_integer(unsigned(data(pos + 1)));
          end if;
          pos := pos + 2;
        elsif hdr = ctl_tx_level_c then
          -- TAP-advertised TX backlog. Skip its two operand bytes; this test
          -- does not act on it.
          pos := pos + 2;
        else
          null;
        end if;
      end loop;
    end procedure;

  begin
    done_s(0) <= '0';

    wait until reset_n = '1';
    wait until falling_edge(clock);

    while rx_count < packet_count_c loop
      -- Batch body: data frames, then idle padding. Built before the batch
      -- header because the TX budget granted there is derived from its length.
      batch_body := null;

      -- Send packets, but never more data bytes than the TAP's last advertised
      -- RX free space: hold a packet that does not fit and let echoes drain
      -- its RX FIFO before retrying.
      credit_left := rx_credit;
      loop
        if pending = null and tx_count < packet_count_c then
          write(pending, gen_packet(tx_count));
          tx_count := tx_count + 1;
        end if;
        exit when pending = null;
        if pending.all'length > credit_left then
          throttled_ever := true;
          exit;
        end if;
        append_data_frames(batch_body, pending.all);
        credit_left := credit_left - pending.all'length;
        deallocate(pending);
        pending := null;
      end loop;

      -- Varying idle padding -> varying TDO room.
      pad := 48 + (batch_no mod 4) * 8;
      for i in 0 to pad - 1 loop
        write(batch_body, ctl_idle_c);
      end loop;

      -- TX budget (spec 6.2): granting N is a promise of at least N*8 + margin
      -- further shift cycles in this Shift-DR, with margin >= U + D +
      -- tap_tx_latency_c. Pause-DR does not enter the count: the promise is
      -- about shifted bits, not about TCK cycles. The grant is the first three
      -- protocol bytes of the batch, so exactly 8 * batch_body'length shift
      -- cycles follow it, and the chain holds no other device (U = D = 0).
      budget := batch_body.all'length - (tap_tx_latency_c + 7) / 8;
      assert budget > 0
        report "batch too short to grant any TX budget" severity failure;

      pb := null;
      write(pb, ctl_credit_c);
      write(pb, to_le(to_unsigned(budget, 16)));
      write(pb, batch_body.all);
      deallocate(batch_body);

      exchange(pb.all, received);
      if received /= null then
        deframe(received.all);
        deallocate(received);
      end if;
      deallocate(pb);

      batch_no := batch_no + 1;
      assert batch_no < 200
        report "packets did not loop back" severity failure;
    end loop;

    assert mid_byte_pause_count > 0
      report "no Pause-DR was injected inside a byte; test did not bite"
      severity failure;
    assert throttled_ever
      report "RX credit never throttled; test did not exercise flow control"
      severity warning;

    log_info("continuous_transport Pause-DR loopback OK ("
             & integer'image(pause_count) & " gaps, "
             & integer'image(mid_byte_pause_count) & " of them inside a byte)");
    done_s(0) <= '1';
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 5 ns,
      reset_duration(0) => 50 ns,
      reset_n_o(0) => async_reset_n,
      clock_o(0) => clock,
      done_i => done_s
      );

end architecture;
