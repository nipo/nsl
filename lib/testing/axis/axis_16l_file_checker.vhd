library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library signalling;
use signalling.axis.all;

library testing;
use testing.fifo.all;

entity axis_16l_file_checker is
  generic(
    filename: string
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_so   : out signalling.axis.axis_16l_sm;
    p_si   : in signalling.axis.axis_16l_ms;

    p_done     : out std_ulogic
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
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_ready => p_so.tready,
      p_valid => p_si.tvalid,
      p_data(16) => p_si.tlast,
      p_data(15 downto 0) => p_si.tdata,
      p_done => p_done
      );

end architecture;
