library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;

entity noc_to_framed is
  port(
    p_resetn    : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_out_val  : out fifo_framed_cmd;
    p_out_ack  : in  fifo_framed_rsp;

    p_in_val : in  flit_cmd;
    p_in_ack : out flit_ack
    );
end entity;

architecture rtl of noc_to_framed is

  type state_t is (
    STATE_RESET,
    STATE_HEADER,
    STATE_DATA
    );
  
  type regs_t is record
    state: state_t;
  end record;
  
  signal r, rin : regs_t;

  signal s_out_val : fifo_framed_cmd;
  signal s_out_ack : fifo_framed_rsp;

begin

  from_flit: nsl.flit.flit_to_framed
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_in_ack => p_in_ack,
      p_in_val => p_in_val,
      p_out_ack => s_out_ack,
      p_out_val => s_out_val
      );
  
  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_out_ack, s_out_val)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_HEADER;

      when STATE_HEADER =>
        if s_out_val.val = '1' then
          rin.state <= STATE_DATA;
        end if;

      when STATE_DATA =>
        if s_out_val.val = '1' and p_out_ack.ack = '1' and s_out_val.more = '0' then
          rin.state <= STATE_HEADER;
        end if;
    end case;
  end process;

  mealy: process(r, p_resetn, p_out_ack, s_out_val)
  begin
    case r.state is
      when STATE_RESET =>
        p_out_val.val <= '0';
        s_out_ack.ack <= '0';

      when STATE_HEADER =>
        p_out_val.val <= '0';
        s_out_ack.ack <= '1';

      when STATE_DATA =>
        p_out_val <= s_out_val;
        s_out_ack <= p_out_ack;
    end case;
  end process;

end architecture;
