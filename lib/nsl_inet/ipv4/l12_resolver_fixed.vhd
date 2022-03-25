library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ipv4.all;

entity l12_resolve_fixed is
  generic(
    l12_header_c : byte_string
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- Resolver API for IP usage
    query_i : in nsl_bnoc.framed.framed_req;
    query_o : out nsl_bnoc.framed.framed_ack;
    reply_o : out nsl_bnoc.framed.framed_req;
    reply_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of l12_resolve_fixed is

  constant reply_c : byte_string(l12_header_c'length-1 downto 0) := l12_header_c;

  type state_t is (
    ST_RESET,

    ST_TAKE_QUERY,
    ST_PUT_STATUS,
    ST_PUT_REPLY
    );

  type regs_t is
  record
    state : state_t;
    left: integer range 0 to reply_c'length-1;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, query_i, reply_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_TAKE_QUERY;

      when ST_TAKE_QUERY =>
        if query_i.valid = '1' and query_i.last = '1' then
          rin.state <= ST_PUT_STATUS;
        end if;

      when ST_PUT_STATUS =>
        if reply_i.ready = '1' then
          rin.state <= ST_PUT_REPLY;
          rin.left <= reply_c'length-1;
        end if;

      when ST_PUT_REPLY =>
        if reply_i.ready = '1' then
          if r.left /= 0 then
            rin.left <= r.left - 1;
          else
            rin.state <= ST_TAKE_QUERY;
          end if;
        end if;
    end case;
  end process;

  mealy: process(r) is
  begin
    reply_o.valid <= '0';
    reply_o.last <= '-';
    reply_o.data <= (others => '-');
    query_o.ready <= '0';

    case r.state is
      when ST_RESET =>
        null;

      when ST_TAKE_QUERY =>
        query_o.ready <= '1';

      when ST_PUT_STATUS =>
        reply_o.valid <= '1';
        reply_o.last <= '0';
        reply_o.data <= x"01";

      when ST_PUT_REPLY =>
        reply_o.valid <= '1';
        reply_o.data <= reply_c(r.left);
        if r.left = 0 then
          reply_o.last <= '1';
        else
          reply_o.last <= '0';
        end if;
    end case;
  end process;

end architecture;
