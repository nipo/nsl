library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

entity routed_exit is
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    routed_i : in nsl_bnoc.routed.routed_req;
    routed_o : out nsl_bnoc.routed.routed_ack;
    framed_o : out nsl_bnoc.framed.framed_req;
    framed_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of routed_exit is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_FORWARD
    );
  
  type regs_t is record
    state: state_t;
  end record;  

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, framed_i, routed_i)
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if routed_i.valid = '1' and routed_i.last = '0' then
          rin.state <= ST_FORWARD;
        end if;
        
      when ST_FORWARD =>
        if routed_i.valid = '1' and routed_i.last = '1' and framed_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  mux: process(r, framed_i, routed_i)
  begin
    routed_o.ready <= '0';
    framed_o.valid <= '0';
    framed_o.data <= (others => '-');
    framed_o.last <= '-';

    case r.state is
      when ST_RESET =>
        null;

      when ST_IDLE =>
        routed_o.ready <= '1';
        
      when ST_FORWARD =>
        framed_o <= routed_i;
        routed_o <= framed_i;
    end case;
  end process;
    
end architecture;
