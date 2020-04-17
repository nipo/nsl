library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_simulation;

entity sized_file_checker is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in nsl_bnoc.sized.sized_req;
    p_in_ack   : out nsl_bnoc.sized.sized_ack;

    p_done     : out std_ulogic
    );
end entity;

architecture rtl of sized_file_checker is
begin

  check: nsl_simulation.fifo.fifo_file_checker
    generic map(
      width => 8,
      filename => filename
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,
      ready_o => p_in_ack.ready,
      valid_i => p_in_val.valid,
      data_i => p_in_val.data,
      done_o => p_done
      );

end architecture;
