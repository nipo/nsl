library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.noc.all;

entity noc_router_inbound is
  generic(
    out_port_count : natural;
    routing_table : noc_routing_table
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in fifo_framed_cmd;
    p_in_ack   : out fifo_framed_rsp;

    p_out_val  : out fifo_framed_cmd;
    p_out_ack  : in fifo_framed_rsp_array(out_port_count-1 downto 0);
    
    p_select : out std_ulogic_vector(out_port_count-1 downto 0)
    );
end entity;

architecture rtl of noc_router_inbound is

  type state_t is (
    STATE_IDLE,
    STATE_FLUSH_HEADER,
    STATE_PASSTHROUGH
    );

  signal r_state, s_state : state_t;
  signal r_selected, s_selected : natural range 0 to out_port_count-1;
  signal r_header, s_header : std_ulogic_vector(7 downto 0);
  
begin

  clk: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r_state <= STATE_IDLE;
      r_selected <= 0;
      r_header <= (others => 'X');
    elsif rising_edge(p_clk) then
      r_state <= s_state;
      r_selected <= s_selected;
      r_header <= s_header;
    end if;
  end process;

  transition: process(p_in_val, p_out_ack, r_state, r_header, r_selected)
  begin
    s_state <= r_state;
    s_header <= r_header;
    s_selected <= r_selected;

    case r_state is
      when STATE_IDLE =>
        if p_in_val.val = '1' then
          s_state <= STATE_FLUSH_HEADER;
          s_header <= p_in_val.data;
          s_selected <= routing_table(to_integer(unsigned(p_in_val.data(3 downto 0))));
        end if;

      when STATE_FLUSH_HEADER =>
        if p_out_ack((r_selected)).ack = '1' then
          s_state <= STATE_PASSTHROUGH;
        end if;

      when STATE_PASSTHROUGH =>
        if p_out_ack((r_selected)).ack = '1'
          and p_in_val.val = '1'
          and p_in_val.more = '0' then
          s_state <= STATE_IDLE;
        end if;

    end case;
  end process;
  
  outputs: process(r_state, r_header, r_selected, p_in_val, p_out_ack)
  begin
    case r_state is
      when STATE_IDLE =>
        p_in_ack.ack <= '1';
        p_out_val.val <= '0';
        p_out_val.more <= 'X';
        p_out_val.data <= (others => 'X');
        p_select <= (others => '0');

      when STATE_FLUSH_HEADER =>
        p_in_ack.ack <= '0';
        p_out_val.val <= '1';
        p_out_val.more <= '1';
        p_out_val.data <= r_header;
        for i in 0 to out_port_count-1 loop
          if i = r_selected then
            p_select(i) <= '1';
          else
            p_select(i) <= '0';
          end if;
        end loop;

      when STATE_PASSTHROUGH =>
        p_in_ack <= p_out_ack(r_selected);
        p_out_val <= p_in_val;
        for i in 0 to out_port_count-1 loop
          if i = r_selected then
            p_select(i) <= '1';
          else
            p_select(i) <= '0';
          end if;
        end loop;
    end case;
  end process;

end architecture;
