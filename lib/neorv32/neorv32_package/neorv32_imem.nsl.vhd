library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32, nsl_memory, nsl_data, nsl_synthesis, user_data;
use neorv32.neorv32_package.all;

architecture neorv32_imem_nsl of neorv32_imem is

begin

  imem_rom: if IMEM_AS_IROM
  generate
  begin
    rom: neorv32.nsl_adaptation.nsl_neorv32_rom
      generic map(
        byte_count_c => IMEM_SIZE,
        contents_c => user_data.neorv32_init.neorv32_imem_init
        )
      port map(
        clk_i => clk_i,
        rstn_i => rstn_i,
        bus_req_i => bus_req_i,
        bus_rsp_o => bus_rsp_o
        );
  end generate;

  imem_ram: if not IMEM_AS_IROM
  generate
    ram: neorv32.nsl_adaptation.nsl_neorv32_ram
      generic map(
        byte_count_c => IMEM_SIZE
        )
      port map(
        clk_i => clk_i,
        rstn_i => rstn_i,
        bus_req_i => bus_req_i,
        bus_rsp_o => bus_rsp_o
        );
  end generate;

end neorv32_imem_nsl;
