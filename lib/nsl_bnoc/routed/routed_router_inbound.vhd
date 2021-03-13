library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity routed_router_inbound is
  generic(
    out_port_count : natural;
    routing_table : nsl_bnoc.routed.routed_routing_table
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in nsl_bnoc.routed.routed_req;
    p_in_ack   : out nsl_bnoc.routed.routed_ack;

    p_out_val  : out nsl_bnoc.routed.routed_req;
    p_out_ack  : in nsl_bnoc.routed.routed_ack_array(out_port_count-1 downto 0);

    p_request  : out std_ulogic_vector(out_port_count-1 downto 0);
    p_selected : in  std_ulogic_vector(out_port_count-1 downto 0)
    );
end entity;

architecture rtl of routed_router_inbound is

  type state_t is (
    STATE_RESET,
    STATE_IDLE,
    STATE_FLUSH_HEADER,
    STATE_PASSTHROUGH
    );

  type regs_t is record
    state : state_t;
    selected : natural range 0 to out_port_count-1;
    header : std_ulogic_vector(7 downto 0);
  end record;

  signal r, rin: regs_t;

begin

  clk: process(p_clk, p_resetn)
  begin
    if rising_edge(p_clk) then
      r <= rin;
    end if;
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    end if;
  end process;

  transition: process(p_in_val, p_out_ack, r, p_selected)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_IDLE;
        rin.selected <= 0;

      when STATE_IDLE =>
        if p_in_val.valid = '1' and p_in_val.last /= '1' then
          rin.state <= STATE_FLUSH_HEADER;
          rin.header <= p_in_val.data;
          rin.selected <= routing_table(to_integer(unsigned(p_in_val.data(3 downto 0))));
        end if;

      when STATE_FLUSH_HEADER =>
        if p_out_ack(r.selected).ready = '1' and p_selected(r.selected) = '1' then
          rin.state <= STATE_PASSTHROUGH;
        end if;

      when STATE_PASSTHROUGH =>
        if p_out_ack(r.selected).ready = '1'
          and p_in_val.valid = '1'
          and p_in_val.last = '1'
          and p_selected(r.selected) = '1' then
          rin.state <= STATE_IDLE;
        end if;

    end case;
  end process;

  outputs: process(r, p_in_val, p_out_ack, p_selected)
  begin
    p_in_ack.ready <= '0';
    p_out_val.valid <= '0';
    p_out_val.last <= '-';
    p_out_val.data <= (others => '-');
    p_request <= (others => '0');

    case r.state is
      when STATE_RESET =>
        null;

      when STATE_IDLE =>
        p_in_ack.ready <= '1';

      when STATE_FLUSH_HEADER =>
        p_out_val.valid <= '1';
        p_out_val.last <= '0';
        p_out_val.data <= r.header;
        p_request(r.selected) <= '1';

      when STATE_PASSTHROUGH =>
        p_in_ack.ready <= p_out_ack(r.selected).ready and p_selected(r.selected);
        p_out_val.valid <= p_in_val.valid and p_selected(r.selected);
        p_out_val.last <= p_in_val.last;
        p_out_val.data <= p_in_val.data;
        p_request(r.selected) <= '1';
    end case;
  end process;

end architecture;
