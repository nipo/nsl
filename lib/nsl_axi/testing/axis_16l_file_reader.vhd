library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_simulation;

entity axis_16l_file_reader is
  generic(
    filename: string
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i      : in  std_ulogic;

    m_o   : out nsl_axi.stream.axis_16l_ms;
    m_i   : in nsl_axi.stream.axis_16l_sm;

    done_o : out std_ulogic
    );
end entity;

architecture rtl of axis_16l_file_reader is
begin

  gen: nsl_simulation.fifo.fifo_file_reader
    generic map(
      width => 17,
      filename => filename
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      valid_o => m_o.tvalid,
      ready_i => m_i.tready,
      data_o(16) => m_o.tlast,
      data_o(15 downto 0) => m_o.tdata,
      done_o => done_o
      );

end architecture;
