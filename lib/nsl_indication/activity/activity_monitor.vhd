library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

entity activity_monitor is
  generic (
    blink_cycles_c : natural;
    on_value_c : std_ulogic := '1'
    );
  port (
    reset_n_i      : in  std_ulogic;
    clock_i         : in  std_ulogic;
    togglable_i   : in  std_ulogic;
    activity_o    : out std_ulogic
    );
end activity_monitor;

architecture rtl of activity_monitor is

  constant size : natural := nsl_math.arith.log2(blink_cycles_c);
  subtype counter_t is unsigned(size - 1 downto 0);
  constant ctr_init: counter_t := counter_t(to_unsigned(blink_cycles_c-1, counter_t'length));
  constant ctr_zero: counter_t := (others => '0');

  type regs_t is record
    old: std_ulogic;
    inactive_timeout: counter_t;
    blink_timeout: counter_t;
    blink: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.inactive_timeout <= (others => '0');
      r.blink_timeout <= (others => '0');
      r.old <= '0';
      r.blink <= '0';
    end if;
  end process;

  process (r, togglable_i)
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

    if r.old /= togglable_i then
      if r.inactive_timeout = ctr_zero then
        rin.blink_timeout <= ctr_init;
        rin.blink <= '1';
      end if;
      rin.inactive_timeout <= ctr_init;
    end if;
    
    rin.old <= togglable_i;
    
  end process;

  activity_o <= on_value_c xnor r.blink;
  
end rtl;
