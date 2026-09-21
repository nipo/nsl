library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

entity interdomain_tick is
  port(
    input_clock_i : in  std_ulogic;
    output_clock_i : in  std_ulogic;
    input_reset_n_i : in std_ulogic;
    tick_i : in  std_ulogic;
    tick_o : out std_ulogic
    );
end interdomain_tick;

architecture rtl of interdomain_tick is

  signal r_input_bistable: std_ulogic;
  signal s_output_bistable: std_ulogic;
  signal r_output_bistable: std_ulogic;
  signal s_output_reset_n: std_ulogic;
  
begin

  input_clock : process(input_clock_i, input_reset_n_i) is
  begin
    if rising_edge(input_clock_i) then
      if tick_i = '1' then
        r_input_bistable <= not r_input_bistable;
      end if;
    end if;

    if input_reset_n_i = '0' then
      r_input_bistable <= '0';
    end if;
  end process input_clock;

  sampler: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => 1
      )
    port map(
      clock_i => output_clock_i,
      data_i(0) => r_input_bistable,
      data_o(0) => s_output_bistable
      );

  -- The output side turns any change of the sampled bistable into a
  -- tick, and reset changes it without a tick ever happening: it
  -- forces the input side to '0' from wherever it stood, and out of
  -- power-up the sampler settles to that '0' from an undefined
  -- value. Carry the reset over, asynchronously asserted so it always
  -- reaches the output side before the change it covers, and hold the
  -- edge detector at the value the input side resets to.
  output_reset: nsl_clocking.async.async_edge
    generic map(
      cycle_count_c => 2,
      target_value_c => '1',
      async_reset_c => true
      )
    port map(
      clock_i => output_clock_i,
      data_i => input_reset_n_i,
      data_o => s_output_reset_n
      );

  output_clock : process(output_clock_i) is
  begin
    if rising_edge(output_clock_i) then
      if s_output_reset_n = '1' then
        r_output_bistable <= s_output_bistable;
        if s_output_bistable /= r_output_bistable then
          tick_o <= '1';
        else
          tick_o <= '0';
        end if;
      else
        r_output_bistable <= '0';
        tick_o <= '0';
      end if;
    end if;
  end process output_clock;

end rtl;
