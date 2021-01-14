library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking;

entity async_stabilizer is
  generic(
    stable_count_c : natural range 1 to 10 := 1;
    cycle_count_c : natural range 1 to 40 := 2;
    data_width_c : integer
    );
  port(
    clock_i    : in std_ulogic;
    data_i     : in std_ulogic_vector(data_width_c-1 downto 0);
    data_o     : out std_ulogic_vector(data_width_c-1 downto 0);
    stable_o   : out std_ulogic
    );
end async_stabilizer;

architecture rtl of async_stabilizer is
  
  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);

  signal last_stable_d, prev_sampled_d, sampled_s : word_t;
  signal unstable_s : natural range 0 to stable_count_c - 1;

begin

  sampler: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => cycle_count_c,
      data_width_c => data_width_c
      )
    port map(
      clock_i => clock_i,
      data_i => data_i,
      data_o => sampled_s
      );
  
  clock: process (clock_i)
  begin
    if rising_edge(clock_i) then
      prev_sampled_d <= sampled_s;
    
      if prev_sampled_d /= sampled_s then
        unstable_s <= stable_count_c - 1;
        stable_o <= '0';
      elsif unstable_s /= 0 then
        unstable_s <= unstable_s - 1;
        stable_o <= '0';
      else
        last_stable_d <= prev_sampled_d;
        stable_o <= '1';
      end if;

    end if;
  end process clock;
    
  data_o <= last_stable_d;
  
end rtl;
