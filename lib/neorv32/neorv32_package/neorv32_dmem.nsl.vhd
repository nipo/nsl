library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32, nsl_memory;
use neorv32.neorv32_package.all;

architecture neorv32_dmem_nsl of neorv32_dmem is

begin

  ram: neorv32.nsl_adaptation.nsl_neorv32_ram
    generic map(
      byte_count_c => dmem_size
      )
    port map(
      clk_i => clk_i,
      rstn_i => rstn_i,
      bus_req_i => bus_req_i,
      bus_rsp_o => bus_rsp_o
      );

end neorv32_dmem_nsl;
