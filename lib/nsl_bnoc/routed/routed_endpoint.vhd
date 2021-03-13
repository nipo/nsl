library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity routed_endpoint is
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_cmd_in_val   : in nsl_bnoc.routed.routed_req;
    p_cmd_in_ack   : out nsl_bnoc.routed.routed_ack;
    p_cmd_out_val   : out nsl_bnoc.framed.framed_req;
    p_cmd_out_ack   : in nsl_bnoc.framed.framed_ack;

    p_rsp_in_val   : in nsl_bnoc.framed.framed_req;
    p_rsp_in_ack   : out nsl_bnoc.framed.framed_ack;
    p_rsp_out_val   : out nsl_bnoc.routed.routed_req;
    p_rsp_out_ack   : in nsl_bnoc.routed.routed_ack
    );
end entity;

architecture rtl of routed_endpoint is

  type state_t is (
    ST_RESET,
    ST_GET_HEADER,
    ST_PUT_HEADER,
    ST_GET_TAG,
    ST_PUT_TAG,
    ST_PUT_TAG_LAST,
    ST_FORWARD_BOTH,
    ST_FORWARD_CMD,
    ST_FORWARD_RSP
    );
  
  type regs_t is record
    state: state_t;
    cmd: nsl_bnoc.framed.framed_data_t;
  end record;  

  signal r, rin: regs_t;
  
begin

  regs: process(p_clk, p_resetn)
  begin
    if rising_edge(p_clk) then
      r <= rin;
    end if;
    if p_resetn = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(p_cmd_in_val, p_cmd_out_ack, p_rsp_in_val, p_rsp_out_ack, r)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_GET_HEADER;

      when ST_GET_HEADER =>
        if p_cmd_in_val.valid = '1' then
          -- ignore short frames
          if p_cmd_in_val.last = '0' then
            rin.cmd <= p_cmd_in_val.data(3 downto 0) & p_cmd_in_val.data(7 downto 4);
            rin.state <= ST_PUT_HEADER;
          end if;
        end if;

      when ST_PUT_HEADER =>
        if p_rsp_out_ack.ready = '1' then
          rin.state <= ST_GET_TAG;
        end if;
        
      when ST_GET_TAG =>
        if p_cmd_in_val.valid = '1' then
          rin.cmd <= p_cmd_in_val.data;
          if p_cmd_in_val.last = '1' then
            -- Special treatment for empty frames
            rin.state <= ST_PUT_TAG_LAST;
          else
            rin.state <= ST_PUT_TAG;
          end if;
        end if;

      when ST_PUT_TAG =>
        if p_rsp_out_ack.ready = '1' then
          rin.state <= ST_FORWARD_BOTH;
        end if;

      when ST_PUT_TAG_LAST =>
        if p_rsp_out_ack.ready = '1' then
          rin.state <= ST_GET_HEADER;
        end if;

      when ST_FORWARD_BOTH =>
        if p_cmd_in_val.valid = '1' and p_cmd_out_ack.ready = '1' and p_cmd_in_val.last = '1'
          and p_rsp_in_val.valid = '1' and p_rsp_out_ack.ready = '1' and p_rsp_in_val.last = '1' then
          rin.state <= ST_GET_HEADER;
        elsif p_cmd_in_val.valid = '1' and p_cmd_out_ack.ready = '1' and p_cmd_in_val.last = '1' then
          rin.state <= ST_FORWARD_RSP;
        elsif p_rsp_in_val.valid = '1' and p_rsp_out_ack.ready = '1' and p_rsp_in_val.last = '1' then
          rin.state <= ST_FORWARD_CMD;
        end if;

      when ST_FORWARD_CMD =>
        if p_cmd_in_val.valid = '1' and p_cmd_out_ack.ready = '1' and p_cmd_in_val.last = '1' then
          rin.state <= ST_FORWARD_RSP;
        end if;

      when ST_FORWARD_RSP =>
        if p_rsp_in_val.valid = '1' and p_rsp_out_ack.ready = '1' and p_rsp_in_val.last = '1' then
          rin.state <= ST_GET_HEADER;
        end if;
    end case;
  end process;

  mux: process(p_cmd_in_val, p_cmd_out_ack, p_rsp_in_val, p_rsp_out_ack, r)
  begin
    p_cmd_out_val.valid <= '0';
    p_cmd_out_val.data <= (others => '-');
    p_cmd_out_val.last <= '-';
    p_cmd_in_ack.ready <= '0';

    p_rsp_out_val.valid <= '0';
    p_rsp_out_val.data <= (others => '-');
    p_rsp_out_val.last <= '-';
    p_rsp_in_ack.ready <= '0';

    case r.state is
      when ST_RESET =>
        null;
        
      when ST_GET_HEADER | ST_GET_TAG =>
        p_cmd_in_ack.ready <= '1';
        
      when ST_PUT_HEADER | ST_PUT_TAG =>
        p_rsp_out_val.valid <= '1';
        p_rsp_out_val.data <= r.cmd;
        p_rsp_out_val.last <= '0';

      when ST_PUT_TAG_LAST =>
        p_rsp_out_val.valid <= '1';
        p_rsp_out_val.data <= r.cmd;
        p_rsp_out_val.last <= '1';
        
      when ST_FORWARD_BOTH =>
        p_cmd_out_val <= p_cmd_in_val;
        p_cmd_in_ack <= p_cmd_out_ack;
        p_rsp_out_val <= p_rsp_in_val;
        p_rsp_in_ack <= p_rsp_out_ack;
        
      when ST_FORWARD_CMD =>
        p_cmd_out_val <= p_cmd_in_val;
        p_cmd_in_ack <= p_cmd_out_ack;

      when ST_FORWARD_RSP =>
        p_rsp_out_val <= p_rsp_in_val;
        p_rsp_in_ack <= p_rsp_out_ack;
    end case;
  end process;
    
end architecture;
