--  Copyright (c) 2016, Vincent Defilippi <vincentdefilippi@gmail.com>

library ieee;
use ieee.std_logic_1164.all;

entity sync_input is
  generic (
    N: integer := 2
  );
  port (
    p_clk: in std_ulogic;
    p_resetn: in std_ulogic;
    p_input: in std_ulogic;
    p_output: out std_ulogic;
    p_rise: out std_ulogic;
    p_fall: out std_ulogic
  );
end sync_input;

architecture arch of sync_input is

  type state_type is (
    S_IDLE,
    S_LOW,
    S_HIGH,
    S_RISE,
    S_FALL
   );
  signal state: state_type;

  signal sreg: std_ulogic_vector(N - 1 downto 0);
  constant SREG_MAX: std_ulogic_vector(N - 1 downto 0) := (others => '1');
  constant SREG_MIN: std_ulogic_vector(N - 1 downto 0) := (others => '0');

begin

  p_output <=
    '1' when state = S_RISE or state = S_HIGH else
    '0' when state = S_FALL or state = S_LOW else
    p_input;

  p_rise <= '1' when state = S_RISE else '0';
  p_fall <= '1' when state = S_FALL else '0';

  process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      state <= S_IDLE;
    elsif rising_edge(p_clk) then
      case state is
        when S_IDLE =>
          if p_input = '0' then
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

      sreg <= sreg(N - 2 downto 0) & p_input;
    end if;
  end process;

end arch;

