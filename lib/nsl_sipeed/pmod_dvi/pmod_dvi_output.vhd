library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_dvi;

entity pmod_dvi_output is
  port(
    reset_n_i : in std_ulogic;
    pixel_clock_i : in std_ulogic;
    serial_clock_i : in std_ulogic;
    
    tmds_i : in nsl_dvi.dvi.symbol_vector_t;

    pmod_io : inout nsl_digilent.pmod.pmod_io_t
    );
end entity;

architecture beh of pmod_dvi_output is

begin

  driver: nsl_dvi.transceiver.dvi_driver
    port map(
      reset_n_i => reset_n_i,
      pixel_clock_i => pixel_clock_i,
      serial_clock_i => serial_clock_i,
      tmds_i => tmds_i,

      clock_o.p => pmod_io(7),
      clock_o.n => pmod_io(6),
      data_o(0).p => pmod_io(5),
      data_o(0).n => pmod_io(4),
      data_o(1).p => pmod_io(3),
      data_o(1).n => pmod_io(2),
      data_o(2).p => pmod_io(1),
      data_o(2).n => pmod_io(0)
      );
  
end architecture;
