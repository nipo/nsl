library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data, nsl_logic, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_logic.bool.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.host.all;
use nsl_sdio.testing.all;

-- Runs a whole host against a card model, one transaction at a time,
-- over what a raw storage user does with a card.
--
-- Half of it runs with a fabric side that cannot keep up: a reader
-- taking a byte every twentieth cycle, then a writer feeding one that
-- slowly.  A block cannot be held once it starts, so the only way
-- through is to take the card's clock away and give it back, and the
-- content checks are what says that worked.
entity tb is
end entity;

architecture beh of tb is

  constant clock_i_hz_c: natural := 100000000;
  constant clock_period_c: time := 10 ns;
  constant half_cycle_m1_c: natural := 1;

  constant block_byte_count_c: natural := 512;
  constant max_block_count_c: natural := 4;

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;

  signal width_s: bus_width_t := SDIO_WIDTH_1;

  signal req_s: txn_req_t := txn_idle;
  signal req_ack_s: txn_ack_t;
  signal rsp_s: txn_rsp_t;
  signal stop_s: std_ulogic := '0';

  signal tx_valid_s: std_ulogic;
  signal tx_data_s: byte;
  signal tx_ready_s: std_ulogic;
  signal tx_base_s: unsigned(31 downto 0) := (others => '0');
  signal tx_index_s: natural := 0;
  signal tx_reset_s: std_ulogic := '0';
  signal tx_enable_s: std_ulogic := '0';

  signal rx_valid_s: std_ulogic;
  signal rx_data_s: byte;
  signal rx_ready_s: std_ulogic;
  signal rx_buf_s: byte_string(0 to max_block_count_c * block_byte_count_c - 1);
  signal rx_count_s: natural := 0;
  signal rx_reset_s: std_ulogic := '0';

  -- Cycles the fabric side of the test takes off between bytes
  signal gap_s: natural := 0;
  signal pace_s: natural := 0;

  signal host_o_s: sdio_master_o;
  signal host_i_s: sdio_master_i;
  signal card_o_s: sdio_slave_o;
  signal bus_s: sdio_bus;

  function written_byte(lba: unsigned; offset: natural) return byte
  is
    variable seed: natural;
  begin
    seed := (to_integer(lba(7 downto 0)) * 37 + offset * 7 + 3) mod 256;

    return std_ulogic_vector(to_unsigned(seed, 8));
  end function;

