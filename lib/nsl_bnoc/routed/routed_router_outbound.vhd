library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity routed_router_outbound is
  generic(
    in_port_count : natural
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_in_val   : in nsl_bnoc.routed.routed_req_array(0 to in_port_count-1);
    p_in_ack   : out nsl_bnoc.routed.routed_ack;

    p_out_val  : out nsl_bnoc.routed.routed_req;
    p_out_ack  : in  nsl_bnoc.routed.routed_ack;

    p_request  : in  std_ulogic_vector(0 to in_port_count-1);
    p_selected : out std_ulogic_vector(0 to in_port_count-1)
    );
end entity;

architecture rtl of routed_router_outbound is

  type state_t is (
    STATE_RESET,
    STATE_SELECT,
    STATE_PASSTHROUGH
    );

  type regs_t is record
    state: state_t;
    selected: natural range 0 to in_port_count-1;
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

  transition: process(p_in_val, p_out_ack, p_request, r)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_SELECT;

      when STATE_SELECT =>
        ports1: for i in in_port_count-1 downto 0 loop
          if p_request(i) = '1' then
            rin.selected <= i;
            rin.state <= STATE_PASSTHROUGH;
          end if;
        end loop;

      when STATE_PASSTHROUGH =>
        if p_out_ack.ready = '1'
          and p_in_val(r.selected).valid = '1'
          and p_in_val(r.selected).last = '1' then
          rin.state <= STATE_SELECT;
        end if;

    end case;
  end process;

  outputs: process(r, p_in_val, p_out_ack)
  begin
    p_out_val.last <= '-';
    p_out_val.data <= (others => '-');
    p_in_ack.ready <= '0';
    p_out_val.valid <= '0';
    p_selected <= (others => '0');

    case r.state is
      when STATE_RESET | STATE_SELECT =>
        null;

      when STATE_PASSTHROUGH =>
        p_in_ack <= p_out_ack;
        p_out_val <= p_in_val(r.selected);
        p_selected(r.selected) <= '1';
    end case;
  end process;

end architecture;
