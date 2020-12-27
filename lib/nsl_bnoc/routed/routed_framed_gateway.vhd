library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity routed_framed_gateway is
  generic(
      source_id_c : nsl_bnoc.routed.component_id
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    target_id_i  : in nsl_bnoc.routed.component_id;

    routed_in_i  : in  nsl_bnoc.routed.routed_req;
    routed_in_o  : out nsl_bnoc.routed.routed_ack;
    framed_out_o : out nsl_bnoc.framed.framed_req;
    framed_out_i : in  nsl_bnoc.framed.framed_ack;

    framed_in_i  : in  nsl_bnoc.framed.framed_req;
    framed_in_o  : out nsl_bnoc.framed.framed_ack;
    routed_out_o : out nsl_bnoc.routed.routed_req;
    routed_out_i : in  nsl_bnoc.routed.routed_ack
    );
end entity;

architecture rtl of routed_framed_gateway is
  
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_ROUTE,
    ST_TAG,
    ST_FORWARD
    );
  
  type regs_t is record
    cmd_state, rsp_state: state_t;
    last_tag: nsl_bnoc.framed.framed_data_t;
  end record;  

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.cmd_state <= ST_RESET;
      r.rsp_state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(routed_in_i, framed_out_i, framed_in_i, routed_out_i, r)
  begin
    rin <= r;

    case r.cmd_state is
      when ST_RESET =>
        rin.cmd_state <= ST_IDLE;

      when ST_IDLE =>
        if routed_in_i.valid = '1' then
          rin.cmd_state <= ST_ROUTE;
        end if;

      when ST_ROUTE =>
        if routed_in_i.valid = '1' then

          -- ignore short frames
          if routed_in_i.last = '1' then
            rin.cmd_state <= ST_IDLE;
          else
            rin.cmd_state <= ST_TAG;
          end if;
        end if;
        
      when ST_TAG =>
        if routed_in_i.valid = '1' then
          rin.last_tag <= routed_in_i.data;

          -- ignore short frames
          if routed_in_i.last = '1' then
            rin.cmd_state <= ST_IDLE;
          else
            rin.cmd_state <= ST_FORWARD;
          end if;
        end if;

      when ST_FORWARD =>
        if routed_in_i.valid = '1' and framed_out_i.ready = '1' and routed_in_i.last = '1' then
          rin.cmd_state <= ST_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when ST_RESET =>
        rin.rsp_state <= ST_IDLE;

      when ST_IDLE =>
        if framed_in_i.valid = '1' then
          rin.rsp_state <= ST_ROUTE;
        end if;

      when ST_ROUTE =>
        if routed_out_i.ready = '1' then
          rin.rsp_state <= ST_TAG;
        end if;
        
      when ST_TAG =>
        if routed_out_i.ready = '1' then
          rin.rsp_state <= ST_FORWARD;
        end if;

      when ST_FORWARD =>
        if framed_in_i.valid = '1' and routed_out_i.ready = '1' and framed_in_i.last = '1' then
          rin.rsp_state <= ST_IDLE;
        end if;
    end case;
  end process;

  mux: process(routed_in_i, framed_out_i, framed_in_i, routed_out_i, r)
  begin
    framed_out_o.valid <= '0';
    framed_out_o.data <= (others => '-');
    framed_out_o.last <= '-';
    routed_in_o.ready <= '0';

    routed_out_o.valid <= '0';
    routed_out_o.data <= (others => '-');
    routed_out_o.last <= '-';
    framed_in_o.ready <= '0';

    case r.cmd_state is
      when ST_RESET | ST_IDLE =>
        null;
        
      when ST_ROUTE | ST_TAG =>
        routed_in_o.ready <= '1';
        
      when ST_FORWARD =>
        framed_out_o <= routed_in_i;
        routed_in_o <= framed_out_i;
    end case;

    case r.rsp_state is
      when ST_RESET | ST_IDLE =>
        null;
        
      when ST_ROUTE =>
        routed_out_o.valid <= '1';
        routed_out_o.data <= nsl_bnoc.routed.routed_header(dst => target_id_i,
                                                           src => source_id_c);
        routed_out_o.last <= '0';

      when ST_TAG =>
        routed_out_o.valid <= '1';
        routed_out_o.data <= r.last_tag;
        routed_out_o.last <= '0';

      when ST_FORWARD =>
        routed_out_o <= framed_in_i;
        framed_in_o <= routed_out_i;
    end case;
  end process;
    
end architecture;
