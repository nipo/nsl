library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_data, nsl_logic, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_logic.bool.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.testing.all;

-- Runs both engines of a host against a card model over the transfers
-- a raw storage user makes: single blocks, counted runs of them, and
-- a run with no end in sight that the host stops when it runs out of
-- data.
--
-- Blocks go out over one data line and then over four, and what comes
-- back is checked against what the card says it holds, so a host
-- spreading a byte over the lines the wrong way cannot pass.
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

  signal sample_phase_s: unsigned(8 downto 0)
    := to_unsigned(default_sample_phase(clock_i_hz_c, half_cycle_m1_c), 9);
  signal run_s: std_ulogic := '0';

  signal drive_s, sample_s: std_ulogic;

  signal req_s: cmd_req_t := cmd_idle;
  signal req_ack_s: cmd_ack_t;
  signal rsp_s: cmd_rsp_t;

  signal width_s: bus_width_t := SDIO_WIDTH_1;
  signal timeout_cycle_s: unsigned(15 downto 0) := to_unsigned(1024, 16);
  signal dat_req_s: dat_req_t := dat_idle;
  signal dat_ack_s: dat_ack_t;
  signal dat_rsp_s: dat_rsp_t;
  signal stop_s: std_ulogic := '0';

  signal tx_valid_s: std_ulogic := '0';
  signal tx_data_s: byte;
  signal tx_ready_s: std_ulogic;
  signal tx_base_s: unsigned(31 downto 0) := (others => '0');
  signal tx_index_s: natural := 0;
  signal tx_reset_s: std_ulogic := '0';

  signal rx_valid_s: std_ulogic;
  signal rx_data_s: byte;
  signal rx_buf_s: byte_string(0 to max_block_count_c * block_byte_count_c - 1);
  signal rx_count_s: natural := 0;
  signal rx_reset_s: std_ulogic := '0';

  signal host_o_s: sdio_master_o;
  signal host_i_s: sdio_master_i;
  signal card_o_s: sdio_slave_o;
  signal bus_s: sdio_bus;

  -- Content a test writes, told apart from what a card says it holds
  -- by the numbers it is made of.
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

  clock_driver: nsl_sdio.link.link_clock_driver
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      half_cycle_m1_i => to_unsigned(half_cycle_m1_c, 8),
      sample_phase_i => sample_phase_s,
      run_i => run_s,

      clk_o => host_o_s.clk,
      drive_o => drive_s,
      sample_o => sample_s,
      running_o => open
      );

  cmd_engine: nsl_sdio.link.link_cmd_engine
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      drive_i => drive_s,
      sample_i => sample_s,

      cmd_o => host_o_s.cmd,
      cmd_i => host_i_s.cmd,
      dat0_i => host_i_s.d(0),

      req_i => req_s,
      req_o => req_ack_s,

      rsp_o => rsp_s,
      busy_o => open
      );

  dut: nsl_sdio.link.link_dat_engine
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      drive_i => drive_s,
      sample_i => sample_s,

      d_o => host_o_s.d,
      d_i => host_i_s.d,

      width_i => width_s,

      timeout_cycle_i => timeout_cycle_s,

      req_i => dat_req_s,
      req_o => dat_ack_s,
      stop_i => stop_s,

      rsp_o => dat_rsp_s,
      busy_o => open,

      tx_valid_i => tx_valid_s,
      tx_data_i => tx_data_s,
      tx_ready_o => tx_ready_s,

      rx_valid_o => rx_valid_s,
      rx_data_o => rx_data_s
      );

  card: nsl_sdio.testing.testing_card_model
    port map(
      sdio_i => to_slave_i(bus_s),
      sdio_o => card_o_s
      );

  -- A write has to keep up for a whole block once one starts, so the
  -- source here never runs dry: it just walks the blocks it was
  -- pointed at.
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
      elsif rx_valid_s = '1' then
        assert rx_count_s < rx_buf_s'length
          report "host read more than the test asked for" severity failure;
        rx_buf_s(rx_count_s) <= rx_data_s;
        rx_count_s <= rx_count_s + 1;
      end if;
    end if;
  end process;

  stim: process is

    variable rca: unsigned(15 downto 0);

    procedure command(index: natural;
                      argument: unsigned;
                      response: response_kind_t;
                      check_crc: boolean := true) is
    begin
      req_s <= cmd_request(index, argument, response, check_crc);

      loop
        wait until rising_edge(clock_s);
        exit when req_ack_s.ready = '1';
      end loop;

      req_s <= cmd_idle;

      loop
        wait until rising_edge(clock_s);
        exit when rsp_s.valid = '1';
      end loop;

      assert rsp_s.status = CMD_OK
        report "CMD" & to_string(index) & " ended as "
        & cmd_status_t'image(rsp_s.status)
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
    end procedure;

    -- What a host does after stopping a transfer: poll until the card
    -- is done with what it had in hand.
    procedure wait_ready is
    begin
      loop
        command(13, rca & x"0000", RESP_SHORT);
        exit when rsp_s.payload(12 downto 9) = "0100";
      end loop;
    end procedure;

    procedure dat_arm(write: boolean; block_count: natural) is
    begin
      dat_req_s <= dat_request(write, block_byte_count_c, block_count);

      loop
        wait until rising_edge(clock_s);
        exit when dat_ack_s.ready = '1';
      end loop;

      dat_req_s <= dat_idle;
    end procedure;

    procedure dat_wait(want: dat_status_t) is
    begin
      loop
        wait until rising_edge(clock_s);
        exit when dat_rsp_s.valid = '1';
      end loop;

      assert dat_rsp_s.status = want
        report "transfer ended as " & dat_status_t'image(dat_rsp_s.status)
        & " instead of " & dat_status_t'image(want)
        severity failure;
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

    -- A read is armed before the command, as a card starts sending
    -- of its own accord once it has answered.
    procedure read_blocks(lba: unsigned;
                          block_count: natural;
                          written: boolean := false) is
    begin
      rx_reset_s <= '1';
      wait until rising_edge(clock_s);
      rx_reset_s <= '0';

      dat_arm(false, block_count);
      command(if_else(block_count = 1, 17, 18),
              lba, RESP_SHORT);
      dat_wait(DAT_OK);

      assert dat_rsp_s.block_count = block_count
        report "host took " & to_string(dat_rsp_s.block_count)
        & " blocks instead of " & to_string(block_count)
        severity failure;

      if block_count /= 1 then
        -- A card sends until told to stop, whatever the host counted.
        command(12, x"00000000", RESP_SHORT);
        wait_ready;
      end if;

      check_read(lba, block_count, written);
    end procedure;

    -- A write is armed after the answer, as a card only starts
    -- looking for a block once it has told the host to go ahead.
    procedure write_blocks(lba: unsigned;
                           block_count: natural;
                           open_ended: boolean := false) is
    begin
      tx_base_s <= lba;
      tx_reset_s <= '1';
      wait until rising_edge(clock_s);
      tx_reset_s <= '0';
      tx_valid_s <= '1';

      command(if_else(block_count = 1, 24, 25),
              lba, RESP_SHORT);

      if open_ended then
        dat_arm(true, 0);

        -- Streaming stops when the source does, which here is a byte
        -- count rather than a block count.
        loop
          wait until rising_edge(clock_s);
          exit when tx_index_s = block_count * block_byte_count_c;
        end loop;

        stop_s <= '1';
      else
        dat_arm(true, block_count);
      end if;

      dat_wait(DAT_OK);
      stop_s <= '0';
      tx_valid_s <= '0';

      assert dat_rsp_s.block_count = block_count
        report "host wrote " & to_string(dat_rsp_s.block_count)
        & " blocks instead of " & to_string(block_count)
        severity failure;

      if block_count /= 1 or open_ended then
        command(12, x"00000000", RESP_SHORT_BUSY);
        wait_ready;
      end if;
    end procedure;

  begin
    wait until reset_n_s = '1';
    run_s <= '1';

    identify;

    report "single block over one data line" severity note;
    read_blocks(x"00000100", 1);

    report "switching the bus to four data lines" severity note;
    command(55, rca & x"0000", RESP_SHORT);
    command(6, x"00000002", RESP_SHORT);
    width_s <= SDIO_WIDTH_4;

    -- Same block, same content, spread over four lines this time.
    report "single block over four data lines" severity note;
    read_blocks(x"00000100", 1);

    report "single block written and read back" severity note;
    write_blocks(x"00000200", 1);
    read_blocks(x"00000200", 1, true);

    report "counted run of blocks" severity note;
    read_blocks(x"00000300", max_block_count_c);

    report "run of blocks with no count, stopped by the host"
      severity note;
    write_blocks(x"00000400", 3, true);
    read_blocks(x"00000400", 3, true);

    -- A card that was never told to send anything sends nothing, and
    -- the host has to give up rather than wait forever.
    report "read of a card that has nothing to say" severity note;
    timeout_cycle_s <= to_unsigned(32, 16);
    rx_reset_s <= '1';
    wait until rising_edge(clock_s);
    rx_reset_s <= '0';
    dat_arm(false, 1);
    dat_wait(DAT_TIMEOUT);
    timeout_cycle_s <= to_unsigned(1024, 16);

    assert rx_count_s = 0
      report "host read " & to_string(rx_count_s)
      & " bytes out of a card that said nothing"
      severity failure;

    report "sdio data engine test done";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
