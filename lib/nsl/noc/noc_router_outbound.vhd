library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.noc.all;

entity noc_router_outbound is
  generic(
    in_port_count : natural
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in fifo_framed_cmd_array(in_port_count-1 downto 0);
    p_in_ack   : out fifo_framed_rsp;

    p_out_val  : out fifo_framed_cmd;
    p_out_ack  : in fifo_framed_rsp;

    p_select : in std_ulogic_vector(in_port_count-1 downto 0)
    );
end entity;

architecture rtl of noc_router_outbound is

  type state_t is (
    STATE_SELECT,
    STATE_PASSTHROUGH
    );

  signal r_state, s_state : state_t;
  signal r_selected, s_selected : natural range 0 to in_port_count-1;
  
begin

  clk: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r_state <= STATE_SELECT;
      r_selected <= 0;
    elsif rising_edge(p_clk) then
      r_state <= s_state;
      r_selected <= s_selected;
    end if;
  end process;

  transition: process(p_in_val, p_out_ack, p_select, r_state, r_selected)
  begin
    s_state <= r_state;
    s_selected <= r_selected;

    case r_state is
      when STATE_SELECT =>
        ports1: for i in r_selected downto 0 loop
          if p_select(i) = '1' then
            s_selected <= i;
            s_state <= STATE_PASSTHROUGH;
          end if;
        end loop;
        ports2: for i in in_port_count-1 downto r_selected+1 loop
          if p_select(i) = '1' then
            s_selected <= i;
            s_state <= STATE_PASSTHROUGH;
          end if;
        end loop;

      when STATE_PASSTHROUGH =>
        if p_out_ack.ack = '1'
          and p_in_val(r_selected).val = '1'
          and p_in_val(r_selected).more = '0' then
          s_state <= STATE_SELECT;
        end if;

    end case;
  end process;
  
  outputs: process(r_state, p_in_val, p_out_ack)
  begin
    case r_state is
      when STATE_SELECT =>
        p_in_ack.ack <= '0';
        p_out_val.val <= '0';
        p_out_val.more <= 'X';
        p_out_val.data <= (others => 'X');

      when STATE_PASSTHROUGH =>
        p_in_ack <= p_out_ack;
        p_out_val <= p_in_val(r_selected);
    end case;
  end process;

end architecture;
