library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;

entity tb is
end entity;

architecture sim of tb is

  constant apb_cfg_c : nsl_amba.apb.config_t :=
    nsl_amba.apb.config(address_width => 12, data_bus_width => 32, err => true);
  constant stream_cfg_c : config_t := config(bytes => 1, last => true);
  constant burst_length_l2_c : natural := 8;

  -- identify payload (bridge appends a status byte)
  constant identify_c : byte_string := (x"a1", x"b2", x"c3");

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic := '0';
  signal done_s : boolean := false;

  signal cmd_m : master_t;
  signal cmd_s : slave_t;
  signal rsp_m : master_t;
  signal rsp_s : slave_t;

  signal apb_m : nsl_amba.apb.master_t;
  signal apb_s : nsl_amba.apb.slave_t;

  procedure stream_xfer(
    constant cmd : in byte_string;
    constant expected : in byte_string;
    signal clock : in std_ulogic;
    signal txm : out master_t;
    signal txs : in slave_t;
    signal rxm : in master_t;
    signal rxs : out slave_t)
  is
    variable idx : natural := 0;
    variable b : byte;
  begin
    rxs <= accept(stream_cfg_c, false);

    for i in cmd'range loop
      txm <= transfer(stream_cfg_c,
                      bytes => byte_string'(0 => cmd(i)),
                      valid => true,
                      last => (i = cmd'high));
      loop
        wait until rising_edge(clock);
        exit when is_ready(stream_cfg_c, txs);
      end loop;
    end loop;
    txm <= transfer_defaults(stream_cfg_c);

    loop
      rxs <= accept(stream_cfg_c, true);
      wait until rising_edge(clock);
      if is_valid(stream_cfg_c, rxm) then
        b := bytes(stream_cfg_c, rxm)(0);
        assert idx < expected'length
          report "response longer than expected" severity failure;
        assert b = expected(expected'low + idx)
          report "response byte " & integer'image(idx) & " mismatch" severity failure;
        idx := idx + 1;
        exit when is_last(stream_cfg_c, rxm);
      end if;
    end loop;
    rxs <= accept(stream_cfg_c, false);

    assert idx = expected'length
      report "response shorter than expected" severity failure;
  end procedure;

begin

  dut: nsl_amba.stream_apb.apb_stream_bridge
    generic map(
      apb_config_c => apb_cfg_c,
      stream_config_c => stream_cfg_c,
      burst_length_l2_c => burst_length_l2_c,
      identify_c => identify_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      rx_i => cmd_m,
      rx_o => cmd_s,
      tx_o => rsp_m,
      tx_i => rsp_s,
      apb_o => apb_m,
      apb_i => apb_s
      );

  ram: nsl_amba.ram.apb_ram
    generic map(
      config_c => apb_cfg_c,
      byte_size_l2_c => 12
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      apb_i => apb_m,
      apb_o => apb_s
      );

  clock_gen: process
  begin
    while not done_s loop
      clock_s <= '0';
      wait for 5 ns;
      clock_s <= '1';
      wait for 5 ns;
    end loop;
    wait;
  end process;

  stim: process
  begin
    cmd_m <= transfer_defaults(stream_cfg_c);
    rsp_s <= accept(stream_cfg_c, false);
    reset_n_s <= '0';
    wait for 23 ns;
    wait until falling_edge(clock_s);
    reset_n_s <= '1';
    wait until falling_edge(clock_s);

    -- identify -> payload + status 0x00
    stream_xfer(cmd => byte_string'(x"ff", x"00"),
                expected => byte_string'(x"a1", x"b2", x"c3", x"00"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    -- write 0xdeadbeef at address 0 -> status 0x00
    stream_xfer(cmd => byte_string'(x"00", x"00", x"00", x"ef", x"be", x"ad", x"de"),
                expected => byte_string'(0 => x"00"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    -- write 0x11223344 at address 4 -> status 0x00
    stream_xfer(cmd => byte_string'(x"00", x"04", x"00", x"44", x"33", x"22", x"11"),
                expected => byte_string'(0 => x"00"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    -- read 1 word at address 0 (count field 0 = one word) -> data (LE) + status
    stream_xfer(cmd => byte_string'(x"80", x"00", x"00", x"00"),
                expected => byte_string'(x"ef", x"be", x"ad", x"de", x"00"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    -- read 2 words at address 0 (count field 1, tests auto-increment)
    stream_xfer(cmd => byte_string'(x"80", x"00", x"00", x"01"),
                expected => byte_string'(x"ef", x"be", x"ad", x"de",
                                         x"44", x"33", x"22", x"11", x"00"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    -- short frame: opcode only, last -> error status
    stream_xfer(cmd => byte_string'(0 => x"80"),
                expected => byte_string'(0 => x"01"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    -- short frame: last mid-address -> error status
    stream_xfer(cmd => byte_string'(x"80", x"00"),
                expected => byte_string'(0 => x"01"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    -- short frame: last mid-write-data (three of four word bytes) -> error status
    stream_xfer(cmd => byte_string'(x"00", x"00", x"00", x"11", x"22", x"33"),
                expected => byte_string'(0 => x"01"),
                clock => clock_s,
                txm => cmd_m, txs => cmd_s, rxm => rsp_m, rxs => rsp_s);

    report "apb_stream_bridge testbench PASSED" severity note;
    done_s <= true;
    wait;
  end process;

end architecture;
