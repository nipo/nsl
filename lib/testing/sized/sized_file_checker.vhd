library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library testing;
use testing.fifo.all;
use testing.sized.all;

library nsl;
use nsl.sized.all;

entity sized_file_checker is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in sized_req;
    p_in_ack   : out sized_ack;

    p_done     : out std_ulogic
    );
end entity;

architecture rtl of sized_file_checker is
begin

  check: testing.fifo.fifo_file_checker
    generic map(
      width => 8,
      filename => filename
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_ready => p_in_ack.ack,
      p_valid => p_in_val.val,
      p_data => p_in_val.data,
      p_done => p_done
      );

end architecture;
