--  Copyright (c) 2016, Vincent Defilippi <vincentdefilippi@gmail.com>

library ieee;
use ieee.std_logic_1164.all;

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

  type state_type is (
    S_IDLE,
    S_LOW,
    S_HIGH,
    S_RISE,
    S_FALL
   );
  signal state: state_type;

  signal sreg: std_ulogic_vector(debounce_count_c - 1 downto 0);
  constant SREG_MAX: std_ulogic_vector(debounce_count_c - 1 downto 0) := (others => '1');
  constant SREG_MIN: std_ulogic_vector(debounce_count_c - 1 downto 0) := (others => '0');

begin

  data_o <=
    '1' when state = S_RISE or state = S_HIGH else
    '0' when state = S_FALL or state = S_LOW else
    data_i;

  rising_o <= '1' when state = S_RISE else '0';
  falling_o <= '1' when state = S_FALL else '0';

  process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      state <= S_IDLE;
    elsif rising_edge(clock_i) then
      case state is
        when S_IDLE =>
          if data_i = '0' then
            state <= S_LOW;
          else
            state <= S_HIGH;
          end if;

        when S_RISE =>
          state <= S_HIGH;

        when S_FALL =>
          state <= S_LOW;

        when S_HIGH =>
          if sreg = SREG_MIN then
            state <= S_FALL;
          end if;

        when S_LOW =>
          if sreg = SREG_MAX then
            state <= S_RISE;
          end if;
      end case;

      sreg <= sreg(debounce_count_c - 2 downto 0) & data_i;
    end if;
  end process;

end arch;

