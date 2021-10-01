library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nrzi_transmitter is
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    valid_i : in std_ulogic;
    bit_i : in std_ulogic;

    data_o : out std_ulogic
    );
end entity;

architecture beh of nrzi_transmitter is

  type regs_t is
  record
    value: std_ulogic;
  end record;

  signal r, rin: regs_t;
  
begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.value <= '0';
    end if;
  end process;

  transition: process(r, bit_i, valid_i) is
  begin
    rin <= r;

    if valid_i = '1' then
      if bit_i = '1' then
        rin.value <= not r.value;
      end if;
    end if;
  end process;

  data_o <= r.value;

end architecture;
