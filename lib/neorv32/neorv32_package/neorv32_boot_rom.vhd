library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32, nsl_memory, nsl_data, nsl_synthesis;
use neorv32.neorv32_package.all;

entity neorv32_boot_rom is
  port (
    clk_i     : in  std_ulogic;
    rstn_i    : in  std_ulogic;
    bus_req_i : in  bus_req_t;
    bus_rsp_o : out bus_rsp_t
  );
end neorv32_boot_rom;

architecture rtl of neorv32_boot_rom is

begin

  rom: neorv32.nsl_adaptation.nsl_neorv32_rom
    generic map(
      init_file_name_c => "neorv32_boot_rom.bin"
      )
    port map(
      clk_i => clk_i,
      rstn_i => rstn_i,
      bus_req_i => bus_req_i,
      bus_rsp_o => bus_rsp_o
      );

end architecture;
