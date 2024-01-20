library ieee;
use ieee.std_logic_1164.all;

library nsl_memory, nsl_bnoc;

entity routed_fifo_slice is
  port(
    reset_n_i  : in  std_ulogic;
    clock_i    : in  std_ulogic;

    in_i   : in nsl_bnoc.routed.routed_req_t;
    in_o   : out nsl_bnoc.routed.routed_ack_t;

    out_o   : out nsl_bnoc.routed.routed_req_t;
    out_i   : in nsl_bnoc.routed.routed_ack_t
    );
end entity;

architecture rtl of routed_fifo_slice is
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
