library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_dvi;

entity pmod_dvi_output is
  generic(
    driver_mode_c : string := "default"
    );
  port(
    reset_n_i : in std_ulogic;
    pixel_clock_i : in std_ulogic;
    serial_clock_i : in std_ulogic;
    
    tmds_i : in nsl_dvi.dvi.symbol_vector_t;

    pmod_o : out nsl_digilent.pmod.pmod_double_t
    );
end entity;

architecture beh of pmod_dvi_output is

begin

  driver: nsl_dvi.transceiver.dvi_driver
    generic map(
      driver_mode_c => driver_mode_c
      );
    port map(
      reset_n_i => reset_n_i,
      pixel_clock_i => pixel_clock_i,
      serial_clock_i => serial_clock_i,
      tmds_i => tmds_i,

      clock_o.p => pmod_o(4),
      clock_o.n => pmod_o(8),
      data_o(0).p => pmod_o(3),
      data_o(0).n => pmod_o(7),
      data_o(1).p => pmod_o(2),
      data_o(1).n => pmod_o(6),
      data_o(2).p => pmod_o(1),
      data_o(2).n => pmod_o(5)
      );
  
end architecture;
