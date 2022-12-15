library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_clocking, nsl_math, nsl_event;

entity nrzi_receiver_recovery is
  generic (
    clock_i_hz_c : natural;
    run_length_limit_c : natural := 3;
    signal_hz_c : natural;
    target_ppm_c : natural := 30000
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    data_i : in std_ulogic;

    bit_o : out std_ulogic;
    valid_o : out std_ulogic;

    tick_o : out std_ulogic
    );
end entity;

architecture beh of nrzi_receiver_recovery is
  
  type regs_t is
  record
    last_synced_data: std_ulogic;
    decoded_data: std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal s_synced, s_sample_tick: std_ulogic;
  
begin

  tick_o <= s_sample_tick;

  recovery: nsl_event.tick.tick_extractor_self_clocking
    generic map(
      period_max_c => integer(ceil(real(clock_i_hz_c) / real(signal_hz_c))),
      run_length_max_c => run_length_limit_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      signal_i => data_i,
      valid_o => s_synced,
      tick_180_o => s_sample_tick
      );

  regs: process(clock_i, reset_n_i, data_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.last_synced_data <= '0';
    end if;
  end process;

  transition: process(r, data_i, s_sample_tick) is
  begin
    rin <= r;

    if s_sample_tick = '1' then
      rin.last_synced_data <= data_i;
      if r.last_synced_data = data_i then
        rin.decoded_data <= '0';
      else
        rin.decoded_data <= '1';
      end if;
    end if;
  end process;

  bit_o <= r.decoded_data;
  valid_o <= s_synced and s_sample_tick;

end architecture;
