library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
library signalling;
library testing;
library util;

entity tb is
end tb;

architecture arch of tb is

  signal s_clk_master : std_ulogic := '0';
  signal s_resetn_master : std_ulogic;
  signal s_clk_slave : std_ulogic := '0';
  signal s_resetn_slave : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 3);

  signal s_spi: signalling.spi.spi_bus;
  signal s_master_cmd, s_master_rsp: nsl.framed.framed_bus;
  signal s_slave_received, s_slave_transmitted: nsl.framed.framed_bus;

begin

  master_reset: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_master,
      p_clk => s_clk_master
      );

  master_cmd: testing.framed.framed_file_reader
    generic map(
      filename => "master_cmd.txt"
      )
    port map(
      p_resetn => s_resetn_master,
      p_clk => s_clk_master,
      p_out_val => s_master_cmd.req,
      p_out_ack => s_master_cmd.ack,
      p_done => s_done(0)
      );

  master_rsp: testing.framed.framed_file_checker
    generic map(
      filename => "master_rsp.txt"
      )
    port map(
      p_resetn => s_resetn_master,
      p_clk => s_clk_master,
      p_in_val => s_master_rsp.req,
      p_in_ack => s_master_rsp.ack,
      p_done => s_done(1)
      );

  master: nsl.spi.spi_master
    generic map(
      slave_count => 1
      )
    port map(
      p_clk => s_clk_master,
      p_resetn => s_resetn_master,
      p_sck => s_spi.sck,
      p_csn(0) => s_spi.cs,
      p_mosi => s_spi.mosi,
      p_miso => s_spi.miso,
      p_cmd_val => s_master_cmd.req,
      p_cmd_ack => s_master_cmd.ack,
      p_rsp_val => s_master_rsp.req,
      p_rsp_ack => s_master_rsp.ack
      );
  
  slave_reset: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_async,
      p_out => s_resetn_slave,
      p_clk => s_clk_slave
      );

  slave: nsl.spi.spi_framed_gateway
    port map(
      p_framed_clk => s_clk_slave,
      p_framed_resetn => s_resetn_slave,
      p_sck => s_spi.sck,
      p_csn => s_spi.cs,
      p_mosi => s_spi.mosi,
      p_miso => s_spi.miso,
      p_out_val => s_slave_received.req,
      p_out_ack => s_slave_received.ack,
      p_in_val => s_slave_transmitted.req,
      p_in_ack => s_slave_transmitted.ack
      );

  slave_transmitted: testing.framed.framed_file_reader
    generic map(
      filename => "slave_transmitted.txt"
      )
    port map(
      p_resetn => s_resetn_slave,
      p_clk => s_clk_slave,
      p_out_val => s_slave_transmitted.req,
      p_out_ack => s_slave_transmitted.ack,
      p_done => s_done(2)
      );

  slave_received: testing.framed.framed_file_checker
    generic map(
      filename => "slave_received.txt"
      )
    port map(
      p_resetn => s_resetn_slave,
      p_clk => s_clk_slave,
      p_in_val => s_slave_received.req,
      p_in_ack => s_slave_received.ack,
      p_done => s_done(3)
      );
  
  process
  begin
    s_resetn_async <= '0';
    wait for 10 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  master_clock: process(s_clk_master)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk_master <= not s_clk_master after 5 ns;
    end if;
  end process;

  slave_clock: process(s_clk_slave)
  begin
    if s_done /= (s_done'range => '1') then
      s_clk_slave <= not s_clk_slave after 7 ns;
    end if;
  end process;
  
end;
