library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

entity async_multi_reset is
  generic(
    debounce_count_c : natural := 2;
    domain_count_c : natural;
    reset_assert_value_c : std_ulogic := '0'
    );
  port (
    clock_i : in  std_ulogic_vector(0 to domain_count_c-1);
    master_i  : in  std_ulogic;
    slave_o : out std_ulogic_vector(0 to domain_count_c-1)
    );
end async_multi_reset;

architecture rtl of async_multi_reset is

  constant reset_deassert_value_c : std_ulogic := not reset_assert_value_c;
  signal common : std_ulogic_vector(0 to domain_count_c-1) := (others => reset_assert_value_c);
  signal merged : std_ulogic := reset_assert_value_c;

begin

  byport: for i in 0 to domain_count_c - 1 generate
    sync_in: nsl_clocking.async.async_edge
      generic map(
        cycle_count_c => 2,
        target_value_c => reset_deassert_value_c,
        async_reset_c => true
        )
      port map(
        clock_i => clock_i(i),
        data_i => master_i,
        data_o => common(i)
        );

    sync_out: nsl_clocking.async.async_edge
      generic map(
        target_value_c => reset_deassert_value_c,
        async_reset_c => true,
        cycle_count_c => debounce_count_c
        )
      port map(
        clock_i => clock_i(i),
        data_i => merged,
        data_o => slave_o(i)
        );
  end generate;

  merged <= reset_deassert_value_c
            when common = (common'range => reset_deassert_value_c)
            else reset_assert_value_c;

end rtl;
