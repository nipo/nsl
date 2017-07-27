library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;
use util.numeric.log2;

entity activity_monitor is
  generic (
    blink_time : natural;
    on_value : std_ulogic := '1'
    );
  port (
    p_resetn      : in  std_ulogic;
    p_clk         : in  std_ulogic;
    p_togglable   : in  std_ulogic;
    p_activity    : out std_ulogic
    );
end activity_monitor;

architecture rtl of activity_monitor is

  constant size : natural := log2(blink_time);
  subtype counter_t is unsigned(size - 1 downto 0);
  constant ctr_init: counter_t := counter_t(to_unsigned(blink_time-1, counter_t'length));
  constant ctr_zero: counter_t := (others => '0');

  type regs_t is record
    old: std_ulogic;
    inactive_timeout: counter_t;
    blink_timeout: counter_t;
    blink: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.inactive_timeout <= (others => '0');
      r.blink_timeout <= (others => '0');
      r.old <= '0';
      r.blink <= '0';
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  process (r, p_togglable)
  begin
    rin <= r;
    
    if r.inactive_timeout /= ctr_zero then
      rin.inactive_timeout <= r.inactive_timeout - 1;
    end if;

    if r.inactive_timeout = ctr_zero then
      rin.blink <= '0';
    elsif r.blink_timeout = ctr_zero then
      rin.blink_timeout <= ctr_init;
      rin.blink <= not r.blink;
    else
      rin.blink_timeout <= r.blink_timeout - 1;
    end if;

    if r.old /= p_togglable then
      if r.inactive_timeout = ctr_zero then
        rin.blink_timeout <= ctr_init;
        rin.blink <= '1';
      end if;
      rin.inactive_timeout <= ctr_init;
    end if;
    
    rin.old <= p_togglable;
    
  end process;

  p_activity <= on_value xnor r.blink;
  
end rtl;
