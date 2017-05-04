library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity baudrate_generator is
  generic(
    p_clk_rate : natural;
    rate_lsb   : natural := 8;
    rate_msb   : natural := 27
    );
  port(
    p_clk      : in std_ulogic;
    p_resetn   : in std_ulogic;
    p_rate     : in unsigned(rate_msb downto rate_lsb);
    p_tick     : out std_ulogic
    );

end baudrate_generator;

architecture rtl of baudrate_generator is

  subtype acc_t is unsigned(rate_msb downto rate_lsb);
  constant clk_mod : acc_t := to_unsigned(p_clk_rate,
                                          rate_msb + 1)(rate_msb downto rate_lsb);
  type regs_t is record
    acc      : acc_t;
    top      : acc_t;
    overflow : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin  -- rtl

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.acc <= (others => '0');
      r.overflow <= '0';
      r.top <= (others => '1');
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r)
  begin
    rin <= r;

    rin.top <= clk_mod - p_rate;

    if r.acc < r.top then
      rin.acc <= r.acc + p_rate;
      rin.overflow <= '0';
    else
      rin.acc <= r.acc - r.top;
      rin.overflow <= '1';
    end if;
  end process;

  p_tick <= r.overflow;

end rtl;
