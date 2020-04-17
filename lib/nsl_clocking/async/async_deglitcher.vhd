library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

entity async_deglitcher is

  generic(
    cycle_count_c : natural := 2
    );
  port (
    clock_i : in  std_ulogic;
    data_i  : in  std_ulogic;
    data_o : out std_ulogic
    );

end async_deglitcher;

architecture rtl of async_deglitcher is

begin

  shreg: if cycle_count_c < 4
  generate
    signal r_backlog : std_ulogic_vector(0 to cycle_count_c-1);
    signal r_value : std_ulogic;
  begin
    reg: process (clock_i)
    begin
      if rising_edge(clock_i) then
        r_backlog <= data_i & r_backlog(r_backlog'left to r_backlog'right-1);

        if r_backlog = (r_backlog'range => '1') then
          r_value <= '1';
        elsif r_backlog = (r_backlog'range => '0') then
          r_value <= '0';
        end if;
      end if;
    end process;

    data_o <= r_value;
  end generate;

  counter: if cycle_count_c >= 4
  generate
    signal r_counter : unsigned(nsl_math.arith.log2(cycle_count_c) downto 0) := (others => '0');
  begin
    reg: process (clock_i)
    begin
      if rising_edge(clock_i) then
        if data_i = '1' and r_counter /= (r_counter'range => '1') then
          r_counter <= r_counter + 1;
        elsif data_i = '0' and r_counter /= (r_counter'range => '0') then
          r_counter <= r_counter - 1;
        end if;
      end if;
    end process;

    data_o <= r_counter(r_counter'left);
  end generate;

end rtl;
