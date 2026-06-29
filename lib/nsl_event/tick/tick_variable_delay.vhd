library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tick_variable_delay is
  generic(
    delay_max_l2_c : positive
    );
  port(
    clock_i : in  std_ulogic;
    reset_n_i : in std_ulogic;

    tick_i : in std_ulogic;
    tick_o : out std_ulogic;

    delay_i : in unsigned(delay_max_l2_c-1 downto 0)
    );
end tick_variable_delay;

architecture rtl of tick_variable_delay is

  constant num_regs : positive := 2**delay_max_l2_c;  
  signal s_data_shreg : std_ulogic_vector(num_regs - 1 downto 0);
  signal s_one_hot : std_ulogic_vector(num_regs - 1 downto 0);
  signal s_tick_vector : std_ulogic_vector(num_regs - 1 downto 0);
  
begin

  tick_o <= s_data_shreg(num_regs - 1);
  s_tick_vector <= (others => tick_i);

  -- One hot decode input delay
  one_hot: process(delay_i)
  begin
    for i in 0 to num_regs - 1 loop
      if i = to_integer(delay_i) then
        s_one_hot(i) <= '1';
      else
        s_one_hot(i) <= '0';
      end if;
    end loop;  -- i
  end process;

  -- Shift registers on rising edge of clock
  -- Use one hot to decide where to write  
  shift: process (clock_i, reset_n_i) is
  begin  -- process shift_write
    if reset_n_i = '0' then             -- asynchronous reset (active low)
      s_data_shreg <= (others => '0');
    elsif rising_edge(clock_i) then     -- rising clock edge
      s_data_shreg <= std_ulogic_vector(shift_left(unsigned(s_data_shreg), 1))
                      or (s_one_hot and s_tick_vector);
      end if;
  end process shift;

  
end rtl;
