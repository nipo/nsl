library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_math;
--library nsl_data;
--use nsl_data.text.all;

entity clock_rate_measurer is
  generic(
    clock_i_hz_c : integer;
    update_hz_l2_c : integer := 0
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;
    measured_clock_i: in std_ulogic;
    rate_hz_o: out unsigned
    );
end entity;

architecture beh of clock_rate_measurer is

  subtype counter_t is unsigned(rate_hz_o'length downto update_hz_l2_c);
  signal counter_s, counter_resync_s : counter_t := (others => '0');

  subtype rate_t is unsigned(rate_hz_o'length-1 downto update_hz_l2_c);

  constant update_interval_c : integer := clock_i_hz_c / (2 ** update_hz_l2_c);

  type regs_t is
  record
    cycles_to_go : integer range 0 to update_interval_c-1;
    last_counter : counter_t;
    rate : rate_t;
  end record;

  signal r, rin : regs_t;

begin

  free_running: process(measured_clock_i) is
  begin
    if rising_edge(measured_clock_i) then
      counter_s <= counter_s + 1;
    end if;
  end process;

  cross_domain: work.interdomain.interdomain_counter
    generic map(
      cycle_count_c => 2,
      data_width_c => counter_s'length,
      decode_stage_count_c => (counter_s'length + 3) / 4
      )
    port map(
      clock_in_i => measured_clock_i,
      clock_out_i => clock_i,
      data_i => counter_s,
      data_o => counter_resync_s
      );

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.last_counter <= (others => '0');
      r.cycles_to_go <= update_interval_c - 1;
    end if;
  end process;

  transition: process(r, counter_resync_s) is
  begin
    rin <= r;

    if r.cycles_to_go /= 0 then
      rin.cycles_to_go <= r.cycles_to_go - 1;
    else
      rin.cycles_to_go <= update_interval_c - 1;
      rin.last_counter <= counter_resync_s;
      rin.rate <= resize(counter_resync_s - r.last_counter, rin.rate'length);
    end if;
  end process;

  rate_hz_o(rate_hz_o'left downto update_hz_l2_c) <= r.rate;
  rate_hz_o(update_hz_l2_c-1 downto 0) <= (others => '0');

end architecture;

