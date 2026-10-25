library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation;

-- Microcoded DMA regressions on four configurations: one channel on
-- a 32-bit bus, two channels on a 32-bit bus, two channels on a
-- 64-bit bus with endian swap, four channels on a 32-bit bus.  The
-- manager boots from 0xff00 in the two and four-channel 32-bit ones,
-- is stopped at reset in the others.  The 64-bit configuration takes
-- two requests a peripheral, the four-channel one three, the others
-- one.  The four-channel one faults stores of a failed load's bytes.  Each
-- follows the script its reference model generated for it
-- (dma_vectors_* packages).
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 3);

begin

  one_32: entity work.dma_harness
    generic map(
      channel_count_c => 1,
      bus_width_c => 32,
      endian_swap_c => false,
      boot_from_pc_c => false,
      boot_addr_c => x"00000000",
      request_depth_c => 1,
      failed_store_fault_c => false,
      name_c => "1ch/32b",
      script_c => work.dma_vectors_1ch_32b.script_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(0)
      );

  two_32: entity work.dma_harness
    generic map(
      channel_count_c => 2,
      bus_width_c => 32,
      endian_swap_c => false,
      boot_from_pc_c => true,
      boot_addr_c => x"0000ff00",
      request_depth_c => 1,
      failed_store_fault_c => false,
      name_c => "2ch/32b",
      script_c => work.dma_vectors_2ch_32b.script_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(1)
      );

  two_64: entity work.dma_harness
    generic map(
      channel_count_c => 2,
      bus_width_c => 64,
      endian_swap_c => true,
      boot_from_pc_c => false,
      boot_addr_c => x"00000000",
      request_depth_c => 2,
      failed_store_fault_c => false,
      name_c => "2ch/64b",
      script_c => work.dma_vectors_2ch_64b.script_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(2)
      );

  four_32: entity work.dma_harness
    generic map(
      channel_count_c => 4,
      bus_width_c => 32,
      endian_swap_c => false,
      boot_from_pc_c => true,
      boot_addr_c => x"0000ff00",
      request_depth_c => 3,
      failed_store_fault_c => true,
      name_c => "4ch/32b",
      script_c => work.dma_vectors_4ch_32b.script_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      done_o => done_s(3)
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 32 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end architecture;