begin

  clock_s <= (not clock_s) after clock_period_c / 2 when not done_s else '0';
  reset_n_s <= '1' after 3 * clock_period_c;

  bus_s <= to_bus(host_o_s);
  bus_s <= to_bus(card_o_s);
  bus_s <= sdio_bus_released_c;

  host_i_s <= to_master_i(bus_s);

  dut: nsl_sdio.host.host_controller
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      sdio_o => host_o_s,
      sdio_i => host_i_s,

      half_cycle_m1_i => to_unsigned(half_cycle_m1_c, 8),
      sample_phase_i => to_unsigned(default_sample_phase(clock_i_hz_c,
                                                         half_cycle_m1_c), 9),
      width_i => width_s,
      timeout_cycle_i => to_unsigned(1024, 16),

      req_i => req_s,
      req_o => req_ack_s,
      stop_i => stop_s,

      rsp_o => rsp_s,

      tx_valid_i => tx_valid_s,
      tx_data_i => tx_data_s,
      tx_ready_o => tx_ready_s,

      rx_valid_o => rx_valid_s,
      rx_data_o => rx_data_s,
      rx_ready_i => rx_ready_s
      );

  card: nsl_sdio.testing.testing_card_model
    port map(
      sdio_i => to_slave_i(bus_s),
      sdio_o => card_o_s
      );

  -- One byte every gap_s + 1 cycles, on whichever side is in use.
  pacer: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if pace_s = 0 then
        pace_s <= gap_s;
      else
        pace_s <= pace_s - 1;
      end if;
    end if;
  end process;

  tx_valid_s <= tx_enable_s when pace_s = 0 else '0';
  rx_ready_s <= '1' when pace_s = 0 else '0';

  tx_data_s <= written_byte(tx_base_s + tx_index_s / block_byte_count_c,
                            tx_index_s mod block_byte_count_c);

  tx_feed: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if tx_reset_s = '1' then
        tx_index_s <= 0;
      elsif tx_valid_s = '1' and tx_ready_s = '1' then
        tx_index_s <= tx_index_s + 1;
      end if;
    end if;
  end process;

  rx_collect: process(clock_s) is
  begin
    if rising_edge(clock_s) then
      if rx_reset_s = '1' then
        rx_count_s <= 0;
      elsif rx_valid_s = '1' and rx_ready_s = '1' then
        assert rx_count_s < rx_buf_s'length
          report "host read more than the test asked for" severity failure;
        rx_buf_s(rx_count_s) <= rx_data_s;
        rx_count_s <= rx_count_s + 1;
      end if;
    end if;
  end process;

  stim: process is

    variable rca: unsigned(15 downto 0);

    procedure run(req: txn_req_t) is
    begin
      req_s <= req;

      loop
        wait until rising_edge(clock_s);
        exit when req_ack_s.ready = '1';
      end loop;

      req_s <= txn_idle;

      loop
        wait until rising_edge(clock_s);
        exit when rsp_s.valid = '1';
      end loop;
    end procedure;

    procedure command(index: natural;
                      argument: unsigned;
                      response: response_kind_t;
                      check_crc: boolean := true) is
    begin
      run(txn_command(index, argument, response, check_crc));

      assert rsp_s.cmd_status = CMD_OK
        report "CMD" & to_string(index) & " ended as "
        & cmd_status_t'image(rsp_s.cmd_status)
        severity failure;
      assert rsp_s.dat_status = DAT_OK
        report "CMD" & to_string(index)
        & " carried no data but came back with "
        & dat_status_t'image(rsp_s.dat_status)
        severity failure;
    end procedure;

    procedure identify is
    begin
      command(0, x"00000000", RESP_NONE);
      command(8, x"000001aa", RESP_SHORT);

      loop
        command(55, x"00000000", RESP_SHORT);
        command(41, x"40ff8000", RESP_SHORT, false);
        exit when rsp_s.payload(31) = '1';
      end loop;

      command(2, x"00000000", RESP_LONG);
      command(3, x"00000000", RESP_SHORT);
      rca := unsigned(rsp_s.payload(31 downto 16));
      command(7, rca & x"0000", RESP_SHORT_BUSY);
      command(16, x"00000200", RESP_SHORT);

      command(55, rca & x"0000", RESP_SHORT);
      command(6, x"00000002", RESP_SHORT);
      width_s <= SDIO_WIDTH_4;
    end procedure;

    procedure wait_ready is
    begin
      loop
        command(13, rca & x"0000", RESP_SHORT);
        exit when rsp_s.payload(12 downto 9) = "0100";
      end loop;
    end procedure;

    procedure check_read(lba: unsigned;
                         block_count: natural;
                         written: boolean) is
      variable want: byte_string(0 to block_byte_count_c - 1);
      variable bad: natural := 0;
    begin
      assert rx_count_s = block_count * block_byte_count_c
        report "host read " & to_string(rx_count_s) & " bytes instead of "
        & to_string(block_count * block_byte_count_c)
        severity failure;

      for b in 0 to block_count - 1
      loop
        if written then
          for i in want'range
          loop
            want(i) := written_byte(lba + b, i);
          end loop;
        else
          want := default_block(lba + b, block_byte_count_c);
        end if;

        for i in want'range
        loop
          if rx_buf_s(b * block_byte_count_c + i) /= want(i) then
            if bad = 0 then
              report "block " & to_string(b) & " byte " & to_string(i)
                & " read as "
                & to_string(rx_buf_s(b * block_byte_count_c + i))
                & " instead of " & to_string(want(i))
                severity failure;
            end if;

            bad := bad + 1;
          end if;
        end loop;
      end loop;

      assert bad = 0
        report to_string(bad) & " bytes of what was read differ"
        severity failure;
    end procedure;

    procedure read_blocks(lba: unsigned;
                          block_count: natural;
                          written: boolean := false) is
    begin
      rx_reset_s <= '1';
      wait until rising_edge(clock_s);
      rx_reset_s <= '0';

      run(txn_read(if_else(block_count = 1, 17, 18), lba,
                   block_byte_count_c, block_count));

      assert rsp_s.cmd_status = CMD_OK and rsp_s.dat_status = DAT_OK
        report "reading ended as "
        & cmd_status_t'image(rsp_s.cmd_status) & " and "
        & dat_status_t'image(rsp_s.dat_status)
        severity failure;
      assert rsp_s.block_count = block_count
        report "host took " & to_string(rsp_s.block_count)
        & " blocks instead of " & to_string(block_count)
        severity failure;

      if block_count /= 1 then
        -- A card sends until told to stop, whatever the host counted.
        command(12, x"00000000", RESP_SHORT);
        wait_ready;
      end if;

      check_read(lba, block_count, written);
    end procedure;

    procedure write_blocks(lba: unsigned;
                           block_count: natural;
                           open_ended: boolean := false) is
    begin
      tx_base_s <= lba;
      tx_reset_s <= '1';
      wait until rising_edge(clock_s);
      tx_reset_s <= '0';
      tx_enable_s <= '1';

      if open_ended then
        req_s <= txn_write(25, lba, block_byte_count_c, 0);
      else
        req_s <= txn_write(if_else(block_count = 1, 24, 25), lba,
                           block_byte_count_c, block_count);
      end if;

      loop
        wait until rising_edge(clock_s);
        exit when req_ack_s.ready = '1';
      end loop;

      req_s <= txn_idle;

      if open_ended then
        -- Streaming stops when the source does, which here is a byte
        -- count rather than a block count.
        loop
          wait until rising_edge(clock_s);
          exit when tx_index_s = block_count * block_byte_count_c;
        end loop;

        stop_s <= '1';
      end if;

      loop
        wait until rising_edge(clock_s);
        exit when rsp_s.valid = '1';
      end loop;

      stop_s <= '0';
      tx_enable_s <= '0';

      assert rsp_s.cmd_status = CMD_OK and rsp_s.dat_status = DAT_OK
        report "writing ended as "
        & cmd_status_t'image(rsp_s.cmd_status) & " and "
        & dat_status_t'image(rsp_s.dat_status)
        severity failure;
      assert rsp_s.block_count = block_count
        report "host wrote " & to_string(rsp_s.block_count)
        & " blocks instead of " & to_string(block_count)
        severity failure;

      if block_count /= 1 or open_ended then
        command(12, x"00000000", RESP_SHORT_BUSY);
        wait_ready;
      end if;
    end procedure;

  begin
    wait until reset_n_s = '1';

    identify;

    report "one block each way, fabric side keeping up" severity note;
    read_blocks(x"00000100", 1);
    write_blocks(x"00000200", 1);
    read_blocks(x"00000200", 1, true);

    report "a run of blocks read by a fabric side that cannot keep up"
      severity note;
    gap_s <= 20;
    read_blocks(x"00000300", max_block_count_c);

    report "a run of blocks written by a fabric side that cannot keep up"
      severity note;
    write_blocks(x"00000400", 3, true);
    read_blocks(x"00000400", 3, true);
    gap_s <= 0;

    -- A command that goes unanswered takes the data phase armed for
    -- it down with it.
    report "a read whose command nobody answers" severity note;
    run(txn_read(13, x"43210000", block_byte_count_c, 1));

    assert rsp_s.cmd_status = CMD_TIMEOUT
      report "command to an address no card has ended as "
      & cmd_status_t'image(rsp_s.cmd_status)
      severity failure;
    assert rsp_s.dat_status = DAT_CANCELLED
      report "data phase of a command nobody answered ended as "
      & dat_status_t'image(rsp_s.dat_status)
      severity failure;

    report "sdio host test done";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
