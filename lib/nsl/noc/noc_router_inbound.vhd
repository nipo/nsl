library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.flit.all;
use nsl.noc.all;

entity noc_router_inbound is
  generic(
    out_port_count : natural;
    routing_table : noc_routing_table
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in flit_cmd;
    p_in_ack   : out flit_ack;

    p_out_val  : out flit_cmd;
    p_out_ack  : in flit_ack_array(out_port_count-1 downto 0);
    
    p_select : out std_ulogic_vector(out_port_count-1 downto 0)
    );
end entity;

architecture rtl of noc_router_inbound is

  type state_t is (
    STATE_GET_SIZE,
    STATE_GET_HEADER,
    STATE_PUT_SIZE,
    STATE_PUT_HEADER,
    STATE_PASSTHROUGH
    );

  type regs_t is record
    state: state_t;
    selected: natural range 0 to out_port_count-1;
    size: unsigned(7 downto 0);
    header: std_ulogic_vector(7 downto 0);
  end record;

  signal r, rin: regs_t;
  
begin

  clk: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= STATE_GET_SIZE;
      r.selected <= 0;
      r.header <= (others => 'X');
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(p_in_val, p_out_ack, r)
  begin
    rin <= r;

    case r.state is
      when STATE_GET_SIZE =>
        if p_in_val.val = '1' then
          rin.state <= STATE_GET_HEADER;
          rin.size <= unsigned(p_in_val.data);
        end if;

      when STATE_GET_HEADER =>
        if p_in_val.val = '1' then
          rin.state <= STATE_PUT_SIZE;
          rin.header <= p_in_val.data;
          rin.selected <= routing_table(noc_flit_header_dst(p_in_val.data));
        end if;

      when STATE_PUT_SIZE =>
        if p_out_ack((r.selected)).ack = '1' then
          rin.state <= STATE_PUT_HEADER;
          rin.size <= r.size - x"01";
        end if;

      when STATE_PUT_HEADER =>
        if p_out_ack((r.selected)).ack = '1' then
          rin.state <= STATE_PASSTHROUGH;
          rin.size <= r.size - x"01";
        end if;

      when STATE_PASSTHROUGH =>
        if p_out_ack((r.selected)).ack = '1'
          and p_in_val.val = '1' then
          rin.size <= r.size - x"01";
          if r.size = x"00" then
            rin.state <= STATE_GET_SIZE;
          end if;
        end if;

    end case;
  end process;
  
  outputs: process(r, p_in_val, p_out_ack)
  begin
    case r.state is
      when STATE_GET_SIZE | STATE_GET_HEADER =>
        p_in_ack.ack <= '1';
        p_out_val.val <= '0';
        p_out_val.data <= (others => 'X');
        p_select <= (others => '0');

      when STATE_PUT_SIZE =>
        p_in_ack.ack <= '0';
        p_out_val.val <= '1';
        p_out_val.data <= std_ulogic_vector(r.size);
        for i in 0 to out_port_count-1 loop
          if i = r.selected then
            p_select(i) <= '1';
          else
            p_select(i) <= '0';
          end if;
        end loop;

      when STATE_PUT_HEADER =>
        p_in_ack.ack <= '0';
        p_out_val.val <= '1';
        p_out_val.data <= r.header;
        for i in 0 to out_port_count-1 loop
          if i = r.selected then
            p_select(i) <= '1';
          else
            p_select(i) <= '0';
          end if;
        end loop;

      when STATE_PASSTHROUGH =>
        p_in_ack <= p_out_ack(r.selected);
        p_out_val <= p_in_val;
        for i in 0 to out_port_count-1 loop
          if i = r.selected then
            p_select(i) <= '1';
          else
            p_select(i) <= '0';
          end if;
        end loop;
    end case;
  end process;

end architecture;
