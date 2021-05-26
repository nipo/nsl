library ieee;
use ieee.std_logic_1164.all;

library nsl_memory, nsl_bnoc;

entity framed_fifo_slice is
  port(
    reset_n_i  : in  std_ulogic;
    clock_i    : in  std_ulogic;

    in_i   : in nsl_bnoc.framed.framed_req;
    in_o   : out nsl_bnoc.framed.framed_ack;

    out_o   : out nsl_bnoc.framed.framed_req;
    out_i   : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of framed_fifo_slice is
begin

  fifo: nsl_memory.fifo.fifo_register_slice
    generic map(
      data_width_c => 9
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      out_data_o(8) => out_o.last,
      out_data_o(7 downto 0) => out_o.data,
      out_ready_i => out_i.ready,
      out_valid_o => out_o.valid,
      in_data_i(8) => in_i.last,
      in_data_i(7 downto 0) => in_i.data,
      in_valid_i => in_i.valid,
      in_ready_o => in_o.ready
      );

end architecture;
