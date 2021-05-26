library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

entity routed_entry is
  generic(
    source_id_c : nsl_bnoc.routed.component_id
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    target_id_i : in nsl_bnoc.routed.component_id;

    framed_i   : in nsl_bnoc.framed.framed_req;
    framed_o   : out nsl_bnoc.framed.framed_ack;
    routed_o  : out nsl_bnoc.routed.routed_req;
    routed_i  : in nsl_bnoc.routed.routed_ack
    );
end entity;

architecture rtl of routed_entry is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_HEADER,
    ST_FORWARD
    );
  
  type regs_t is record
    state: state_t;
    target: nsl_bnoc.routed.component_id;
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

  transition: process(r, framed_i, routed_i, target_id_i)
  begin
    rin <= r;

    rin.target <= target_id_i;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if framed_i.valid = '1' then
          rin.state <= ST_HEADER;
        end if;

      when ST_HEADER =>
        if routed_i.ready = '1' then
          rin.state <= ST_FORWARD;
        end if;
        
      when ST_FORWARD =>
        if framed_i.valid = '1' and framed_i.last = '1' and routed_i.ready = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  mux: process(r, framed_i, routed_i)
  begin
    framed_o.ready <= '0';
    routed_o.valid <= '0';
    routed_o.data <= (others => '-');
    routed_o.last <= '-';

    case r.state is
      when ST_RESET | ST_IDLE =>
        null;
        
      when ST_HEADER =>
        routed_o.valid <= '1';
        routed_o.data <= nsl_bnoc.routed.routed_header(dst => r.target,
                                                       src => source_id_c);
        routed_o.last <= '0';
        
      when ST_FORWARD =>
        framed_o <= routed_i;
        routed_o <= framed_i;
    end case;
  end process;
    
end architecture;
