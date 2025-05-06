library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_clocking, nsl_logic;
use nsl_logic.bool.all;

entity fifo_count is
  generic(
    max_count_l2_c : natural;
    clock_count_c : natural range 1 to 2
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic_vector(0 to clock_count_c-1);

    out_ready_i : in  std_ulogic;
    out_valid_o : out std_ulogic;
    out_counter_o : out unsigned(max_count_l2_c-1 downto 0);

    in_valid_i : in  std_ulogic;
    in_ready_o : out std_ulogic := '1';
    in_counter_o : out unsigned(max_count_l2_c-1 downto 0)
    );
end entity;

architecture beh of fifo_count is

  subtype counter_t is unsigned(max_count_l2_c-1 downto 0);
  
  type side_t is
  record
    cur, nxt: counter_t;
  end record;

  signal in_pos_in_s, in_pos_out_s: counter_t;
  signal out_pos_in_s, out_pos_out_s: counter_t;

begin

  in_side: block is
    signal r, rin: side_t;
    alias clock_s : std_ulogic is clock_i(0);
    signal reset_n_s : std_ulogic;
  begin
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => clock_s,
        data_i => reset_n_i,
        data_o => reset_n_s
        );
    
    regs: process(clock_s, reset_n_s) is
    begin
      if rising_edge(clock_s) then
        r <= rin;
      end if;

      if reset_n_s = '0' then
        r.cur <= to_unsigned(0, counter_t'length);
        r.nxt <= to_unsigned(1, counter_t'length);
      end if;
    end process;

    transition: process(r, in_valid_i, out_pos_in_s) is
    begin
      rin <= r;

      if r.nxt /= out_pos_in_s then
        if in_valid_i = '1' then
          rin.nxt <= r.nxt + 1;
          rin.cur <= r.nxt;
        end if;
      end if;
    end process;

    outputs: process(r, out_pos_in_s) is
    begin
      in_counter_o <= r.cur - out_pos_in_s;
      in_ready_o <= to_logic(r.nxt /= out_pos_in_s);
      in_pos_in_s <= r.cur;
    end process;
  end block;
  
  out_side: block is
    signal r, rin: side_t;
    alias clock_s : std_ulogic is clock_i(clock_count_c-1);
    signal reset_n_s : std_ulogic;
  begin
    reset_sync: nsl_clocking.async.async_edge
      port map(
        clock_i => clock_s,
        data_i => reset_n_i,
        data_o => reset_n_s
        );
    
    regs: process(clock_s, reset_n_s) is
    begin
      if rising_edge(clock_s) then
        r <= rin;
      end if;

      if reset_n_s = '0' then
        r.cur <= to_unsigned(0, counter_t'length);
        r.nxt <= to_unsigned(1, counter_t'length);
      end if;
    end process;

    transition: process(r, out_ready_i, in_pos_out_s) is
    begin
      rin <= r;

      if r.cur /= in_pos_out_s then
        if out_ready_i = '1' then
          rin.nxt <= r.nxt + 1;
          rin.cur <= r.nxt;
        end if;
      end if;
    end process;

    ouptuts: process(r, in_pos_out_s) is
    begin
      out_counter_o <= in_pos_out_s - r.cur;
      out_valid_o <= to_logic(r.cur /= in_pos_out_s);
      out_pos_out_s <= r.cur;
    end process;
  end block;

  no_resync: if clock_count_c = 1
  generate
  begin
    out_pos_in_s <= out_pos_out_s;
    in_pos_out_s <= in_pos_in_s;
  end generate;

  do_resync: if clock_count_c = 2
  generate
  begin
    out_to_in: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => counter_t'length
        )
      port map(
        clock_in_i => clock_i(1),
        clock_out_i => clock_i(0),
        data_i => out_pos_out_s,
        data_o => out_pos_in_s
        );

    in_to_out: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => counter_t'length
        )
      port map(
        clock_in_i => clock_i(0),
        clock_out_i => clock_i(1),
        data_i => in_pos_in_s,
        data_o => in_pos_out_s
        );
  end generate;

end architecture;
