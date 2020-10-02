library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

entity async_input is
  generic (
    debounce_count_c: integer := 2
  );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    data_i: in std_ulogic;
    data_o: out std_ulogic;
    rising_o: out std_ulogic;
    falling_o: out std_ulogic
  );
end async_input;

architecture arch of async_input is

  type regs_t is
  record
    cur, prev : std_ulogic;
    debouncer : natural range 0 to debounce_count_c-1;
  end record;

  signal r, rin : regs_t;
  signal synced : std_ulogic;

begin

  sampler: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 1
      )
    port map(
      clock_i => clock_i,
      data_i(0) => data_i,
      data_o(0) => synced
      );
  
  regs: process(clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.cur <= '0';
      r.prev <= '0';
      r.debouncer <= 0;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, synced)
  begin
    rin <= r;

    if r.cur = synced then
      rin.debouncer <= debounce_count_c - 1;
    elsif r.debouncer /= 0 then
      rin.debouncer <= r.debouncer - 1;
    else
      rin.debouncer <= debounce_count_c;
      rin.cur <= synced;
    end if;

    rin.prev <= r.cur;
  end process;

  rising_o <= not r.prev and r.cur;
  falling_o <= r.prev and not r.cur;
  data_o <= r.cur;
  
end arch;

