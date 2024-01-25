library ieee;
use ieee.std_logic_1164.all;

library nsl_simulation, nsl_data, nsl_wishbone, nsl_math;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_wishbone.testing.all;
use nsl_wishbone.wishbone.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  signal wb_s, wb_dmem_s, wb_imem_s : nsl_wishbone.wishbone.wb_bus_t;
  shared variable wb_queue : wb_test_queue_root;

  constant wb_config_c : wb_config_t := (
    version => WB_B4,
    bus_type => WB_CLASSIC_PIPELINED,
    adr_width => 32,
    port_size_l2 => 5,
    port_granularity_l2 => 3,
    max_op_size_l2 => 5,
    endian => WB_ENDIAN_LITTLE,
    error_supported => true,
    retry_supported => false,
    tga_width => 0,
    req_tgd_width => 0,
    ack_tgd_width => 0,
    tgc_width => 0,
    timeout => 1024,
    burst_supported => false,
    wrap_supported => false
    );

begin

  bus_master: process is
  begin
    wb_test_queue_init(wb_queue);
    wb_test_queue_worker(wb_config_c,
                         wb_s.req, wb_s.ack, clock_s,
                         wb_queue, "WBM");
  end process;    

  imem_test: process is
    variable term: wb_term_t;
    variable data: std_ulogic_vector(31 downto 0);
  begin
    done_s(0) <= '0';
    wait for 5 ns;
    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    
    wb_test_write(wb_queue, wb_config_c, x"00000000", x"83828180", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"80008004", x"87868584", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"00000008", x"8b8a8988", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"8000800c", x"8f8e8d8c", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"00000010", x"93929190", x"f", term);

    wb_test_read_check(wb_queue, wb_config_c, x"00000000", x"83828180");
    wb_test_read_check(wb_queue, wb_config_c, x"00000004", x"87868584");

    wb_test_write(wb_queue, wb_config_c, x"00000000", x"ffffff00", x"5", term);
    wb_test_read_check(wb_queue, wb_config_c, x"00000000", x"83ff8100");

    wb_test_read_check(wb_queue, wb_config_c, x"00000008", x"8b8a8988");
    wb_test_read_check(wb_queue, wb_config_c, x"0000000c", x"8f8e8d8c");
    wb_test_read_check(wb_queue, wb_config_c, x"00000010", x"93929190");
      
    wait for 30 ns;

    done_s(0) <= '1';
    wait;
  end process;

  dmem_test: process is
    variable term: wb_term_t;
    variable data: std_ulogic_vector(31 downto 0);
  begin
    done_s(1) <= '0';
    wait for 5 ns;
    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);

    wb_test_write(wb_queue, wb_config_c, x"80000000", x"03020100", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"00008004", x"07060504", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"80000008", x"0b0a0908", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"0000800c", x"0f0e0d0c", x"f", term);
    wb_test_write(wb_queue, wb_config_c, x"80000010", x"13121110", x"f", term);

    wb_test_read_check(wb_queue, wb_config_c, x"80000000", x"03020100");
    wb_test_read_check(wb_queue, wb_config_c, x"80000004", x"07060504");
    wb_test_read_check(wb_queue, wb_config_c, x"80000008", x"0b0a0908");
    wb_test_read_check(wb_queue, wb_config_c, x"8000000c", x"0f0e0d0c");
    wb_test_read_check(wb_queue, wb_config_c, x"80000010", x"13121110");
    
    wait for 30 ns;

    done_s(1) <= '1';
    wait;
  end process;

  
  arb: nsl_wishbone.crossbar.wishbone_crossbar
    generic map(
      wb_config_c => wb_config_c,
      slave_count_c => 2,
      routing_mask_c => x"80008000",
      routing_table_c => nsl_math.int_ext.integer_vector'(0, 1, 1, 0)
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => wb_s.req,
      master_o => wb_s.ack,

      slave_o(0) => wb_imem_s.req,
      slave_o(1) => wb_dmem_s.req,
      slave_i(0) => wb_imem_s.ack,
      slave_i(1) => wb_dmem_s.ack
      );

  imem: nsl_wishbone.memory.wishbone_ram
    generic map(
      wb_config_c => wb_config_c,
      byte_size_l2_c => 3+10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      wb_i => wb_imem_s.req,
      wb_o => wb_imem_s.ack
      );      

  dmem: nsl_wishbone.memory.wishbone_ram
    generic map(
      wb_config_c => wb_config_c,
      byte_size_l2_c => 3+10
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      wb_i => wb_dmem_s.req,
      wb_o => wb_dmem_s.ack
      );      

  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 17 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
