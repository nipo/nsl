library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_simulation;

entity axis_16l_file_checker is
  generic(
    filename: string
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    s_o   : out nsl_axi.stream.axis_16l_sm;
    s_i   : in nsl_axi.stream.axis_16l_ms;

    done_o     : out std_ulogic
    );
end entity;

architecture rtl of axis_16l_file_checker is
begin

  check: testing.fifo.fifo_file_checker
    generic map(
      width => 17,
      filename => filename
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      ready_o => s_o.tready,
      valid_i => s_i.tvalid,
      data_i(16) => s_i.tlast,
      data_i(15 downto 0) => s_i.tdata,
      done_o => done_o
      );

end architecture;
