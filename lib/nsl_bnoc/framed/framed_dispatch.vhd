library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_math;
use nsl_bnoc.framed.all;

entity framed_dispatch is
  generic(
    destination_count_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    enable_i : in std_ulogic := '1';
    destination_i  : in natural range 0 to destination_count_c - 1;
    
    in_i   : in framed_req;
    in_o   : out framed_ack;

    out_o   : out framed_req_array(0 to destination_count_c - 1);
    out_i   : in framed_ack_array(0 to destination_count_c - 1)
    );
end entity;

architecture rtl of framed_dispatch is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_FORWARD
    );

  type regs_t is record
    state : state_t;
    selected : natural range 0 to destination_count_c - 1;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(in_i, out_i, r, enable_i, destination_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if enable_i = '1' then
          rin.selected <= destination_i;
          if in_i.valid = '1' then
            rin.state <= ST_FORWARD;
          end if;
        end if;

      when ST_FORWARD =>
        if in_i.valid = '1' and in_i.last = '1' and out_i(r.selected).ready = '1' then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  mux: process(r, in_i, out_i)
  begin
    in_o.ready <= '0';
    out_o <= (others => (valid => '0', data => (others => '-'), last => '-'));

    case r.state is
      when ST_FORWARD =>
        out_o(r.selected) <= in_i;
        in_o <= out_i(r.selected);

      when others =>
        null;
    end case;
  end process;
end architecture;
