library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library nsl_qspi, nsl_bnoc, nsl_data, nsl_simulation;
use nsl_qspi.transactor.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use work.qspi_test_support.all;

entity tb is
end entity;

architecture test of tb is
  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;
  signal cmd_s, rsp_s: framed_bus;
  signal pins_s: nsl_qspi.qspi.qspi_master_o;
  signal input_s: nsl_qspi.qspi.qspi_master_i;
  signal dq_s, enable_s: std_ulogic_vector(3 downto 0);
  signal opcode_s: byte := x"03";
  signal address_s: unsigned(31 downto 0) := x"00123458";
  signal address_bytes_s: positive := 3;
  signal address_lanes_s, data_lanes_s: positive := 1;
  signal dummy_s: natural := 0;
  signal data_bytes_s: positive := 7;
  signal half_period_s: time := 10 ns;
  signal completed_s: natural;
begin
  clock_s <= not clock_s after 5 ns when not done_s else '0';
  lanes: for i in 0 to 3 generate
    dq_s(i) <= pins_s.dq(i).v;
    enable_s(i) <= pins_s.dq(i).en;
  end generate;
  dut: nsl_qspi.transactor.qspi_framed_transactor
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             qspi_o => pins_s, qspi_i => input_s,
             cmd_i => cmd_s.req, cmd_o => cmd_s.ack,
             rsp_o => rsp_s.req, rsp_i => rsp_s.ack);
  flash: work.qspi_test_support.qspi_flash_model
    port map(cs_n_i => pins_s.cs_n, sck_i => pins_s.sck,
             dq_i => dq_s, enable_i => enable_s, dq_o => input_s.dq,
             opcode_i => opcode_s, address_i => address_s,
             address_bytes_i => address_bytes_s, address_lanes_i => address_lanes_s,
             data_lanes_i => data_lanes_s, dummy_cycles_i => dummy_s,
             data_bytes_i => data_bytes_s, half_period_i => half_period_s,
             completed_o => completed_s);

  timeout: process
  begin
    wait for 1 ms;
    assert done_s report "QSPI transactor timeout" severity failure;
    wait;
  end process;

  stimulus: process
    procedure tick is
    begin
      wait until rising_edge(clock_s);
      wait until falling_edge(clock_s);
    end procedure;

    procedure send(data: byte_string) is
    begin
      for i in data'range loop
        cmd_s.req <= framed_flit(data(i), i = data'right);
        loop
          wait until rising_edge(clock_s);
          exit when cmd_s.ack.ready = '1';
        end loop;
        wait until falling_edge(clock_s);
        cmd_s.req <= framed_req_idle_c;
        if i /= data'right then
          for j in 0 to i mod 3 loop
            tick;
            assert pins_s.cs_n = '1' report "CS asserted before complete command frame" severity failure;
          end loop;
        end if;
      end loop;
    end procedure;

    procedure receive(count: natural; status: byte := qspi_status_ok_c) is
      variable held_v: framed_req;
    begin
      for i in 0 to count loop
        rsp_s.ack <= framed_accept(false);
        loop
          wait until rising_edge(clock_s);
          exit when rsp_s.req.valid = '1';
        end loop;
        held_v := rsp_s.req;
        wait until falling_edge(clock_s);
        for j in 1 to 4 loop
          tick;
          assert rsp_s.req = held_v report "Framed response changed while stalled" severity failure;
          assert pins_s.cs_n = '1' report "Response backpressure holds CS active" severity failure;
        end loop;
        if i = count then
          assert held_v.data = status and held_v.last = '1'
            report "Missing final QSPI status or wrong frame boundary" severity failure;
        else
          assert held_v.data = memory_byte(address_s + i) and held_v.last = '0'
            report "QSPI receive data/order/frame boundary mismatch" severity failure;
        end if;
        rsp_s.ack <= framed_accept(true);
        tick;
        rsp_s.ack <= framed_accept(false);
      end loop;
      for i in 1 to 4 loop
        tick;
        assert rsp_s.req.valid = '0' report "Duplicate QSPI response" severity failure;
      end loop;
    end procedure;
  begin
    cmd_s.req <= framed_req_idle_c;
    rsp_s.ack <= framed_accept(false);
    wait for 30 ns;
    assert pins_s.cs_n = '1' and pins_s.sck = '0' and enable_s = "0000"
      report "Reset must release QSPI pins" severity failure;
    reset_n_s <= '1';
    tick;
    send(qspi_timing(1, 3, 4) & qspi_tx(byte_string'(x"03", x"12", x"34", x"58"))
         & qspi_rx(3) & qspi_rx(4));
    receive(7);
    assert completed_s = 1 severity failure;

    opcode_s <= x"0b";
    dummy_s <= 8;
    half_period_s <= 30 ns;
    send(qspi_timing(divider => 3) & qspi_tx(byte_string'(x"0b", x"12", x"34", x"58"))
         & qspi_dummy(8) & qspi_rx(7));
    receive(7);

    opcode_s <= x"6b";
    data_lanes_s <= 4;
    half_period_s <= 20 ns;
    send(qspi_timing(divider => 2) & qspi_tx(byte_string'(x"6b", x"12", x"34", x"58"))
         & qspi_dummy(8) & qspi_rx(7, true));
    receive(7);

    opcode_s <= x"eb";
    address_s <= x"89abcdef";
    address_bytes_s <= 4;
    address_lanes_s <= 4;
    dummy_s <= 6;
    half_period_s <= 10 ns;
    send(qspi_timing & qspi_tx(byte_string'(0 => x"eb"))
         & qspi_tx(byte_string'(x"89", x"ab", x"cd", x"ef"), true)
         & qspi_dummy(6) & qspi_rx(7, true));
    receive(7);
    assert completed_s = 4 severity failure;

    -- Malformed commands must be rejected before the flash sees CS.
    send(byte_string'(0 => x"ff"));
    receive(0, qspi_status_error_c);
    send(qspi_timing & byte_string'(qspi_cmd_tx4_c, x"01", x"a5"));
    receive(0, qspi_status_error_c);
    send(qspi_timing & qspi_rx(256) & qspi_rx(1));
    receive(0, qspi_status_error_c);
    assert completed_s = 4 and pins_s.cs_n = '1' severity failure;

    report "QSPI transactor: four wire profiles, framing, stalls and malformed commands passed";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;
end architecture;
