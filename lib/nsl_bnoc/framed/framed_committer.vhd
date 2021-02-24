library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

entity framed_committer is
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    data_i : in nsl_bnoc.framed.framed_data_t;
    valid_i : in std_ulogic;
    ready_o : out std_ulogic;

    flush_i : in std_ulogic;

    req_o : out nsl_bnoc.framed.framed_req;
    ack_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of framed_committer is

  type state_t is (
    ST_RESET,
    ST_FILL_0,
    ST_FILL_1,
    ST_FILL_2,
    ST_FILL_3
    );

  type word_t is
  record
    data : nsl_bnoc.framed.framed_data_t;
    last : std_ulogic;
  end record;

  type word_vector_t is array(natural range 0 to 2) of word_t;

  type regs_t is
  record
    state: state_t;
    data: word_vector_t;
  end record;

  signal r, rin: regs_t;

  attribute keep : string;
  attribute nomerge : string;
  attribute keep of r : signal is "TRUE";
  attribute nomerge of r : signal is "";

begin

  regs: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if reset_n_i = '0' then
        r.state <= ST_RESET;
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process(r, ack_i, data_i, valid_i, flush_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_FILL_0;

      when ST_FILL_0 =>
        if valid_i = '1' then
          -- (0) <- in
          rin.data(0).data <= data_i;
          rin.data(0).last <= '0';
          rin.state <= ST_FILL_1;
        end if;

      when ST_FILL_1 =>
        -- (0) is filled, can only go out if (0).last is set.
        if ack_i.ready = '1' and r.data(0).last = '1' then
          -- flushing here makes no sense.
          if valid_i = '1' then
            -- out <- (0) <- in
            rin.data(0).data <= data_i;
            rin.data(0).last <= '0';
          else
            -- out <- (0)
            rin.state <= ST_FILL_0;
          end if;
        else
          if valid_i = '1' then
            -- (1) <- in
            -- Last may be set to (0)
            rin.data(1).data <= data_i;
            rin.data(1).last <= '0';
            rin.state <= ST_FILL_2;
          end if;

          if flush_i = '1' then
            rin.data(0).last <= '1';
          end if;
        end if;

      when ST_FILL_2 =>
        -- (0) and (1) are filled. Can pipeline.
        if ack_i.ready = '1' then
          -- Last may be set to (0)
          rin.data(0) <= r.data(1);

          if valid_i = '1' then
            -- out <- (0) <- (1) <- in
            rin.data(1).data <= data_i;
            rin.data(1).last <= '0';
          else
            -- out <- (0) <- (1)
            -- Last may be set to (0)
            rin.state <= ST_FILL_1;
          end if;

          if flush_i = '1' then
            rin.data(0).last <= '1';
          end if;
        else
          -- Last may be set to (1)
          if valid_i = '1' then
            -- (2) <- in
            rin.data(2).data <= data_i;
            rin.data(2).last <= '0';
            rin.state <= ST_FILL_3;
          end if;

          if flush_i = '1' then
            rin.data(1).last <= '1';
          end if;
        end if;

      when ST_FILL_3 =>
        -- (0), (1) and (2) are filled. Cannot pipeline.
        if ack_i.ready = '1' then
          -- out <- (0) <- (1) <- (2)
          -- Last may be set to (1)
          rin.data(0) <= r.data(1);
          rin.data(1) <= r.data(2);
          rin.state <= ST_FILL_2;
          if flush_i = '1' then
            rin.data(1).last <= '1';
          end if;
        else
          -- No movement
          -- Last may be set to (2)
          if flush_i = '1' then
            rin.data(2).last <= '1';
          end if;
        end if;

    end case;
  end process;

  moore: process(r)
  begin
    case r.state is
      when ST_RESET | ST_FILL_0 =>
        req_o.valid <= '0';
        req_o.data <= (others => '-');
        req_o.last <= '-';

      when ST_FILL_1 =>
        -- Here, valid is last, as data should get out only if we are sure
        -- of flushing frame.
        req_o.valid <= r.data(0).last;
        req_o.data <= r.data(0).data;
        req_o.last <= r.data(0).last;

      when ST_FILL_2 | ST_FILL_3 =>
        req_o.valid <= '1';
        req_o.data <= r.data(0).data;
        req_o.last <= r.data(0).last;
    end case;

    case r.state is
      when ST_RESET | ST_FILL_3 =>
        ready_o <= '0';

      when ST_FILL_0 | ST_FILL_1 | ST_FILL_2 =>
        ready_o <= '1';
    end case;
  end process;

end architecture;
