library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;
library util;
use util.numeric.all;

entity framed_fifo_atomic is
  generic(
    depth : natural;
    clk_count  : natural range 1 to 2
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic_vector(0 to clk_count-1);

    p_in_val   : in nsl.framed.framed_req;
    p_in_ack   : out nsl.framed.framed_ack;

    p_out_val   : out nsl.framed.framed_req;
    p_out_ack   : in nsl.framed.framed_ack
    );
end entity;

architecture rtl of framed_fifo_atomic is

  -- Just to be able to read them back
  signal s_out_val : nsl.framed.framed_req;
  signal s_in_ack, s_out_ack : nsl.framed.framed_ack;
  signal s_has_one : std_ulogic;
  constant nw : natural := 2 ** util.numeric.log2(depth);

  type regs_t is record
    flush: std_ulogic;
    complete: natural range 0 to nw - 1;
  end record;

  signal r, rin: regs_t;

begin

  assert clk_count = 1
    report "This component only supports one clock for now"
    severity failure;
  
  reg: process(p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.complete <= 0;
      r.flush <= '0';
    elsif rising_edge(p_clk(0)) then
      r <= rin;
    end if;
  end process;

  process(p_in_val, s_out_ack, s_out_val, s_in_ack, r.complete)
    variable inc, dec : boolean;
  begin
    inc := p_in_val.val = '1' and s_in_ack.ack = '1' and p_in_val.more = '0';
    dec := s_out_val.val = '1' and s_out_ack.ack = '1' and s_out_val.more = '0';

    rin.complete <= r.complete;
    if inc and not dec then
      rin.complete <= (r.complete + 1) mod nw;
    elsif not inc and dec then
      rin.complete <= (r.complete - 1) mod nw;
    end if;

    if r.flush = '0' then
      rin.flush <= not s_in_ack.ack;
    else
      rin.flush <= s_out_val.val and s_out_val.more;
    end if;
  end process;
  
  fifo: nsl.framed.framed_fifo
    generic map(
      depth => depth,
      clk_count => clk_count
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_in_val => p_in_val,
      p_in_ack => s_in_ack,
      p_out_val => s_out_val,
      p_out_ack => s_out_ack
      );

  s_has_one <= '1' when r.complete /= 0 else '0';
  p_in_ack <= s_in_ack;
  s_out_ack.ack <= p_out_ack.ack and (s_has_one or r.flush);
  p_out_val.val <= s_out_val.val and (s_has_one or r.flush);
  p_out_val.data <= s_out_val.data;
  p_out_val.more <= s_out_val.more;

end architecture;
