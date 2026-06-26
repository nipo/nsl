library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_bnoc, nsl_jtag, nsl_simulation, nsl_data;
use nsl_jtag.jtag.all;
use nsl_jtag.transactor.all;
use nsl_jtag.continuous_transport.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

-- Integration loopback test with decoupled application and JTAG driver.
--
-- An application process pushes packets to ate_tx_q and, in a second loop,
-- expects the same packets back on ate_rx_q (two loops so TX and RX pipeline).
-- The JTAG driver process turns those packets into continuous_transport
-- batches over a real simulation TAP whose RX is looped back to its TX through
-- a framed_fifo. It honours dynamic RX credit: it never sends more data bytes
-- than the TAP's last advertised RX free space, holding a packet that does not
-- fit until echoes drain the RX FIFO. The RX FIFO is deliberately small so the
-- credit loop binds; the idle padding is kept large so the TAP's echo is not
-- truncated.
entity tb is
end entity;

architecture arch of tb is

  constant idcode_c : std_ulogic_vector(31 downto 0) := x"87654321";
  constant idcode_instruction_c : std_ulogic_vector(3 downto 0) := x"2";
  constant user0_instruction_c : std_ulogic_vector(3 downto 0) := x"8";

  constant packet_count_c : integer := 16;

  signal done_s : std_ulogic_vector(0 to 0);

  type framed_io is
  record
    cmd, rsp : nsl_bnoc.framed.framed_bus;
  end record;

  -- Transactor command/response queues.
  shared variable command_q, response_q : framed_queue_root;
  -- Application <-> JTAG-driver packet queues, and completion flag.
  shared variable ate_tx_q, ate_rx_q : framed_queue_root;
  shared variable test_done : boolean := false;

  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  signal rx_req, tx_req : nsl_bnoc.framed.framed_req_t;
  signal rx_ack, tx_ack : nsl_bnoc.framed.framed_ack_t;

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

  -- Application: push all packets, then expect them all back.
  app: process
    variable rx : byte_stream;
  begin
    wait for 200 ns;

    for i in 0 to packet_count_c - 1 loop
      framed_queue_put(ate_tx_q, gen_packet(i));
    end loop;

    for i in 0 to packet_count_c - 1 loop
      framed_queue_get(ate_rx_q, rx);
      assert_equal("loopback", rx.all, gen_packet(i), failure);
      deallocate(rx);
    end loop;

    test_done := true;
    wait;
  end process;

  -- JTAG driver: batches packets onto the wire and reassembles the echoes.
  host: process
    variable rx_partial : byte_stream := null;
    variable pb, received : byte_stream;
    -- A packet pulled from ate_tx_q but not yet sent (held when RX credit is
    -- too low to fit it).
    variable pending : byte_stream := null;
    variable batch_no : integer := 0;
    variable pad : integer;
    -- Latest RX free space advertised by the TAP, and the budget left to spend
    -- on data this batch.
    variable rx_credit : integer := 0;
    variable credit_left : integer;
    variable throttled_ever : boolean := false;

    procedure do_io(response : out byte_stream; command : in byte_string) is
      variable rsp : byte_stream;
    begin
      framed_queue_put(command_q, command);
      framed_queue_get(response_q, rsp);
      response := rsp;
    end procedure;

    procedure chain_reset(div : integer range 1 to 256) is
      variable response : byte_stream;
    begin
      do_io(response, cmd_reset(5) & cmd_divisor(div) & cmd_reset(5) & cmd_run(1));
    end procedure;

    procedure ir_set(ir : std_ulogic_vector) is
      variable command, response : byte_stream;
    begin
      command := null;
      write(command, cmd_capture_ir);
      write(command, cmd_shift(ir, false));
      write(command, cmd_run(1));
      do_io(response, command.all);
      rsp(response);
      rsp_shift(response, ir'length);
      rsp(response);
    end procedure;

    -- Prefix preamble+SOF to protocol_data, shift the batch, and return every
    -- byte after the TAP's SOF on TDO.
    procedure exchange(protocol_data : byte_string; rx_bytes : out byte_stream) is
      constant batch : byte_string := byte_string'(x"55", x"55", x"d5") & protocol_data;
      constant cmd : byte_string := cmd_capture_dr
                                    & cmd_shift(std_ulogic_vector(from_le(batch)), true)
                                    & cmd_run(1);
      variable tdo_bits : std_ulogic_vector(batch'length * 8 - 1 downto 0);
      variable response : byte_stream;
      variable sof, pos : integer;
      variable acc : byte_stream := null;
    begin
      do_io(response, cmd);
      rsp(response);
      rsp_shift(response, tdo_bits);
      rsp(response);

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

    -- Walk protocol bytes; accumulate data into rx_partial and push a complete
    -- packet to ate_rx_q on a non-truncated last frame.
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
          if got_all and hdr(hdr_last_bit_c) = '1' then
            framed_queue_put(ate_rx_q, rx_partial.all);
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
          -- TAP-advertised TX backlog (absolute, little-endian). Skip its two
          -- operand bytes; this test does not act on it.
          pos := pos + 2;
        else
          null;
        end if;
      end loop;
    end procedure;

  begin
    done_s(0) <= '0';
    framed_queue_init(command_q);
    framed_queue_init(response_q);
    framed_queue_init(ate_tx_q);
    framed_queue_init(ate_rx_q);

    wait for 40 ns;

    chain_reset(3);
    ir_set(user0_instruction_c);

    while not test_done loop
      pb := null;
      -- Grant a generous TX budget (how much the TAP may send us).
      write(pb, byte_string'(ctl_credit_c, x"c8", x"00"));

      -- Send queued packets, but never more data bytes than the TAP's last
      -- advertised RX free space: hold a packet that does not fit and let
      -- echoes drain its RX FIFO before retrying.
      credit_left := rx_credit;
      loop
        if pending = null and ate_tx_q.all /= null then
          framed_queue_get(ate_tx_q, pending);
        end if;
        exit when pending = null;
        if pending.all'length > credit_left then
          throttled_ever := true;
          exit;
        end if;
        append_data_frames(pb, pending.all);
        credit_left := credit_left - pending.all'length;
        deallocate(pending);
        pending := null;
      end loop;

      -- Varying idle padding -> varying TDO room.
      pad := 48 + (batch_no mod 4) * 8;
      for i in 0 to pad - 1 loop
        write(pb, ctl_idle_c);
      end loop;

      exchange(pb.all, received);
      if received /= null then
        deframe(received.all);
        deallocate(received);
      end if;
      deallocate(pb);

      batch_no := batch_no + 1;
      assert batch_no < 500
        report "packets did not loop back" severity failure;
    end loop;

    assert throttled_ever
      report "RX credit never throttled; test did not exercise flow control"
      severity warning;
    if throttled_ever then
      log_info("continuous_transport queued loopback OK (RX credit throttled)");
    else
      log_info("continuous_transport queued loopback OK (RX credit never bound)");
    end if;
    done_s(0) <= '1';
    wait;
  end process;

  ate: block is
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;
    signal ate_io_s : framed_io;
  begin
    master_q: process is
    begin
      ate_io_s.cmd.req <= framed_req_idle_c;
      wait for 40 ns;
      framed_queue_master_worker(ate_io_s.cmd.req, ate_io_s.cmd.ack, clock_s, command_q);
    end process;

    slave_q: process is
    begin
      ate_io_s.rsp.ack <= framed_ack_idle_c;
      wait for 40 ns;
      framed_queue_slave_worker(ate_io_s.rsp.req, ate_io_s.rsp.ack, clock_s, response_q);
    end process;

    reset_sync_clk: nsl_clocking.async.async_edge
      port map(
        data_i => async_reset_n_s,
        data_o => clock_reset_n_s,
        clock_i => clock_s
        );

    ate_impl: nsl_jtag.transactor.framed_ate
      port map(
        clock_i => clock_s,
        reset_n_i => clock_reset_n_s,
        cmd_i => ate_io_s.cmd.req,
        cmd_o => ate_io_s.cmd.ack,
        rsp_o => ate_io_s.rsp.req,
        rsp_i => ate_io_s.rsp.ack,
        jtag_o => ate_o,
        jtag_i => ate_i
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => 5 ns,
        reset_duration(0) => 5 ns,
        reset_n_o(0) => async_reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

  ate_i <= transport to_ate(tap_o);
  tap_i <= transport to_tap(ate_o);

  dut: block is
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;
    signal slave_reset_n : std_ulogic;
  begin
    reset_sync_clk: nsl_clocking.async.async_edge
      port map(
        data_i => async_reset_n_s,
        data_o => clock_reset_n_s,
        clock_i => clock_s
        );

    tap: nsl_simulation.jtag.jtag_sim_tap
      generic map(
        idcode_c => idcode_c,
        idcode_instruction_c => idcode_instruction_c,
        user0_instruction_c => user0_instruction_c
        )
      port map(
        tck_i => tap_i.tck,
        tms_i => tap_i.tms,
        tdi_i => tap_i.tdi,
        tdo_o => tap_o.tdo.v
        );
    tap_o.tdo.en <= '1';

    slave: nsl_jtag.continuous_transport.continuous_transport_slave
      generic map(
        reg_id_c => 1,
        -- Small RX FIFO so the host's RX-credit throttling actually binds.
        rx_fifo_depth_c => 16,
        tx_fifo_depth_c => 256,
        preamble_count_c => 2
        )
      port map(
        clock_i => clock_s,
        reset_n_i => clock_reset_n_s,
        reset_n_o => slave_reset_n,
        tx_i => tx_req,
        tx_o => tx_ack,
        rx_o => rx_req,
        rx_i => rx_ack
        );

    loopback_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 256,
        clk_count => 1
        )
      port map(
        p_resetn => slave_reset_n,
        p_clk(0) => clock_s,
        p_in_val => rx_req,
        p_in_ack => rx_ack,
        p_out_val => tx_req,
        p_out_ack => tx_ack
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => 5 ns,
        reset_duration(0) => 5 ns,
        reset_n_o(0) => async_reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

end architecture;
