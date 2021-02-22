library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

entity frequency_generator is
  generic (
    clock_rate_c : positive
    );
  port (
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    frequency_i : in unsigned;

    value_o : out std_ulogic
    );
end entity;

architecture beh of frequency_generator is

  constant overflow_bit_count : natural := nsl_math.arith.log2(clock_rate_c / 2);
  constant max_bit_count : natural := nsl_math.arith.log2(clock_rate_c / 2) + 1;
  constant half_rate : signed(max_bit_count-1 downto 0) := to_signed(clock_rate_c/2, max_bit_count);

  type regs_t is
  record
    counter : signed(max_bit_count-1 downto 0);
    offset : signed(max_bit_count-1 downto 0);
    freq : signed(max_bit_count-1 downto 0);
    value : std_ulogic;
  end record;

  signal r, rin : regs_t;

  signal frequency : signed(max_bit_count-1 downto 0);

begin

  assert frequency_i'length < max_bit_count - 1
    report "Input clock frequency is not fast enough for frequency range"
    severity failure;
  
  regs: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      r.counter <= (others => '0');
      r.value <= '1';
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  frequency <= signed(resize(frequency_i, frequency'length));
  
  transition: process(r, frequency) is
  begin
    rin <= r;

    rin.offset <= frequency - half_rate;
    rin.freq <= frequency;

    if r.counter < 0 then
      rin.counter <= r.counter - r.offset;
      rin.value <= not r.value;
    else
      rin.counter <= r.counter - r.freq;
    end if;

  end process;

  value_o <= r.value;

end architecture;
