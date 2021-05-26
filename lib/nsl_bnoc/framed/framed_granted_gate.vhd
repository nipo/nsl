library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

entity framed_granted_gate is
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    request_o   : out std_ulogic;
    grant_i     : in  std_ulogic;
    busy_o      : out std_ulogic;

    in_cmd_i   : in  nsl_bnoc.framed.framed_req;
    in_cmd_o   : out nsl_bnoc.framed.framed_ack;
    in_rsp_o   : out nsl_bnoc.framed.framed_req;
    in_rsp_i   : in  nsl_bnoc.framed.framed_ack;
    out_cmd_o  : out nsl_bnoc.framed.framed_req;
    out_cmd_i  : in  nsl_bnoc.framed.framed_ack;
    out_rsp_i  : in  nsl_bnoc.framed.framed_req;
    out_rsp_o  : out nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of framed_granted_gate is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_FWD,
    ST_WAIT_DONE
    );

  type regs_t is
  record
    cmd_state: state_t;
    rsp_state: state_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= ST_RESET;
      r.rsp_state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_cmd_i, in_rsp_i, out_cmd_i, out_rsp_i)
  begin
    rin <= r;

    case r.cmd_state is
      when ST_RESET =>
        rin.cmd_state <= ST_IDLE;

      when ST_IDLE =>
        if in_cmd_i.valid = '1' and grant_i = '1' then
          rin.cmd_state <= ST_FWD;
        end if;

      when ST_FWD =>
        if in_cmd_i.valid = '1' and out_cmd_i.ready = '1' and in_cmd_i.last = '1' then
          rin.cmd_state <= ST_WAIT_DONE;
        end if;

      when ST_WAIT_DONE =>
        if r.rsp_state = ST_WAIT_DONE then
          rin.cmd_state <= ST_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when ST_RESET =>
        rin.rsp_state <= ST_IDLE;

      when ST_IDLE =>
        if r.cmd_state = ST_FWD then
          rin.rsp_state <= ST_FWD;
        end if;

      when ST_FWD =>
        if out_rsp_i.valid = '1' and in_rsp_i.ready = '1' and out_rsp_i.last = '1' then
          rin.rsp_state <= ST_WAIT_DONE;
        end if;

      when ST_WAIT_DONE =>
        if r.cmd_state = ST_WAIT_DONE then
          rin.rsp_state <= ST_IDLE;
        end if;
    end case;
  end process;

  out_cmd_o.data <= in_cmd_i.data;
  out_cmd_o.last <= in_cmd_i.last;
  out_cmd_o.valid <= in_cmd_i.valid when r.cmd_state = ST_FWD else '0';
  in_cmd_o.ready <= out_cmd_i.ready when r.cmd_state = ST_FWD else '0';

  in_rsp_o.data <= out_rsp_i.data;
  in_rsp_o.last <= out_rsp_i.last;
  in_rsp_o.valid <= out_rsp_i.valid when r.rsp_state = ST_FWD else '0';
  out_rsp_o.ready <= in_rsp_i.ready when r.rsp_state = ST_FWD else '0';
  
end architecture;
