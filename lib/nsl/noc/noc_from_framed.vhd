library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.flit.all;
use nsl.noc.all;

entity noc_from_framed is
  generic(
    srcid       : noc_id;
    tgtid       : noc_id;
    data_depth  : natural := 512;
    txn_depth   : natural := 4
    );
  port(
    p_resetn    : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_in_val    : in fifo_framed_cmd;
    p_in_ack    : out fifo_framed_rsp;

    p_out_val   : out flit_cmd;
    p_out_ack   : in flit_ack
    );
end entity;

architecture rtl of noc_from_framed is

  type state_t is (
    STATE_RESET,
    STATE_HEADER,
    STATE_DATA
    );
  
  type regs_t is record
    state: state_t;
  end record;
  
  signal r, rin : regs_t;

  signal s_in_val : fifo_framed_cmd;
  signal s_in_ack : fifo_framed_rsp;

begin

  to_flit: nsl.flit.flit_from_framed
    generic map(
      data_depth => data_depth,
      txn_depth => txn_depth
      )
    port map(
      p_resetn => p_resetn,
      p_clk => p_clk,
      p_in_ack => s_in_ack,
      p_in_val => s_in_val,
      p_out_ack => p_out_ack,
      p_out_val => p_out_val
      );
  
  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_in_val, p_out_ack, s_in_ack)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_HEADER;

      when STATE_HEADER =>
        if s_in_ack.ack = '1' then
          rin.state <= STATE_DATA;
        end if;

      when STATE_DATA =>
        if s_in_ack.ack = '1' and p_in_val.val = '1' and p_in_val.more = '0' then
          rin.state <= STATE_HEADER;
        end if;
    end case;
  end process;

  mealy: process(r, p_resetn, p_in_val, s_in_ack)
  begin
    case r.state is
      when STATE_RESET =>
        p_in_ack.ack <= '0';
        s_in_val.val <= '0';
        s_in_val.more <= 'X';
        s_in_val.data <= (others => 'X');

      when STATE_HEADER =>
        p_in_ack.ack <= '0';
        s_in_val.val <= '0';
        s_in_val.more <= '1';
        s_in_val.data <= noc_flit_header(tgtid, srcid);

      when STATE_DATA =>
        p_in_ack <= s_in_ack;
        s_in_val <= p_in_val;
    end case;
  end process;

end architecture;
