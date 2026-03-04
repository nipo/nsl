library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_spi, nsl_amba, nsl_simulation, nsl_data, nsl_event, nsl_io, nsl_memory;

architecture arch of tb is

  constant cfg_c: nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(1, last => true);
  constant addr_byte_cnt: integer := 2;
  constant data_byte_cnt: integer := 2;

  signal s_cmd           : nsl_amba.axi4_stream.bus_t;
  signal s_rsp           : nsl_amba.axi4_stream.bus_t;
  
  signal spi_master_s: nsl_spi.spi.spi_master_io;
  signal spi_slave_s: nsl_spi.spi.spi_slave_io;
  
  signal spi_m: nsl_spi.spi.spi_slave_i;
  signal spi_s: nsl_spi.spi.spi_slave_o;
  signal cs_s_n : nsl_io.io.opendrain;
  signal mosi_s : nsl_io.io.tristated;
  signal miso_s : std_ulogic;
  
  signal s_clk : std_ulogic := '0';
  signal s_resetn : std_ulogic;
  signal s_done : std_ulogic_vector(0 to 0);
  signal s_write : std_ulogic;
  signal s_rdata, s_wdata : std_ulogic_vector(8*data_byte_cnt-1 downto 0);
  signal s_wdata_bytestream : nsl_data.bytestream.byte_string(0 to data_byte_cnt-1);
  signal s_address : unsigned(8*addr_byte_cnt-1 downto 0);

  signal   tick_s      : std_ulogic;
  constant tick_divisor: unsigned(7 downto 0) := (others => '1');
begin

  dut: nsl_spi.cbor_transactor.controller
    generic map(
      clock_i_hz_c   => 10e7,
      tick_i_hz_c    => 10e7/to_integer(tick_divisor),
      axi_s_cfg_c    => cfg_c,
      slave_count_c  => 1,
      width_c        => 7
      )
    port map(
      clock_i        => s_clk,
      reset_n_i      => s_resetn,

      tick_i         => tick_s,
      
      sck_o          => spi_slave_s.i.sck,
      cs_n_o(0)      => cs_s_n,
      mosi_o         => mosi_s,
      miso_i         => miso_s,
      
      cmd_i          => s_cmd.m,
      cmd_o          => s_cmd.s,
      rsp_o          => s_rsp.m,
      rsp_i          => s_rsp.s
      );

  spi_slave_s.i.cs_n <= cs_s_n.drain_n;
  spi_slave_s.i.mosi <= nsl_io.io.to_logic(mosi_s);
  miso_s <= nsl_io.io.to_logic(spi_slave_s.o.miso);
  
  slave: nsl_spi.slave.spi_memory_controller
    generic map(
      addr_bytes_c   => addr_byte_cnt,
      data_bytes_c   => data_byte_cnt,
      write_opcode_c => x"0b"
      )
    port map(
      clock_i    => s_clk,
      reset_n_i  => s_resetn,

      spi_i      => spi_slave_s.i,
      spi_o      => spi_slave_s.o,
          
      selected_o => open,

      addr_o     => s_address,

      cpol_i     => '0',
      cpha_i     => '0',

      rdata_i    => nsl_data.bytestream.from_suv(s_rdata),
      rready_o   => open,

      wdata_o    => s_wdata_bytestream,
      wvalid_o   => s_write
      );

  s_wdata <= s_wdata_bytestream(1) & s_wdata_bytestream(0);
  
  ram : nsl_memory.ram.ram_1p
    generic map (
      addr_size_c => 8*addr_byte_cnt,
      data_size_c => 8*data_byte_cnt
    )
    port map (
      clock_i      => s_clk,
      write_en_i   => s_write,
      address_i    => s_address,
      write_data_i => s_wdata,
      read_data_o  => s_rdata
      );

  
  net: nsl_amba.stream_to_udp.axi4_stream_udp_gateway
    generic map(
      config_c    => cfg_c,
      bind_port_c => 4242
      )
    port map(
      clock_i     => s_clk,
      reset_n_i   => s_resetn,

      tx_i => s_rsp.m,
      tx_o => s_rsp.s,

      rx_o => s_cmd.m,
      rx_i => s_cmd.s
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => s_resetn,
      clock_o(0) => s_clk,
      done_i => s_done
      );

  rx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      prefix_c => "UDP RX",
      config_c => cfg_c
      )
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      bus_i => s_cmd
      );

  tx_dumper: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      prefix_c => "UDP TX",
      config_c => cfg_c
      )
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      bus_i => s_rsp
      );

  tick_gen: nsl_event.tick.tick_generator_integer
    port map(
      clock_i => s_clk,
      reset_n_i => s_resetn,
      period_m1_i => tick_divisor,
      tick_o => tick_s
      );

end architecture;
