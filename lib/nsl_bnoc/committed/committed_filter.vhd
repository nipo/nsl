library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory, nsl_math;
use nsl_bnoc.committed.all;

entity committed_filter is
  generic(
    max_size_c : natural := 2048
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    in_i   : in  committed_req;
    in_o   : out committed_ack;
    out_o  : out committed_req;
    out_i  : in committed_ack
    );
end entity;

architecture beh of committed_filter is

  constant word_count_l2_c : natural := nsl_math.arith.log2(max_size_c-1);
  
  type state_t is (
    ST_RESET,
    ST_FILL,
    ST_OVERFLOW,
    ST_COMMIT,
    ST_CANCEL
    );

  type regs_t is
  record
    state : state_t;
  end record;

  signal r, rin: regs_t;

  signal in_ready_s, in_valid_s, do_commit_s, do_rollback_s : std_ulogic;
  signal in_free_s : unsigned(word_count_l2_c downto 0);
  
begin

  fifo: nsl_memory.fifo.fifo_cancellable
    generic map(
      data_width_c => 9,
      word_count_l2_c => word_count_l2_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      out_data_o(7 downto 0) => out_o.data,
      out_data_o(8) => out_o.last,
      out_ready_i => out_i.ready,
      out_valid_o => out_o.valid,

      in_data_i(7 downto 0) => in_i.data,
      in_data_i(8) => in_i.last,
      in_ready_o => in_ready_s,
      in_valid_i => in_valid_s,

      in_free_o => in_free_s,

      in_commit_i => do_commit_s,
      in_rollback_i => do_rollback_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, in_ready_s, in_free_s) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_FILL;

      when ST_FILL =>
        if in_free_s = 0 and in_ready_s = '0' then
          if in_i.valid = '1' and in_i.last = '1' then
            rin.state <= ST_CANCEL;
          else
            rin.state <= ST_OVERFLOW;
          end if;
        else
          if in_i.valid = '1' and in_i.last = '1' then
            if in_i.data(0) = '1' then
              rin.state <= ST_COMMIT;
            else
              rin.state <= ST_CANCEL;
            end if;
          end if;
        end if;

      when ST_OVERFLOW =>
        if in_i.valid = '1' and in_i.last = '1' then
          rin.state <= ST_CANCEL;
        end if;

      when ST_CANCEL | ST_COMMIT =>
        rin.state <= ST_FILL;
    end case;
  end process;

  mealy: process(r, in_i, in_ready_s) is
  begin
    do_rollback_s <= '0';
    do_commit_s <= '0';
    in_valid_s <= '0';
    in_o.ready <= '0';

    case r.state is
      when ST_FILL =>
        in_valid_s <= in_i.valid;
        in_o.ready <= in_ready_s;

      when ST_COMMIT =>
        do_commit_s <= '1';

      when ST_CANCEL =>
        do_rollback_s <= '1';

      when ST_OVERFLOW =>
        in_o.ready <= '1';

      when others =>
        null;
    end case;
  end process;
      
end architecture;
