library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_bnoc;

entity framed_file_reader is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_out_val   : out nsl_bnoc.framed.framed_req;
    p_out_ack   : in nsl_bnoc.framed.framed_ack;

    p_done : out std_ulogic
    );
end entity;

architecture rtl of framed_file_reader is

  signal s_fifo : std_ulogic_vector(8 downto 0);
  
begin

  gen: nsl_simulation.fifo.fifo_file_reader
    generic map(
      width => 9,
      filename => filename
      )
    port map(
      reset_n_i => p_resetn,
      clock_i => p_clk,
      valid_o => p_out_val.valid,
      ready_i => p_out_ack.ready,
      data_o => s_fifo,
      done_o => p_done
      );
  p_out_val.last <= s_fifo(8);
  p_out_val.data <= s_fifo(7 downto 0);

end architecture;
