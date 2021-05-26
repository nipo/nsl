library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity framed_gate is
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    enable_i   : in std_ulogic;

    in_i   : in nsl_bnoc.framed.framed_req;
    in_o   : out nsl_bnoc.framed.framed_ack;
    out_o   : out nsl_bnoc.framed.framed_req;
    out_i   : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of framed_gate is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_FWD
    );

  type regs_t is
  record
    state: state_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i, enable_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if in_i.valid = '1' and out_i.ready = '1' and enable_i = '1' then
          if in_i.last = '0' then
            rin.state <= ST_FWD;
          end if;
        end if;

      when ST_FWD =>
        if in_i.valid = '1' and out_i.ready = '1' and in_i.last = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  out_o.data <= in_i.data;
  out_o.last <= in_i.last;
  out_o.valid <= in_i.valid and enable_i;
  in_o.ready <= out_i.ready and enable_i;
  
end architecture;
