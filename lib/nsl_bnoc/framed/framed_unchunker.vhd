library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;
use nsl_bnoc.pipe.all;
use nsl_bnoc.framed.all;

entity framed_unchunker is
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    in_i : in  nsl_bnoc.pipe.pipe_req_t;
    in_o : out nsl_bnoc.pipe.pipe_ack_t;

    reset_n_o : out std_ulogic;

    out_o : out framed_req_t;
    out_i : in framed_ack_t
    );
end entity;

architecture beh of framed_unchunker is

  type state_t is (
    ST_RESET,
    ST_CMD,
    ST_SIZE_LOW,
    ST_DATA
    );

  type regs_t is
  record
    state: state_t;
    data_left: unsigned(13 downto 0);
    reset: std_ulogic;
    last: std_ulogic;
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
      r.reset <= '0';
    end if;
  end process;

  transition: process(r, in_i, out_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_CMD;

      when ST_CMD =>
        if in_i.valid = '1' then
          if in_i.data(7) = '1' then
            rin.reset <= in_i.data(6);
          else
            rin.data_left(13 downto 8) <= unsigned(in_i.data(5 downto 0));
            rin.last <= in_i.data(6);
            rin.state <= ST_SIZE_LOW;
          end if;
        end if;

      when ST_SIZE_LOW =>
        if in_i.valid = '1' then
          rin.data_left(7 downto 0) <= unsigned(in_i.data);
          rin.state <= ST_DATA;
        end if;

      when ST_DATA =>
        if in_i.valid = '1' and out_i.ready = '1' then
          rin.data_left <= r.data_left - 1;
          if r.data_left = 0 then
            rin.state <= ST_CMD;
          end if;
        end if;
    end case;
  end process;

  mealy: process(r, in_i, out_i) is
  begin
    out_o <= framed_req_idle_c;
    in_o <= pipe_ack_idle_c;
    reset_n_o <= not r.reset;

    case r.state is
      when ST_RESET =>
        null;

      when ST_CMD | ST_SIZE_LOW =>
        in_o <= pipe_accept(true);

      when ST_DATA =>
        out_o <= framed_flit(in_i.data,
                             last => r.data_left = 0 and r.last = '1',
                             valid => in_i.valid = '1');
        in_o <= pipe_accept(out_i.ready = '1');
    end case;
  end process;
end architecture;
