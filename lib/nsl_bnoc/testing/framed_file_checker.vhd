library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_simulation;

entity framed_file_checker is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in nsl_bnoc.framed.framed_req;
    p_in_ack   : out nsl_bnoc.framed.framed_ack;

    p_done     : out std_ulogic
    );
end entity;

architecture rtl of framed_file_checker is

  signal s_fifo : std_ulogic_vector(8 downto 0);
  
begin

  check: nsl_simulation.fifo.fifo_file_checker
    generic map(
      width => 9,
      filename => filename
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,
      ready_o => p_in_ack.ready,
      valid_i => p_in_val.valid,
      data_i => s_fifo,
      done_o => p_done
      );
  s_fifo <= p_in_val.last & p_in_val.data;

end architecture;
