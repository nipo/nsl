library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi;
use nsl_axi.axi4_mm.all;

entity axi4_mm_ram is
  generic(
    config_c : config_t;
    byte_size_l2_c : positive
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t
    );
end entity;

architecture beh of axi4_mm_ram is

begin

  lite: if is_lite(config_c)
  generate
    impl: nsl_axi.ram.axi4_mm_lite_ram
      generic map(
        config_c => config_c,
        byte_size_l2_c => byte_size_l2_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        axi_i => axi_i,
        axi_o => axi_o
        );
  end generate;
  
  full: if not is_lite(config_c)
  generate
    impl: nsl_axi.ram.axi4_mm_full_ram
      generic map(
        config_c => config_c,
        byte_size_l2_c => byte_size_l2_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        axi_i => axi_i,
        axi_o => axi_o
        );
  end generate;
  
end architecture;
