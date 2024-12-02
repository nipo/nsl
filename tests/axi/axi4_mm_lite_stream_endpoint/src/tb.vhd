library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_axi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_axi.axi4_mm.all;
use nsl_axi.axi4_stream.all;
use nsl_axi.stream_endpoint.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal bus_s: nsl_axi.axi4_mm.bus_t;
  signal stream_s: nsl_axi.axi4_stream.bus_t;
  signal irq_n_s: std_ulogic;

  constant mm_config_c : nsl_axi.axi4_mm.config_t := nsl_axi.axi4_mm.config(address_width => 32,
                                                                            data_bus_width => 32);

  constant stream_config_c : nsl_axi.axi4_stream.config_t := nsl_axi.axi4_stream.config(bytes => 2,
                                                                                        last => true);

begin

  mm: process is
    variable value: unsigned(31 downto 0);
    variable rsp: resp_enum_t;
  begin
    done_s(0) <= '0';

    bus_s.m.aw <= address_defaults(mm_config_c);
    bus_s.m.w <= write_data_defaults(mm_config_c);
    bus_s.m.r <= handshake_defaults(mm_config_c);
    bus_s.m.b <= handshake_defaults(mm_config_c);
    bus_s.m.ar <= address_defaults(mm_config_c);

    wait for 30 ns;
    wait until falling_edge(clock_s);

    lite_write(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IRQ_MASK, reg_lsb => 2, val => x"00000001");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IRQ_STATE, reg_lsb => 2, val => x"00000002");
    lite_write(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_OUT_DATA, reg_lsb => 2, val => x"80001234");
    wait for 80 ns;
    wait until falling_edge(clock_s);
    lite_write(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_OUT_DATA, reg_lsb => 2, val => x"80004567");
    lite_write(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_OUT_DATA, reg_lsb => 2, val => x"c000789a");
    wait for 80 ns;
    wait until falling_edge(clock_s);
    assert_equal("irq", irq_n_s, '0', failure);
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IRQ_STATE, reg_lsb => 2, val => x"00000003");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IN_STATUS, reg_lsb => 2, val => x"80000003");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IN_DATA, reg_lsb => 2, val => x"80001234");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IN_STATUS, reg_lsb => 2, val => x"80000002");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IN_DATA, reg_lsb => 2, val => x"80004567");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IN_STATUS, reg_lsb => 2, val => x"c0000001");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IN_DATA, reg_lsb => 2, val => x"c000789a");
    lite_check(mm_config_c, clock_s, bus_s.s, bus_s.m, reg => AXI4_STREAM_ENDPOINT_LITE_IN_STATUS, reg_lsb => 2, val => "0-00"&x"0000000");
    assert_equal("irq", irq_n_s, '1', failure);
    wait for 80 ns;
    
    done_s(0) <= '1';
    wait;
  end process;

  dumper: nsl_axi.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => mm_config_c,
      prefix_c => "EP"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => bus_s.m,
      slave_i => bus_s.s
      );

  ep: nsl_axi.stream_endpoint.axi4_stream_endpoint_lite
    generic map(
      mm_config_c => mm_config_c,
      stream_config_c => stream_config_c,
      in_buffer_depth_c => 128,
      out_buffer_depth_c => 128
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      irq_n_o => irq_n_s,
      
      mm_i => bus_s.m,
      mm_o => bus_s.s,

      rx_i => stream_s.m,
      rx_o => stream_s.s,

      tx_o => stream_s.m,
      tx_i => stream_s.s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 25 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
