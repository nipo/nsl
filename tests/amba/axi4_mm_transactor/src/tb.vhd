library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_mm.all;

entity tb is
  generic(
    beat_count_c : integer := 22
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end tb;

architecture arch of tb is

  signal bus_s, bus2_s: bus_t;

  constant config_c : config_t := config(address_width => 32,
                                         data_bus_width => 32,
                                         max_length => 16,
                                         burst => true);
  constant ctx_length_c : natural := beat_count_c * (2 ** config_c.data_bus_width_l2);

begin
  
  transactor: work.tester.axi_transactor
    generic map(
      config_c => config_c,
      ctx_length_c => ctx_length_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      done_o => done_o,
      
      axi_o => bus_s.m,
      axi_i => bus_s.s
      );
  
  dumper: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "RAMx"&to_string(beat_count_c)
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      master_i => bus_s.m,
      slave_i => bus_s.s
      );

  fifo: nsl_amba.mm_fifo.axi4_mm_fifo
    generic map(
      config_c => config_c,
      clock_count_c => 1,
      aw_depth_c => 8,
      w_depth_c => 32,
      b_depth_c => 8,
      ar_depth_c => 8,
      r_depth_c => 32
      )
    port map(
      clock_i(0) => clock_i,
      reset_n_i => reset_n_i,

      slave_i => bus_s.m,
      slave_o => bus_s.s,

      master_o => bus2_s.m,
      master_i => bus2_s.s
      );
  
  dut: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => 10
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => bus2_s.m,
      axi_o => bus2_s.s
      );

end;
