library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.noc.all;
use nsl.util.all;

entity noc_atomic_fifo is
  generic(
    depth : natural
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in noc_cmd;
    p_in_ack   : out noc_rsp;

    p_out_val   : out noc_cmd;
    p_out_ack   : in noc_rsp
    );
end entity;

architecture rtl of noc_atomic_fifo is

  -- Just to be able to read them back
  signal s_out_val : noc_cmd;
  signal s_in_ack, s_out_ack : noc_rsp;
  signal s_has_one : std_ulogic;
  signal r_flush, s_flush : std_ulogic;
  constant nw : natural := 2 ** log2(depth);
  signal r_complete, s_complete : natural range 0 to nw - 1;

begin

  reg: process(p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r_complete <= 0;
      r_flush <= '0';
    elsif rising_edge(p_clk) then
      r_complete <= s_complete;
      r_flush <= s_flush;
    end if;
  end process;

  process(p_in_val, s_out_ack, s_out_val, s_in_ack, r_complete)
    variable inc, dec : boolean;
  begin
    inc := p_in_val.val = '1' and s_in_ack.ack = '1' and p_in_val.more = '0';
    dec := s_out_val.val = '1' and s_out_ack.ack = '1' and s_out_val.more = '0';

    s_complete <= r_complete;
    if inc and not dec then
      s_complete <= (r_complete + 1) mod nw;
    elsif not inc and dec then
      s_complete <= (r_complete - 1) mod nw;
    end if;
  end process;

  flush: process(s_in_ack.ack, s_out_val, r_flush)
  begin
    if r_flush = '0' then
      s_flush <= not s_in_ack.ack;
    else
      s_flush <= s_out_val.val and s_out_val.more;
    end if;
  end process;
  
  fifo: nsl.noc.noc_fifo
    generic map(
      depth => depth
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_in_val => p_in_val,
      p_in_ack => s_in_ack,
      p_out_val => s_out_val,
      p_out_ack => s_out_ack
      );

  s_has_one <= '1' when r_complete /= 0 else '0';
  p_in_ack <= s_in_ack;
  s_out_ack.ack <= p_out_ack.ack and (s_has_one or r_flush);
  p_out_val.val <= s_out_val.val and (s_has_one or r_flush);
  p_out_val.data <= s_out_val.data;
  p_out_val.more <= s_out_val.more;

end architecture;
