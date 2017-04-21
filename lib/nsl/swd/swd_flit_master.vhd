library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;
use nsl.swd.all;

entity swd_flit_master is
  port (
    p_clk      : in  std_logic;
    p_resetn   : in  std_logic;

    p_in_val    : in flit_cmd;
    p_in_ack    : out flit_ack;
    p_out_val   : out flit_cmd;
    p_out_ack   : in flit_ack;
    
    p_swclk    : out std_logic;
    p_swdio_i  : in  std_logic;
    p_swdio_o  : out std_logic;
    p_swdio_oe : out std_logic
  );
end entity; 

architecture rtl of swd_flit_master is

  signal s_in_val, s_out_val: fifo_framed_cmd;
  signal s_in_ack, s_out_ack: fifo_framed_rsp;

begin

  master: nsl.swd.swd_master
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_in_val => s_in_val,
      p_in_ack => s_in_ack,
      p_out_val => s_out_val,
      p_out_ack => s_out_ack,
      p_swclk => p_swclk,
      p_swdio_i => p_swdio_i,
      p_swdio_o => p_swdio_o,
      p_swdio_oe => p_swdio_oe
      );

  to_framed: nsl.flit.flit_to_framed
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_in_val => p_in_val,
      p_in_ack => p_in_ack,
      p_out_val => s_in_val,
      p_out_ack => s_in_ack
      );

  from_framed: nsl.flit.flit_from_framed
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,
      p_in_val => s_out_val,
      p_in_ack => s_out_ack,
      p_out_val => p_out_val,
      p_out_ack => p_out_ack
      );

end architecture;
