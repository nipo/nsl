library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity event_counter is
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    event_i : in std_ulogic;
    
    count_o   : out unsigned
    );
end entity;

architecture beh of event_counter is

  type regs_t is
  record
    count: unsigned(count_o'length-1 downto 0);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.count <= (others => '0');
    end if;
  end process;

  transition: process(r, event_i) is
  begin
    rin <= r;

    if event_i = '1' then
      rin.count <= r.count + 1;
    end if;
  end process;
  
  count_o <= r.count;

end architecture;
