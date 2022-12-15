library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity delay_line_regs is
  generic(
    data_width_c : integer;
    cycles_c : integer
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i : in  std_ulogic;

    ready_o : out std_ulogic;
    valid_i : in  std_ulogic;
    data_i : in std_ulogic_vector(data_width_c-1 downto 0);
    data_o : out std_ulogic_vector(data_width_c-1 downto 0)
    );
end entity;

architecture beh of delay_line_regs is

  subtype data_t is std_ulogic_vector(data_i'range);
  type data_vector is array (integer range <>) of data_t;
  
  type regs_t is
  record
    delay_line : data_vector(0 to cycles_c-1);
    ready : std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  reg: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.delay_line <= (others => (others => '0'));
      r.ready <= '0';
    end if;
  end process;

  transition: process(r, valid_i) is
  begin
    rin <= r;

    rin.ready <= '1';

    if valid_i = '1' then
      rin.delay_line <= r.delay_line(1 to r.delay_line'right) & data_i;
    end if;
  end process;

  data_o <= r.delay_line(0);
  ready_o <= r.ready;
  
end architecture;
