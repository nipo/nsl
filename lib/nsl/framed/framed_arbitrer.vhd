library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;

entity framed_arbitrer is
  generic(
    source_count : natural
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_cmd_val   : in framed_req_array(0 to source_count - 1);
    p_cmd_ack   : out framed_ack_array(0 to source_count - 1);
    p_rsp_val   : out framed_req_array(0 to source_count - 1);
    p_rsp_ack   : in framed_ack_array(0 to source_count - 1);

    p_target_cmd_val   : out framed_req;
    p_target_cmd_ack   : in framed_ack;
    p_target_rsp_val   : in framed_req;
    p_target_rsp_ack   : out framed_ack
    );
end entity;

architecture rtl of framed_arbitrer is

  type state_t is (
    STATE_RESET,
    STATE_ELECT,
    STATE_FORWARD,
    STATE_FLUSH
    );

  type regs_t is record
    state : state_t;
    elected : natural range 0 to source_count - 1;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(p_cmd_val, p_rsp_ack, p_target_cmd_ack, p_target_rsp_val, r)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_ELECT;

      when STATE_ELECT =>
        ports: for i in source_count-1 downto 0 loop
          if p_cmd_val(i).val = '1' then
            rin.elected <= i;
            rin.state <= STATE_FORWARD;
          end if;
        end loop;

      when STATE_FORWARD =>
        if p_cmd_val(r.elected).val = '1' and p_target_cmd_ack.ack = '1' and p_cmd_val(r.elected).more = '0' then
          rin.state <= STATE_FLUSH;
        end if;

      when STATE_FLUSH =>
        if p_target_rsp_val.val = '1' and p_rsp_ack(r.elected).ack = '1' and p_target_rsp_val.more = '0' then
          rin.state <= STATE_ELECT;
        end if;
        
    end case;
  end process;

  mux: process(r, p_cmd_val, p_rsp_ack, p_target_cmd_ack, p_target_rsp_val)
  begin
    ports: for i in 0 to source_count-1 loop
      p_cmd_ack(i).ack <= '0';
      p_rsp_val(i).val <= '0';
      p_rsp_val(i).data <= (others => '-');
      p_rsp_val(i).more <= '-';
    end loop;
    p_target_rsp_ack.ack <= '0';
    p_target_cmd_val.val <= '0';
    p_target_cmd_val.data <= (others => '-');
    p_target_cmd_val.more <= '-';

    case r.state is
      when STATE_FORWARD =>
        p_target_cmd_val <= p_cmd_val(r.elected);
        p_cmd_ack(r.elected) <= p_target_cmd_ack;
        p_rsp_val(r.elected) <= p_target_rsp_val;
        p_target_rsp_ack <= p_rsp_ack(r.elected);
        
      when STATE_FLUSH =>
        p_rsp_val(r.elected) <= p_target_rsp_val;
        p_target_rsp_ack <= p_rsp_ack(r.elected);

      when others =>
        null;
    end case;
  end process;
    
end architecture;
