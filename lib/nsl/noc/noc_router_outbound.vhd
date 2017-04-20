library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.flit.all;
use nsl.noc.all;

entity noc_router_outbound is
  generic(
    in_port_count : natural
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in flit_cmd_array(in_port_count-1 downto 0);
    p_in_ack   : out flit_ack;

    p_out_val  : out flit_cmd;
    p_out_ack  : in flit_ack;

    p_select : in std_ulogic_vector(in_port_count-1 downto 0)
    );
end entity;

architecture rtl of noc_router_outbound is

  type state_t is (
    STATE_SELECT,
    STATE_PASSTHROUGH
    );

  type regs_t is record
    state : state_t;
    selected : natural range 0 to in_port_count-1;
  end record;
  
  signal r, rin: regs_t;

begin

  clk: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= STATE_SELECT;
      r.selected <= 0;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(p_in_val, p_out_ack, p_select, r)
  begin
    rin <= r;

    case r.state is
      when STATE_SELECT =>
        ports: for i in 0 to in_port_count-1 loop
          if p_select(i) = '1' then
            rin.selected <= i;
            rin.state <= STATE_PASSTHROUGH;
          end if;
        end loop;

      when STATE_PASSTHROUGH =>
        if p_select(r.selected) = '0' then
          rin.state <= STATE_SELECT;
        end if;

    end case;
  end process;
  
  outputs: process(r, p_in_val, p_out_ack)
  begin
    case r.state is
      when STATE_SELECT =>
        p_in_ack.ack <= '0';
        p_out_val.val <= '0';
        p_out_val.data <= (others => 'X');

      when STATE_PASSTHROUGH =>
        p_in_ack <= p_out_ack;
        p_out_val <= p_in_val(r.selected);
    end case;
  end process;

end architecture;
