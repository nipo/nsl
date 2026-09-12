library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data, nsl_sdio;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_sdio.sdio.all;
use nsl_sdio.link.all;
use nsl_sdio.host.all;
use nsl_sdio.card.all;
use nsl_sdio.testing.all;

-- Runs the whole stack against a card model: identification, then
-- blocks in and out of it by address, with nothing driving it but a
-- block request and a stream.
--
-- Identification is left to run on its own from reset, so what the
-- test checks first is what the card turned out to be.
entity tb is
end entity;

architecture beh of tb is

  constant clock_i_hz_c: natural := 100000000;
  constant clock_period_c: time := 10 ns;

  constant block_byte_count_c: natural := 512;
  constant max_block_count_c: natural := 4;
  constant card_block_count_c: natural := 65536;

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;

  signal half_cycle_m1_s: unsigned(15 downto 0);
  signal sample_phase_s: unsigned(15 downto 0);
  signal width_s: bus_width_t;
  signal info_s: card_info_t;
  signal card_ready_s: std_ulogic;

  signal blk_req_s: block_req_t := block_idle;
  signal blk_ack_s: block_ack_t;
  signal blk_rsp_s: block_rsp_t;
  signal blk_stop_s: std_ulogic := '0';

  signal dev_req_s: txn_req_t;
  signal dev_ack_s: txn_ack_t;
  signal dev_rsp_s: txn_rsp_t;
  signal dev_stop_s: std_ulogic;

  signal host_req_s: txn_req_t;
  signal host_ack_s: txn_ack_t;
  signal host_rsp_s: txn_rsp_t;

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

  signal bus_o_s: sdio_master_o;
  signal bus_i_s: sdio_master_i;
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

  bus_s <= to_bus(bus_o_s);
  bus_s <= to_bus(card_o_s);
  bus_s <= sdio_bus_released_c;

  bus_i_s <= to_master_i(bus_s);

  device: nsl_sdio.card.card_block_device
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      info_i => info_s,

      req_i => blk_req_s,
      req_o => blk_ack_s,
      stop_i => blk_stop_s,

      rsp_o => blk_rsp_s,

      host_req_o => dev_req_s,
      host_req_i => dev_ack_s,
      host_rsp_i => dev_rsp_s,
      host_stop_o => dev_stop_s
      );

  -- Identification runs on its own out of reset, and steps aside for
  -- the block device once a card is ready.
  initializer: nsl_sdio.card.card_initializer
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      -- Faster than a bus is allowed to start, to keep the test
      -- short: what a divisor of that size does is checked elsewhere.
      bus_init_hz_c => 2000000,
      power_up_us_c => 20
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
      timeout_cycle_i => to_unsigned(4096, 16),

      req_i => host_req_s,
      req_o => host_ack_s,
      stop_i => dev_stop_s,

      rsp_o => host_rsp_s,

      tx_valid_i => tx_valid_s,
      tx_data_i => tx_data_s,
      tx_ready_o => tx_ready_s,

      rx_valid_o => rx_valid_s,
      rx_data_o => rx_data_s
      );

  card: nsl_sdio.testing.testing_card_model
    generic map(
      block_count_c => card_block_count_c
      )
    port map(
      sdio_i => to_slave_i(bus_s),
      sdio_o => card_o_s
      );

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

    procedure check_read(lba: unsigned;
                         block_count: natural;
                         written: boolean) is
      variable want: byte_string(0 to block_byte_count_c - 1);
      variable bad: natural := 0;
    begin
      assert rx_count_s = block_count * block_byte_count_c
        report "read gave " & to_string(rx_count_s) & " bytes instead of "
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

    procedure run(req: block_req_t) is
    begin
      blk_req_s <= req;

      loop
        wait until rising_edge(clock_s);
        exit when blk_ack_s.ready = '1';
      end loop;

      blk_req_s <= block_idle;

      loop
        wait until rising_edge(clock_s);
        exit when blk_rsp_s.valid = '1';
      end loop;

      assert blk_rsp_s.status = BLOCK_OK
        report "block run ended as " & block_status_t'image(blk_rsp_s.status)
        severity failure;
    end procedure;

    procedure read_blocks(lba: unsigned;
                          block_count: natural;
                          written: boolean := false) is
    begin
      rx_reset_s <= '1';
      wait until rising_edge(clock_s);
      rx_reset_s <= '0';

      run(block_read(lba, block_count));

      assert blk_rsp_s.count = block_count
        report "read moved " & to_string(blk_rsp_s.count)
        & " blocks instead of " & to_string(block_count)
        severity failure;

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
      tx_valid_s <= '1';

      if open_ended then
        blk_req_s <= block_write(lba, 0);
      else
        blk_req_s <= block_write(lba, block_count);
      end if;

      loop
        wait until rising_edge(clock_s);
        exit when blk_ack_s.ready = '1';
      end loop;

      blk_req_s <= block_idle;

      if open_ended then
        loop
          wait until rising_edge(clock_s);
          exit when tx_index_s = block_count * block_byte_count_c;
        end loop;

        blk_stop_s <= '1';
      end if;

      loop
        wait until rising_edge(clock_s);
        exit when blk_rsp_s.valid = '1';
      end loop;

      blk_stop_s <= '0';
      tx_valid_s <= '0';

      assert blk_rsp_s.status = BLOCK_OK
        report "block run ended as " & block_status_t'image(blk_rsp_s.status)
        severity failure;
      assert blk_rsp_s.count = block_count
        report "write moved " & to_string(blk_rsp_s.count)
        & " blocks instead of " & to_string(block_count)
        severity failure;
    end procedure;

  begin
    wait until card_ready_s = '1';

    report "card identified" severity note;

    assert info_s.kind = CARD_SDHC
      report "card came out as " & card_kind_t'image(info_s.kind)
      severity failure;
    assert info_s.block_addressed
      report "card does not address blocks" severity failure;
    assert info_s.rca = x"1234"
      report "card address came out as " & to_string(info_s.rca)
      severity failure;
    assert info_s.block_count = card_block_count_c
      report "card says it holds " & to_string(info_s.block_count)
      & " blocks instead of " & to_string(card_block_count_c)
      severity failure;
    assert info_s.width = SDIO_WIDTH_4
      report "bus was not switched to four data lines" severity failure;
    assert info_s.cid = card_register(default_cid_c)
      report "card identification came out as " & to_string(info_s.cid)
      severity failure;

    report "one block each way" severity note;
    read_blocks(x"00001000", 1);
    write_blocks(x"00001100", 1);
    read_blocks(x"00001100", 1, true);

    report "a counted run of blocks" severity note;
    read_blocks(x"00001200", max_block_count_c);

    report "a run of blocks with no count" severity note;
    write_blocks(x"00001300", 3, true);
    read_blocks(x"00001300", 3, true);

    report "sdio card test done";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
