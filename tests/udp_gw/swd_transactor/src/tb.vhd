library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_coresight, nsl_simulation, nsl_data, nsl_amba;
use nsl_coresight.testing.all;
use nsl_bnoc.testing.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_coresight.swd.all;
use nsl_data.endian.all;
use nsl_simulation.logging.all;

architecture arch of tb is

  signal done_s : std_ulogic_vector(0 to 0);
  signal master_swd_s : nsl_coresight.swd.swd_master_bus;
  signal slave_swd_s : nsl_coresight.swd.swd_slave_bus;
  
begin

  slave_swd_s.i <= to_slave(master_swd_s.o);
  master_swd_s.i <= to_master(slave_swd_s.o);
  
  master: block is
    constant clock_period_c : time := 10 ns;
    signal clock_s : std_ulogic;
    signal reset_n_s : std_ulogic;

    constant cfg_c: nsl_amba.axi4_stream.config_t
      := nsl_amba.axi4_stream.config(1, last => true);
    signal udp_rx_s, udp_tx_s: nsl_amba.axi4_stream.bus_t;

    type framed_io is
    record
      cmd, rsp: nsl_bnoc.framed.framed_bus_t;
    end record;

    signal dp_s : framed_io;
  begin
    
    net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
      generic map(
        config_c => cfg_c,
        bind_port_c => 4242
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        tx_i => udp_tx_s.m,
        tx_o => udp_tx_s.s,

        rx_o => udp_rx_s.m,
        rx_i => udp_rx_s.s
        );

    rx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        prefix_c => "UDP RX",
        config_c => cfg_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => udp_rx_s
        );

    tx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
      generic map(
        prefix_c => "UDP TX",
        config_c => cfg_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        bus_i => udp_tx_s
        );
    
    dp_s.cmd.req <= nsl_bnoc.framed.framed_flit(
      data => nsl_amba.axi4_stream.bytes(cfg_c, udp_rx_s.m)(0),
      last => nsl_amba.axi4_stream.is_last(cfg_c, udp_rx_s.m),
      valid => nsl_amba.axi4_stream.is_valid(cfg_c, udp_rx_s.m));
    udp_rx_s.s <= nsl_amba.axi4_stream.accept(cfg_c, dp_s.cmd.ack.ready = '1');

    udp_tx_s.m <= nsl_amba.axi4_stream.transfer(
      cfg_c,
      bytes => (0 => dp_s.rsp.req.data),
      valid => dp_s.rsp.req.valid = '1',
      last => dp_s.rsp.req.last = '1');
    dp_s.rsp.ack.ready <= '1' when nsl_amba.axi4_stream.is_ready(cfg_c, udp_tx_s.s) else '0';
    
    dp: nsl_coresight.transactor.dp_framed_transactor
      port map(
        clock_i  => clock_s,
        reset_n_i => reset_n_s,
        
        cmd_i => dp_s.cmd.req,
        cmd_o => dp_s.cmd.ack,
        rsp_o => dp_s.rsp.req,
        rsp_i => dp_s.rsp.ack,

        swd_o => master_swd_s.o,
        swd_i => master_swd_s.i
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => clock_period_c,
        reset_duration(0) => 42 ns,
        reset_n_o(0) => reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;
  
  dut: block is
    constant clock_period_c : time := 20 ns;
    signal clock_s : std_ulogic;
    signal reset_n_s : std_ulogic;

    constant dp_idr_c : unsigned := x"04567e11";

    signal dapbus_gen, dapbus_memap : nsl_coresight.dapbus.dapbus_bus;
    constant axi_cfg_c : nsl_amba.axi4_mm.config_t := nsl_amba.axi4_mm.config(address_width => 32, data_bus_width => 32);
    signal axi_s : nsl_amba.axi4_mm.bus_t;
    signal ctrl, ctrl_w, stat :std_ulogic_vector(31 downto 0);
  begin

    dp: nsl_coresight.dp.swdp_sync
      generic map(
        idr => dp_idr_c
        )
      port map(
        ref_clock_i => clock_s,
        ref_reset_n_i => reset_n_s,

        swd_i => slave_swd_s.i,
        swd_o => slave_swd_s.o,

        dap_o => dapbus_gen.ms,
        dap_i => dapbus_gen.sm,

        ctrl_o => ctrl,
        stat_i => stat,
        abort_o => open
        );

    stat_update: process(ctrl)
    begin
      stat <= ctrl;
      stat(27) <= ctrl(26);
      stat(29) <= ctrl(28);
      stat(31) <= ctrl(30);
    end process;
    
    interconnect: nsl_coresight.dapbus.dapbus_interconnect
      generic map(
        access_port_count => 1
        )
      port map(
        s_i => dapbus_gen.ms,
        s_o => dapbus_gen.sm,

        m_i(0) => dapbus_memap.sm,
        m_o(0) => dapbus_memap.ms
        );

    mem_ap: nsl_coresight.ap.ap_axi4_lite
      generic map(
        rom_base => x"00000000",
        config_c => axi_cfg_c,
        idr => x"01234e11"
        )
      port map(
        clk_i => clock_s,
        reset_n_i => reset_n_s,

        dbgen_i => ctrl(28),
        spiden_i => '1',

        dap_i => dapbus_memap.ms,
        dap_o => dapbus_memap.sm,

        axi_o => axi_s.m,
        axi_i => axi_s.s
        );

    mem: nsl_amba.ram.axi4_mm_lite_ram
      generic map (
        byte_size_l2_c => 12,
        config_c => axi_cfg_c
        )
      port map (
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        axi_i => axi_s.m,
        axi_o => axi_s.s
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => clock_period_c,
        reset_duration(0) => 42 ns,
        reset_n_o(0) => reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

end;
