library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;

entity fifo_framed_endpoint is
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_cmd_in_val   : in nsl.fifo.fifo_framed_cmd;
    p_cmd_in_ack   : out nsl.fifo.fifo_framed_rsp;
    p_cmd_out_val   : out nsl.fifo.fifo_framed_cmd;
    p_cmd_out_ack   : in nsl.fifo.fifo_framed_rsp;

    p_rsp_in_val   : in nsl.fifo.fifo_framed_cmd;
    p_rsp_in_ack   : out nsl.fifo.fifo_framed_rsp;
    p_rsp_out_val   : out nsl.fifo.fifo_framed_cmd;
    p_rsp_out_ack   : in nsl.fifo.fifo_framed_rsp
    );
end entity;

architecture rtl of fifo_framed_endpoint is

  type state_t is (
    ST_RESET,
    ST_GET_HEADER,
    ST_PUT_HEADER,
    ST_GET_TAG,
    ST_PUT_TAG,
    ST_FORWARD_CMD,
    ST_FORWARD_RSP
    );
  
  type regs_t is record
    state: state_t;
    cmd: framed_data_t;
  end record;  

  signal r, rin: regs_t;
  
begin

  regs: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(p_cmd_in_val, p_cmd_out_ack, p_rsp_in_val, p_rsp_out_ack, r)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_GET_HEADER;

      when ST_GET_HEADER =>
        if p_cmd_in_val.val = '1' then
          rin.cmd <= p_cmd_in_val.data(3 downto 0) & p_cmd_in_val.data(7 downto 4);
          rin.state <= ST_PUT_HEADER;
        end if;

      when ST_PUT_HEADER =>
        if p_rsp_out_ack.ack = '1' then
          rin.state <= ST_GET_TAG;
        end if;
        
      when ST_GET_TAG =>
        if p_cmd_in_val.val = '1' then
          rin.cmd <= p_cmd_in_val.data;
          rin.state <= ST_PUT_TAG;
        end if;

      when ST_PUT_TAG =>
        if p_rsp_out_ack.ack = '1' then
          rin.state <= ST_FORWARD_CMD;
        end if;

      when ST_FORWARD_CMD =>
        if p_cmd_in_val.val = '1' and p_cmd_out_ack.ack = '1' and p_cmd_in_val.more = '0' then
          rin.state <= ST_FORWARD_RSP;
        end if;

      when ST_FORWARD_RSP =>
        if p_rsp_in_val.val = '1' and p_rsp_out_ack.ack = '1' and p_rsp_in_val.more = '0' then
          rin.state <= ST_GET_HEADER;
        end if;
    end case;
  end process;

  mux: process(r, p_cmd_in_val, p_cmd_out_ack, p_rsp_in_val, p_rsp_out_ack)
  begin
    p_cmd_out_val.val <= '0';
    p_cmd_out_val.data <= (others => '-');
    p_cmd_out_val.more <= '-';
    p_cmd_in_ack.ack <= '0';

    p_rsp_out_val.val <= '0';
    p_rsp_out_val.data <= (others => '-');
    p_rsp_out_val.more <= '-';
    p_rsp_in_ack.ack <= '0';

    case r.state is
      when ST_RESET =>
        null;
        
      when ST_GET_HEADER | ST_GET_TAG =>
        p_cmd_in_ack.ack <= '1';
        
      when ST_PUT_HEADER | ST_PUT_TAG =>
        p_rsp_out_val.val <= '1';
        p_rsp_out_val.data <= r.cmd;
        p_rsp_out_val.more <= '1';
        
      when ST_FORWARD_CMD | ST_FORWARD_RSP =>
        p_cmd_out_val <= p_cmd_in_val;
        p_cmd_in_ack <= p_cmd_out_ack;
        p_rsp_out_val <= p_rsp_in_val;
        p_rsp_in_ack <= p_rsp_out_ack;
    end case;
  end process;
    
end architecture;
