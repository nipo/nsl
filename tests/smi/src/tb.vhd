library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_smi, nsl_simulation, nsl_amba, nsl_data;

architecture arch of tb is

  signal master_clock_s : std_ulogic := '0';
  signal slave_clock_s : std_ulogic := '0';
  signal reset_n_async_s : std_ulogic;

  signal done_s : std_ulogic_vector(0 to 0);
  signal smi_s : nsl_smi.smi.smi_bus;

begin

  slave: block is
    use nsl_amba.axi4_mm.all;

    signal bus_s: bus_t;
    constant config_c : config_t := config(address_width => 7,
                                           data_bus_width => 32);

    signal reg_no_s: natural range 0 to 15;
    signal w_value_s, r_value_s : unsigned(15 downto 0);
    signal w_value_msb_s, r_value_msb_s : unsigned(15 downto 0);
    signal w_strobe_s : std_ulogic;

    signal reg0, reg1: unsigned(15 downto 0);

    signal smi_i_s : nsl_smi.smi.smi_slave_i;
    signal smi_o_s : nsl_smi.smi.smi_slave_o;

    alias clock_s : std_ulogic is slave_clock_s;
    signal reset_n_s : std_ulogic;
    
  begin
    io_driver: nsl_smi.smi.smi_slave_line_driver
      port map(
        smi_io => smi_s,
        slave_o => smi_i_s,
        slave_i => smi_o_s
        );
    
    reset_sync_slave: nsl_clocking.async.async_edge
      port map(
        data_i => reset_n_async_s,
        data_o => reset_n_s,
        clock_i => clock_s
        );

    writing: process(clock_s, reset_n_s) is
    begin
      if rising_edge(clock_s) then
        if w_strobe_s = '1' then
          case reg_no_s is
            when 0 =>
              reg0 <= w_value_s;

            when 1 =>
              reg1 <= w_value_s;

            when others =>
              null;
          end case;
        end if;
      end if;

      if reset_n_s = '0' then
      end if;
    end process;

      with reg_no_s select r_value_s <=
        reg0        when 0,
        x"f00d" when 1,
        reg1        when 2,
        x"beef" when others;

    smi_slave: nsl_smi.slave.smi_c22_slave_axi_master
      generic map(
        phy_addr_c => "00011",
        config_c => config_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        smi_i => smi_i_s,
        smi_o => smi_o_s,

        regmap_i => bus_s.s,
        regmap_o => bus_s.m
        );

    dumper: nsl_amba.axi4_mm.axi4_mm_dumper
      generic map(
        config_c => config_c,
        prefix_c => "MM"
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        master_i => bus_s.m,
        slave_i => bus_s.s
      );

    dut: nsl_amba.axi4_mm.axi4_mm_lite_regmap
      generic map(
        config_c => config_c,
        reg_count_l2_c => 4
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        axi_i => bus_s.m,
        axi_o => bus_s.s,

        reg_no_o => reg_no_s,
        w_value_o(31 downto 16) => w_value_msb_s,
        w_value_o(15 downto 0) => w_value_s,
        w_strobe_o => w_strobe_s,
        r_value_i(31 downto 16) => r_value_msb_s,
        r_value_i(15 downto 0) => r_value_s
        );

    r_value_msb_s <= (others => '0');
  end block;

  master: block is
    use nsl_data.bytestream.all;
    use nsl_simulation.logging.all;
    use nsl_bnoc.testing.all;
    use nsl_smi.transactor.all;
    
    alias clock_s : std_ulogic is master_clock_s;
    signal reset_n_s : std_ulogic;
    signal cmd_s, rsp_s : nsl_bnoc.framed.framed_bus;
    signal smi_i_s : nsl_smi.smi.smi_master_i;
    signal smi_o_s : nsl_smi.smi.smi_master_o;
    shared variable rsp_v, cmd_v: framed_queue_root;

    procedure do_c22_read(
      ctx: string;
      cmd_q, rsp_q: inout framed_queue_root;
      phyad, addr: natural; rdata: unsigned(15 downto 0); ok: boolean := true)
    is
      constant cmd: byte_string := nsl_smi.transactor.c22_read(phyad, addr);
      constant rsp: byte_string := nsl_smi.transactor.read_rsp(rdata, ok);
    begin
      framed_txn_check(ctx, cmd_q, rsp_q, cmd, rsp, LOG_LEVEL_WARNING);
    end procedure;

    procedure do_c22_write(
      ctx: string;
      cmd_q, rsp_q: inout framed_queue_root;
      phyad, addr: natural; wdata: unsigned(15 downto 0))
    is
      constant cmd: byte_string := nsl_smi.transactor.c22_write(phyad, addr, wdata);
      constant rsp: byte_string := nsl_smi.transactor.write_rsp;
    begin
      framed_txn_check(ctx, cmd_q, rsp_q, cmd, rsp, LOG_LEVEL_WARNING);
    end procedure;

  begin

    stim: process is
    begin
      done_s(0) <= '0';

      wait for 100 ns;

      do_c22_write("write 0", cmd_v, rsp_v, 3, 0, x"1234");
      do_c22_write("write 1", cmd_v, rsp_v, 3, 1, x"4567");
      do_c22_read("read  0", cmd_v, rsp_v, 3, 0, x"1234", true);
      do_c22_write("write err", cmd_v, rsp_v, 7, 0, x"1234");
      do_c22_read("read err", cmd_v, rsp_v, 7, 0, "----------------", false);
      do_c22_read("read  1", cmd_v, rsp_v, 3, 1, x"f00d", true);
      do_c22_read("read  2", cmd_v, rsp_v, 3, 2, x"4567", true);
      do_c22_read("read  3", cmd_v, rsp_v, 3, 3, x"beef", true);
      
      wait for 3000 ns;
      
      done_s(0) <= '1';
      wait;
    end process;

    reset_sync_master: nsl_clocking.async.async_edge
      port map(
        data_i => reset_n_async_s,
        data_o => reset_n_s,
        clock_i => clock_s
        );

    rsp_reader: process is
      variable data: byte_stream;
    begin
      framed_queue_init(rsp_v);

      wait for 200 ns;

      framed_queue_slave_worker(rsp_s.req, rsp_s.ack, clock_s, rsp_v);
    end process;

    cmd_writer: process is
      variable data: byte_stream;
    begin
      framed_queue_init(cmd_v);

      wait for 200 ns;

      framed_queue_master_worker(cmd_s.req, cmd_s.ack, clock_s, cmd_v, "cmd");
    end process;
    
    smi_master: nsl_smi.transactor.smi_framed_transactor
      generic map(
        clock_freq_c => 100e6,
        mdc_freq_c => 25e6
      )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        
        smi_o => smi_o_s,
        smi_i => smi_i_s,

        cmd_i => cmd_s.req,
        cmd_o => cmd_s.ack,
        rsp_i => rsp_s.ack,
        rsp_o => rsp_s.req
        );

    io_driver: nsl_smi.smi.smi_master_line_driver
      port map(
        mdc_o => smi_s.mdc,
        mdio_io => smi_s.mdio,
        master_o => smi_i_s,
        master_i => smi_o_s
        );
  end block;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 8 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => reset_n_async_s,
      clock_o(0) => master_clock_s,
      clock_o(1) => slave_clock_s,
      done_i => done_s
      );

end;
