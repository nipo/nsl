library ieee;
use ieee.std_logic_1164.all;

library nsl_data, nsl_usb, nsl_bnoc, nsl_hwdep, nsl_math, nsl_clocking, nsl_memory;
use nsl_data.bytestream.all;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.descriptor.all;
use nsl_usb.utmi.all;
use nsl_usb.ulpi.all;
use nsl_usb.func.all;

entity usb_function is
  generic(
    clock_i_hz_c: natural;
    transactor_count_c: natural
    );
  port(
    clock_i: in std_ulogic;
    app_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    app_reset_n_o : out std_ulogic;

    serial_i : in string(1 to 8);

    ulpi_o: out nsl_usb.ulpi.ulpi8_link2phy;
    ulpi_i: in nsl_usb.ulpi.ulpi8_phy2link;

    -- Transactors
    cmd_i: in nsl_bnoc.framed.framed_ack_array(0 to transactor_count_c-1);
    cmd_o: out nsl_bnoc.framed.framed_req_array(0 to transactor_count_c-1);
    rsp_i: in nsl_bnoc.framed.framed_req_array(0 to transactor_count_c-1);
    rsp_o: out nsl_bnoc.framed.framed_ack_array(0 to transactor_count_c-1);

    -- Serial port
    rx_o  : out nsl_bnoc.pipe.pipe_req_t;
    rx_i  : in  nsl_bnoc.pipe.pipe_ack_t;
    tx_i  : in  nsl_bnoc.pipe.pipe_req_t;
    tx_o  : out  nsl_bnoc.pipe.pipe_ack_t;
    
    online_o : out std_ulogic
    );
end entity;

architecture beh of usb_function is

  constant hs_supported_c      : boolean              := true;
  constant self_powered_c      : boolean              := false;
  constant phy_clock_rate_c    : integer              := 60000000;
  constant bulk_fs_mps_l2_c    : integer range 3 to 6 := 6;
  constant bulk_mps_count_l2_c : integer              := 1;

  constant debug_ep_no_c : endpoint_idx_t := 1;
  constant data_ep_no_c  : endpoint_idx_t := 2;
  constant notif_ep_no_c : endpoint_idx_t := 3;
  
  signal utmi: utmi8_bus;

  type sized_io is
  record
    cmd, rsp : nsl_bnoc.sized.sized_bus;
  end record;

  signal s_out_cmd : transaction_cmd_vector(1 to 2);
  signal s_out_rsp : transaction_rsp_vector(s_out_cmd'range);
  signal s_in_cmd : transaction_cmd_vector(1 to 3);
  signal s_in_rsp : transaction_rsp_vector(s_in_cmd'range);

  signal app_reset_n : std_ulogic;

  signal s_host: sized_io;
  
  type framed_io is
  record
    cmd, rsp : nsl_bnoc.framed.framed_bus;
  end record;

  type routed_io is
  record
    cmd, rsp : nsl_bnoc.routed.routed_bus;
  end record;

  signal s_routed: framed_io;
  signal s_uart_tx, s_uart_rx: nsl_bnoc.pipe.pipe_bus_t;

  signal s_routed_cmd_req: nsl_bnoc.routed.routed_req_array(transactor_count_c-1 downto 0);
  signal s_routed_cmd_ack: nsl_bnoc.routed.routed_ack_array(transactor_count_c-1 downto 0);
  signal s_routed_rsp_req: nsl_bnoc.routed.routed_req_array(transactor_count_c-1 downto 0);
  signal s_routed_rsp_ack: nsl_bnoc.routed.routed_ack_array(transactor_count_c-1 downto 0);

  function routing_table_gen(port_count: integer) return nsl_bnoc.routed.routed_routing_table
  is
    variable ret : nsl_bnoc.routed.routed_routing_table;
  begin
    ret := (others => 0);
    for i in 0 to port_count-1
    loop
      ret(i) := i;
    end loop;
    return ret;
  end function;

  function do_config_descriptor(interval, mps : integer)
    return byte_string
  is
  begin
    return nsl_usb.descriptor.config(
      config_no => 1,
      self_powered => self_powered_c,
      max_power => 150,

      other_desc => nsl_usb.descriptor.interface_association(
        first_interface => 0,
        interface_count => 2,
        str_index => 4,
        class => 2, subclass => 2),

      interface0 => nsl_usb.descriptor.interface(
        interface_number => 0,
        class => 2, subclass => 2,
        functional_desc =>
        nsl_usb.descriptor.cdc_functional_header
        & nsl_usb.descriptor.cdc_functional_acm
        & nsl_usb.descriptor.cdc_functional_union(control => 0, sub0 => 1)
        & nsl_usb.descriptor.cdc_functional_call_management(
          capabilities => 0, data_interface => 1),
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => notif_ep_no_c,
          ttype => "11",
          mps => 8,
          interval => interval)),

      interface1 => nsl_usb.descriptor.interface(
        interface_number => 1,
        class => 10,
        str_index => 4,
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => data_ep_no_c,
          ttype => "10",
          mps => mps),
        endpoint1 => nsl_usb.descriptor.endpoint(
          direction => HOST_TO_DEVICE,
          number => data_ep_no_c,
          ttype => "10",
          mps => mps)),

      interface2 => nsl_usb.descriptor.interface(
        interface_number => 2,
        class => 16#ff#, subclass => 16#ff#, protocol => 16#ff#,
        str_index => 3,
        endpoint0 => nsl_usb.descriptor.endpoint(
          direction => DEVICE_TO_HOST,
          number => debug_ep_no_c,
          ttype => "10",
          mps => mps),
        endpoint1 => nsl_usb.descriptor.endpoint(
          direction => HOST_TO_DEVICE,
          number => debug_ep_no_c,
          ttype => "10",
          mps => mps)));

  end function;
  
