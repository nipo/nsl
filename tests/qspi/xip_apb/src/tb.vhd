library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library nsl_qspi, nsl_amba, nsl_bnoc, nsl_data, nsl_simulation;
use nsl_amba.axi4_mm.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use work.qspi_test_support.all;

entity tb is
end entity;

architecture test of tb is
  constant axi_config_c: nsl_amba.axi4_mm.config_t := nsl_amba.axi4_mm.config(
    address_width => 32, data_bus_width => 32, id_width => 4,
    max_length => 4, size => true, burst => true);
  constant apb_config_c: nsl_amba.apb.config_t := nsl_amba.apb.apb4_config(
    address_width => 8, data_bus_width => 32, strb => true, err => true);
  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal done_s: boolean := false;
  signal axi_s: nsl_amba.axi4_mm.bus_t;
  signal apb_s: nsl_amba.apb.bus_t;
  signal command_s, response_s: framed_bus;
  signal pins_s: nsl_qspi.qspi.qspi_master_o;
  signal pin_input_s: nsl_qspi.qspi.qspi_master_i;
  signal dq_s, enable_s: std_ulogic_vector(3 downto 0);
  signal completed_s: natural;
begin
  clock_s <= not clock_s after 5 ns when not done_s else '0';
  lanes: for i in 0 to 3 generate
    dq_s(i) <= pins_s.dq(i).v;
    enable_s(i) <= pins_s.dq(i).en;
  end generate;

  dut: nsl_qspi.xip.axi4_mm_qspi_xip_apb
    generic map(config_c => axi_config_c, apb_config_c => apb_config_c)
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             apb_i => apb_s.m, apb_o => apb_s.s,
             axi_i => axi_s.m, axi_o => axi_s.s,
             cmd_o => command_s.req, cmd_i => command_s.ack,
             rsp_i => response_s.req, rsp_o => response_s.ack);
  wire: nsl_qspi.transactor.qspi_framed_transactor
    port map(clock_i => clock_s, reset_n_i => reset_n_s,
             qspi_o => pins_s, qspi_i => pin_input_s,
             cmd_i => command_s.req, cmd_o => command_s.ack,
             rsp_o => response_s.req, rsp_i => response_s.ack);
  flash: work.qspi_test_support.qspi_flash_model
    port map(cs_n_i => pins_s.cs_n, sck_i => pins_s.sck,
             dq_i => dq_s, enable_i => enable_s, dq_o => pin_input_s.dq,
             opcode_i => x"eb", address_i => x"123457a0",
             address_bytes_i => 4, address_lanes_i => 4, data_lanes_i => 4,
             dummy_cycles_i => 6, data_bytes_i => 4, half_period_i => 20 ns,
             completed_o => completed_s);

  timeout: process
  begin
    wait for 1 ms;
    assert done_s report "QSPI XIP APB timeout" severity failure;
    wait;
  end process;

  stimulus: process
    variable value_v: unsigned(31 downto 0);
    variable error_v: boolean;
    variable expected_v: byte_string(0 to 3);
  begin
    apb_s.m <= nsl_amba.apb.transfer_idle(apb_config_c);
    axi_s.m.aw <= address_defaults(axi_config_c);
    axi_s.m.w <= write_data_defaults(axi_config_c);
    axi_s.m.b <= accept(axi_config_c, false);
    axi_s.m.ar <= address_defaults(axi_config_c);
    axi_s.m.r <= accept(axi_config_c, false);
    wait for 30 ns;
    reset_n_s <= '1';
    wait until falling_edge(clock_s);

    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 0, reg_lsb => 2, val => x"00000000");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 2, reg_lsb => 2, val => x"00000000");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 3, reg_lsb => 2, val => x"00000003");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 4, reg_lsb => 2, val => x"0008006b");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 7, reg_lsb => 2, val => x"00000000");

    nsl_amba.apb.apb_write(apb_config_c, clock_s, apb_s.s, apb_s.m,
      addr => x"04", val => x"12345600", strb => "0011", err => error_v);
    assert error_v report "Partial APB write was not rejected" severity failure;
    wait until rising_edge(clock_s);
    wait until falling_edge(clock_s);
    -- apb_regmap reports an error but still pulses its abstract write strobe.
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 1, reg_lsb => 2, val => x"12345600");

    nsl_amba.apb.apb_write(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 1, reg_lsb => 2, val => x"12345600", strb => "1111");
    nsl_amba.apb.apb_write(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 2, reg_lsb => 2, val => x"00000001", strb => "1111");
    nsl_amba.apb.apb_write(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 4, reg_lsb => 2, val => x"000603eb", strb => "1111");
    nsl_amba.apb.apb_write(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 0, reg_lsb => 2, val => x"00000003", strb => "1111");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 0, reg_lsb => 2, val => x"00000003");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 1, reg_lsb => 2, val => x"12345600");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 2, reg_lsb => 2, val => x"00000001");
    nsl_amba.apb.apb_check(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 4, reg_lsb => 2, val => x"000603eb");

    axi_s.m.ar <= nsl_amba.axi4_mm.address(
      axi_config_c, id => "0101", addr => x"000001a0",
      len_m1 => to_unsigned(0, axi_config_c.len_width),
      size_l2 => to_unsigned(2, 3));
    loop
      wait until rising_edge(clock_s);
      exit when axi_s.s.ar.ready = '1';
    end loop;
    wait until falling_edge(clock_s);
    axi_s.m.ar <= address_defaults(axi_config_c);

    -- Changes after AR acceptance must not affect the accepted request.
    nsl_amba.apb.apb_write(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 0, reg_lsb => 2, val => x"00000000", strb => "1111");
    nsl_amba.apb.apb_write(apb_config_c, clock_s, apb_s.s, apb_s.m,
      reg => 1, reg_lsb => 2, val => x"87654321", strb => "1111");
    axi_s.m.r <= accept(axi_config_c, true);
    loop
      wait until rising_edge(clock_s);
      exit when axi_s.s.r.valid = '1';
    end loop;
    for lane in 0 to 3 loop
      expected_v(lane) := memory_byte(unsigned'(x"123457a0") + lane);
    end loop;
    assert nsl_amba.axi4_mm.resp(axi_config_c, axi_s.s.r) = RESP_OKAY
      and nsl_amba.axi4_mm.id(axi_config_c, axi_s.s.r) = "0101"
      and nsl_amba.axi4_mm.bytes(axi_config_c, axi_s.s.r) = expected_v
      and nsl_amba.axi4_mm.is_last(axi_config_c, axi_s.s.r)
      report "APB-configured XIP response mismatch" severity failure;
    assert completed_s = 1 report "APB snapshot did not produce one flash frame" severity failure;

    report "QSPI XIP APB: reset, map, strobes, profile and snapshot passed";
    done_s <= true;
    nsl_simulation.control.terminate(0);
    wait;
  end process;
end architecture;
