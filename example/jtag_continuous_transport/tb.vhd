library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_jtag, nsl_bnoc, nsl_simulation, nsl_clocking;

-- Continuous-transport software-driver demo platform.
--
-- Two TCP sockets bracket a real JTAG link:
--
--   host :4242  (ATE side)                       host :4243  (application side)
--       |                                              |
--   tcp_framed_gateway                            tcp_framed_gateway
--       |  framed cmd/rsp (HDLC over the socket)       |  framed app data (HDLC)
--   framed_fifo x2                                framed_fifo x2
--       |                                              |
--   nsl_jtag.transactor.framed_ate  --JTAG-->  jtag_sim_tap --(globals)-->
--                                              continuous_transport_slave
--
-- A host program connects to :4242 and speaks the JTAG transactor command
-- protocol (selecting the user IR, then shifting continuous-transport batches).
-- Whatever it pushes through the transport surfaces, as a framed byte stream,
-- on :4243, and vice versa. The simulation never terminates (done stays low),
-- so the built simulator just serves both sockets until killed.
entity tb is
end entity;

architecture arch of tb is

  constant idcode_c : std_ulogic_vector(31 downto 0) := x"87654321";
  constant idcode_instruction_c : std_ulogic_vector(3 downto 0) := x"2";
  constant user0_instruction_c : std_ulogic_vector(3 downto 0) := x"8";

  constant ate_port_c : natural := 4242;
  constant app_port_c : natural := 4243;

  -- Never asserted: the platform runs forever.
  signal done_s : std_ulogic_vector(0 to 0) := (others => '0');

  -- JTAG link between the ATE and the simulated TAP.
  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

  component tcp_framed_gateway is
    generic(
      bind_port_c : natural
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;
      rx_o : out nsl_bnoc.framed.framed_req_t;
      rx_i : in  nsl_bnoc.framed.framed_ack_t;
      tx_i : in  nsl_bnoc.framed.framed_req_t;
      tx_o : out nsl_bnoc.framed.framed_ack_t
      );
  end component;

begin

  ate_i <= transport nsl_jtag.jtag.to_ate(tap_o);
  tap_i <= transport nsl_jtag.jtag.to_tap(ate_o);

  -- ATE side: socket :4242 <-> transactor command/response.
  ate: block is
    signal clock_s : std_ulogic := '0';
    signal reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;

    signal sock_rx, sock_tx : nsl_bnoc.framed.framed_bus_t;  -- gateway side
    signal cmd, rsp : nsl_bnoc.framed.framed_bus_t;          -- transactor side
  begin
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => clock_s,
        data_i => async_reset_n_s,
        data_o => reset_n_s
        );

    gateway: tcp_framed_gateway
      generic map(
        bind_port_c => ate_port_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        rx_o => sock_rx.req,
        rx_i => sock_rx.ack,
        tx_i => sock_tx.req,
        tx_o => sock_tx.ack
        );

    cmd_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 512,
        clk_count => 1
        )
      port map(
        p_resetn => reset_n_s,
        p_clk(0) => clock_s,
        p_in_val => sock_rx.req,
        p_in_ack => sock_rx.ack,
        p_out_val => cmd.req,
        p_out_ack => cmd.ack
        );

    rsp_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 512,
        clk_count => 1
        )
      port map(
        p_resetn => reset_n_s,
        p_clk(0) => clock_s,
        p_in_val => rsp.req,
        p_in_ack => rsp.ack,
        p_out_val => sock_tx.req,
        p_out_ack => sock_tx.ack
        );

    transactor: nsl_jtag.transactor.framed_ate
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        cmd_i => cmd.req,
        cmd_o => cmd.ack,
        rsp_o => rsp.req,
        rsp_i => rsp.ack,
        jtag_o => ate_o,
        jtag_i => ate_i,
        system_reset_n_o => open
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => 10 ns,
        reset_duration(0) => 50 ns,
        reset_n_o(0) => async_reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

  -- Application side: simulated TAP + continuous-transport slave, looped to
  -- socket :4243.
  app: block is
    signal clock_s : std_ulogic := '0';
    signal reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;

    signal sock_rx, sock_tx : nsl_bnoc.framed.framed_bus_t;   -- gateway side
    signal slave_rx, slave_tx : nsl_bnoc.framed.framed_bus_t; -- slave system side
  begin
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => clock_s,
        data_i => async_reset_n_s,
        data_o => reset_n_s
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
        rx_fifo_depth_c => 256,
        tx_fifo_depth_c => 256,
        preamble_count_c => 2
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        reset_n_o => open,
        tx_i => slave_tx.req,
        tx_o => slave_tx.ack,
        rx_o => slave_rx.req,
        rx_i => slave_rx.ack
        );

    -- Socket -> slave TX (application sends into the transport).
    tx_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 512,
        clk_count => 1
        )
      port map(
        p_resetn => reset_n_s,
        p_clk(0) => clock_s,
        p_in_val => sock_rx.req,
        p_in_ack => sock_rx.ack,
        p_out_val => slave_tx.req,
        p_out_ack => slave_tx.ack
        );

    -- Slave RX -> socket (application receives from the transport).
    rx_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 512,
        clk_count => 1
        )
      port map(
        p_resetn => reset_n_s,
        p_clk(0) => clock_s,
        p_in_val => slave_rx.req,
        p_in_ack => slave_rx.ack,
        p_out_val => sock_tx.req,
        p_out_ack => sock_tx.ack
        );

    gateway: tcp_framed_gateway
      generic map(
        bind_port_c => app_port_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        rx_o => sock_rx.req,
        rx_i => sock_rx.ack,
        tx_i => sock_tx.req,
        tx_o => sock_tx.ack
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => 7 ns,
        reset_duration(0) => 50 ns,
        reset_n_o(0) => async_reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

end architecture;
