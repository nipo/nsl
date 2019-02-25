library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library testing;
use testing.fifo.all;

library signalling;
use signalling.axis.all;

entity axis_16l_file_reader is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_mo   : out signalling.axis.axis_16l_ms;
    p_mi   : in signalling.axis.axis_16l_sm;

    p_done : out std_ulogic
    );
end entity;

architecture rtl of axis_16l_file_reader is
begin

  gen: testing.fifo.fifo_file_reader
    generic map(
      width => 17,
      filename => filename
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_valid => p_mo.tvalid,
      p_ready => p_mi.tready,
      p_data(16) => p_mo.tlast,
      p_data(15 downto 0) => p_mo.tdata,
      p_done => p_done
      );

end architecture;
