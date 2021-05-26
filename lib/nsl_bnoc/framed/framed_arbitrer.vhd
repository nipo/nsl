library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_math;

entity framed_arbitrer is
  generic(
    source_count : natural
    );
  port(
    p_resetn   : in  std_ulogic;
    p_clk      : in  std_ulogic;

    p_selected : out unsigned(nsl_math.arith.log2(source_count)-1 downto 0);

    p_cmd_val   : in nsl_bnoc.framed.framed_req_array(0 to source_count - 1);
    p_cmd_ack   : out nsl_bnoc.framed.framed_ack_array(0 to source_count - 1);
    p_rsp_val   : out nsl_bnoc.framed.framed_req_array(0 to source_count - 1);
    p_rsp_ack   : in nsl_bnoc.framed.framed_ack_array(0 to source_count - 1);

    p_target_cmd_val   : out nsl_bnoc.framed.framed_req;
    p_target_cmd_ack   : in nsl_bnoc.framed.framed_ack;
    p_target_rsp_val   : in nsl_bnoc.framed.framed_req;
    p_target_rsp_ack   : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of framed_arbitrer is

  type state_t is (
    STATE_RESET,
    STATE_ELECT_FAIR,
    STATE_ELECT,
    STATE_FORWARD,
    STATE_FLUSH
    );

  type regs_t is record
    state : state_t;
    elected : natural range 0 to source_count - 1;
    last : natural range 0 to source_count - 1;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(p_resetn, p_clk)
  begin
    if rising_edge(p_clk) then
      r <= rin;
    end if;
    if p_resetn = '0' then
      r.state <= STATE_RESET;
    end if;
  end process;

  transition: process(p_cmd_val, p_rsp_ack, p_target_cmd_ack, p_target_rsp_val, r)
  begin
    rin <= r;

    case r.state is
      when STATE_RESET =>
        rin.state <= STATE_ELECT;

      when STATE_ELECT_FAIR =>
        rin.state <= STATE_ELECT;
        for i in source_count-1 downto 0 loop
          if p_cmd_val(i).valid = '1' and i /= r.elected then
            rin.elected <= i;
            rin.state <= STATE_FORWARD;
          end if;
        end loop;

      when STATE_ELECT =>
        for i in source_count-1 downto 0 loop
          if p_cmd_val(i).valid = '1' then
            rin.elected <= i;
            rin.state <= STATE_FORWARD;
          end if;
        end loop;

      when STATE_FORWARD =>
        if p_cmd_val(r.elected).valid = '1' and p_target_cmd_ack.ready = '1' and p_cmd_val(r.elected).last = '1' then
          rin.state <= STATE_FLUSH;
        end if;

      when STATE_FLUSH =>
        if p_target_rsp_val.valid = '1' and p_rsp_ack(r.elected).ready = '1' and p_target_rsp_val.last = '1' then
          rin.state <= STATE_ELECT_FAIR;
        end if;
        
    end case;
  end process;

  mux: process(r, p_cmd_val, p_rsp_ack, p_target_cmd_ack, p_target_rsp_val)
  begin
    ports: for i in 0 to source_count-1 loop
      p_cmd_ack(i).ready <= '0';
      p_rsp_val(i).valid <= '0';
      p_rsp_val(i).data <= (others => '-');
      p_rsp_val(i).last <= '-';
    end loop;
    p_target_rsp_ack.ready <= '0';
    p_target_cmd_val.valid <= '0';
    p_target_cmd_val.data <= (others => '-');
    p_target_cmd_val.last <= '-';

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

  p_selected <= to_unsigned(r.elected, p_selected'length);
  
end architecture;
