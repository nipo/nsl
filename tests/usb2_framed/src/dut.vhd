library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_memory, nsl_clocking, nsl_hwdep, nsl_bnoc;
use nsl_usb.utmi.all;

entity dut is
  port(
    reset_n_i : in std_logic;

    utmi_data_o : out utmi_data8_sie2phy;
    utmi_data_i : in utmi_data8_phy2sie;
    utmi_system_o : out utmi_system_sie2phy;
    utmi_system_i : in utmi_system_phy2sie
    );
end entity;

architecture beh of dut is

  signal s_out, s_in : nsl_bnoc.framed.framed_bus;

  signal reset_n_sys : std_ulogic;
  signal clock_int, reset_n_int : std_ulogic;

  signal online : std_ulogic;

begin

  clk_gen: process
  begin
    while true
    loop
      clock_int <= '0';
      wait for 8333 ps;
      clock_int <= '1';
      wait for 8333 ps;
    end loop;
  end process;

  reset_gen: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_int,
      data_i => reset_n_i,
      data_o => reset_n_int
      );
 
  usb_device: nsl_usb.func.vendor_framed_pair
    generic map(
      vendor_id_c => x"1234",
      product_id_c => x"5678",
      device_version_c => x"0100",
      manufacturer_c => "NSL",
      product_c => "Some 64-byte long string descr.",
      hs_supported_c => true,
      self_powered_c => false,
      framed_fs_mps_l2_c => 6,
      framed_double_buffer_c => true,
      serial_i_length_c => 4
      )
    port map(
      reset_n_i => reset_n_int,
      app_reset_n_o => reset_n_sys,
      online_o => online,
      serial_i => "1234",

      phy_system_o => utmi_system_o,
      phy_system_i => utmi_system_i,
      phy_data_o => utmi_data_o,
      phy_data_i => utmi_data_i,
      
      out_o => s_out.req,
      out_i => s_out.ack,
      in_o => s_in.ack,
      in_i => s_in.req
      );

  dumper: nsl_bnoc.testing.framed_dumper
    generic map(
      name_c => "loopback"
      )
    port map(
      reset_n_i => reset_n_sys,
      clock_i => utmi_system_i.clock,
      val_i => s_in.req,
      ack_i => s_in.ack
      );
  
  loopback: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 16,
      clk_count => 1
      )
    port map(
      p_resetn => reset_n_sys,
      p_clk(0) => utmi_system_i.clock,

      p_out_val => s_in.req,
      p_out_ack => s_in.ack,
      p_in_val => s_out.req,
      p_in_ack => s_out.ack
      );
  
end architecture;