begin

  app_reset_n_o <= app_reset_n;

  utmi_converter: nsl_usb.ulpi.utmi8_ulpi8_converter
    generic map(
      phy_model_c => "USB3340",
      dpdm_swap_c => true
      )
    port map(
      reset_n_i => reset_n_i,

      ulpi_i => ulpi_i,
      ulpi_o => ulpi_o,
 
      utmi_data_i => utmi.sie2phy.data,
      utmi_data_o => utmi.phy2sie.data,
      utmi_system_i => utmi.sie2phy.system,
      utmi_system_o => utmi.phy2sie.system
      );

  bus_interface: nsl_usb.device.bus_interface_utmi8
    generic map (
      hs_supported_c => hs_supported_c,
      phy_clock_rate_c => phy_clock_rate_c,

      device_descriptor_c => nsl_usb.descriptor.device(
        hs_support => hs_supported_c,
        mps => 64,
        vendor_id => x"1500",
        product_id => x"df55",
        device_version => x"0100",
        manufacturer_str_index => 1,
        product_str_index => 2,
        serial_str_index => 10
        ),

      device_qualifier_c => nsl_usb.descriptor.device_qualifier(
        usb_version => 16#0200#,
        mps0 => 64),

      fs_config_1_c => do_config_descriptor(interval => 255, mps => 2 ** bulk_fs_mps_l2_c),
      hs_config_1_c => do_config_descriptor(interval => 15, mps => 2 ** 9),

      string_1_c => "Nipo",
      string_2_c => "NEORV32 test platform",
      string_3_c => "Debug",
      string_4_c => "UART0",
      string_10_i_length_c => serial_i'length,
      
      in_ep_count_c => s_in_cmd'length,
      out_ep_count_c => s_out_cmd'length
      )
    port map(
      reset_n_i => reset_n_i,
      app_reset_n_o => app_reset_n,

      hs_o => open,
      suspend_o => open,
      online_o => online_o,

      string_10_i => serial_i,

      phy_system_o => utmi.sie2phy.system,
      phy_system_i => utmi.phy2sie.system,
      phy_data_o => utmi.sie2phy.data,
      phy_data_i => utmi.phy2sie.data,

      frame_number_o => open,
      frame_o => open,
      
      transaction_out_o => s_out_cmd,
      transaction_out_i => s_out_rsp,
      transaction_in_o => s_in_cmd,
      transaction_in_i => s_in_rsp
      );

  debug_bulk_in : nsl_usb.device.device_ep_bulk_in
    generic map(
      hs_supported_c => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => utmi.phy2sie.system.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(debug_ep_no_c),
      transaction_o => s_in_rsp(debug_ep_no_c),
      
      valid_i => s_host.rsp.req.valid,
      data_i => s_host.rsp.req.data,
      ready_o => s_host.rsp.ack.ready,
      room_o  => open,

      flush_i => open
      );

  debug_bulk_out : nsl_usb.device.device_ep_bulk_out
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => utmi.phy2sie.system.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_out_cmd(debug_ep_no_c),
      transaction_o => s_out_rsp(debug_ep_no_c),

      valid_o => s_host.cmd.req.valid,
      data_o => s_host.cmd.req.data,
      ready_i => s_host.cmd.ack.ready,
      available_o => open
      );

  serial_bulk_in : nsl_usb.device.device_ep_bulk_in
    generic map(
      hs_supported_c      => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => utmi.phy2sie.system.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(data_ep_no_c),
      transaction_o => s_in_rsp(data_ep_no_c),
      
      valid_i => s_uart_tx.req.valid,
      data_i  => s_uart_tx.req.data,
      ready_o => s_uart_tx.ack.ready,
      room_o  => open,

      flush_i => '1'
      );

  serial_bulk_out : nsl_usb.device.device_ep_bulk_out
    generic map(
      hs_supported_c => hs_supported_c,
      fs_mps_l2_c => bulk_fs_mps_l2_c,
      mps_count_l2_c => bulk_mps_count_l2_c
      )
    port map(
      clock_i   => utmi.phy2sie.system.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_out_cmd(data_ep_no_c),
      transaction_o => s_out_rsp(data_ep_no_c),

      valid_o => s_uart_rx.req.valid,
      data_o  => s_uart_rx.req.data,
      ready_i => s_uart_rx.ack.ready,
      available_o => open
      );

  serial_fifo_out: nsl_bnoc.pipe.pipe_fifo
    generic map(
      word_count_c => 512,
      clock_count_c => 2
      )
    port map(
      reset_n_i => app_reset_n,
      clock_i(0) => utmi.phy2sie.system.clock,
      clock_i(1) => app_clock_i,

      in_i => s_uart_rx.req,
      in_o => s_uart_rx.ack,

      out_o => rx_o,
      out_i => rx_i
      );
      
  serial_fifo_in: nsl_bnoc.pipe.pipe_fifo
    generic map(
      word_count_c => 512,
      clock_count_c => 2
      )
    port map(
      reset_n_i => app_reset_n,
      clock_i(0) => app_clock_i,
      clock_i(1) => utmi.phy2sie.system.clock,

      in_i => tx_i,
      in_o => tx_o,

      out_i => s_uart_tx.ack,
      out_o => s_uart_tx.req
      );
  
  notify_in : nsl_usb.device.device_ep_in_noop
    port map(
      clock_i   => utmi.phy2sie.system.clock,
      reset_n_i => app_reset_n,

      transaction_i => s_in_cmd(notif_ep_no_c),
      transaction_o => s_in_rsp(notif_ep_no_c)
      );

  to_framed: nsl_bnoc.sized.sized_to_framed
    port map(
      p_resetn => app_reset_n,
      p_clk => clock_i,

      p_in_val => s_host.cmd.req,
      p_in_ack => s_host.cmd.ack,

      p_out_val => s_routed.cmd.req,
      p_out_ack => s_routed.cmd.ack
      );

  from_framed: nsl_bnoc.sized.sized_from_framed
    generic map(
      max_txn_length => 2048
      )
    port map(
      p_resetn => app_reset_n,
      p_clk => clock_i,

      p_in_val => s_routed.rsp.req,
      p_in_ack => s_routed.rsp.ack,

      p_out_val => s_host.rsp.req,
      p_out_ack => s_host.rsp.ack
      );

  cmd_router: nsl_bnoc.routed.routed_router
    generic map(
      in_port_count => 1,
      out_port_count => s_routed_cmd_req'length,
      routing_table => routing_table_gen(s_routed_cmd_req'length)
      )
    port map(
      p_resetn => app_reset_n,
      p_clk => clock_i,
      p_in_val(0) => s_routed.cmd.req,
      p_in_ack(0) => s_routed.cmd.ack,
      p_out_val => s_routed_cmd_req,
      p_out_ack => s_routed_cmd_ack
      );

  rsp_router: nsl_bnoc.routed.routed_router
    generic map(
      in_port_count => s_routed_rsp_req'length,
      out_port_count => 1,
      routing_table => (0, 0, 0, 0,
                        0, 0, 0, 0,
                        0, 0, 0, 0,
                        0, 0, 0, 0)
      )
    port map(
      p_resetn => app_reset_n,
      p_clk => clock_i,
      p_in_val => s_routed_rsp_req,
      p_in_ack => s_routed_rsp_ack,
      p_out_val(0) => s_routed.rsp.req,
      p_out_ack(0) => s_routed.rsp.ack
      );

  by_port: for i in 0 to transactor_count_c-1
  generate
    signal s_routed: routed_io;
  begin
    cmd_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 512,
        clk_count => 2
        )
      port map(
        p_resetn => app_reset_n,
        p_clk(0) => clock_i,
        p_clk(1) => app_clock_i,

        p_in_val  => s_routed_cmd_req(i),
        p_in_ack  => s_routed_cmd_ack(i),

        p_out_val => s_routed.cmd.req,
        p_out_ack => s_routed.cmd.ack
        );

    rsp_fifo: nsl_bnoc.framed.framed_fifo
      generic map(
        depth => 512,
        clk_count => 2
        )
      port map(
        p_resetn => app_reset_n,
        p_clk(0) => app_clock_i,
        p_clk(1) => clock_i,

        p_in_val => s_routed.rsp.req,
        p_in_ack => s_routed.rsp.ack,
        
        p_out_val => s_routed_rsp_req(i),
        p_out_ack => s_routed_rsp_ack(i)
        );
      
    endpoint: nsl_bnoc.routed.routed_endpoint
      port map(
        p_resetn => app_reset_n,
        p_clk => app_clock_i,

        p_cmd_in_val => s_routed.cmd.req,
        p_cmd_in_ack => s_routed.cmd.ack,
        p_rsp_out_val => s_routed.rsp.req,
        p_rsp_out_ack => s_routed.rsp.ack,

        p_cmd_out_val  => cmd_o(i),
        p_cmd_out_ack  => cmd_i(i),
        p_rsp_in_val => rsp_i(i),
        p_rsp_in_ack => rsp_o(i)
        );

  end generate;
  
end architecture;
