library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_simulation;

entity sized_file_reader is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_out_val   : out nsl_bnoc.sized.sized_req;
    p_out_ack   : in nsl_bnoc.sized.sized_ack;

    p_done : out std_ulogic
    );
end entity;

architecture rtl of sized_file_reader is
begin

  gen: nsl_simulation.fifo.fifo_file_reader
    generic map(
      width => 8,
      filename => filename
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,
      valid_o => p_out_val.valid,
      ready_i => p_out_ack.ready,
      data_o => p_out_val.data,
      done_o => p_done
      );

end architecture;
