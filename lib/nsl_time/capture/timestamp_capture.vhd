library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.timestamp.all;

entity timestamp_capture is
  generic(
    id_bits_c : natural range 1 to 4 := 2
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    timestamp_i : in timestamp_t;
    strobe_i : in std_ulogic;
    id_i : in unsigned(3 downto 0);

    read_id_i : in unsigned(3 downto 0);
    read_timestamp_o : out timestamp_t
    );
end entity;

architecture beh of timestamp_capture is

  constant register_count_c: natural := 2 ** id_bits_c;

  type timestamp_vector is array(natural range <>) of timestamp_t;

  type regs_t is
  record
    timestamp: timestamp_vector(0 to register_count_c-1);
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.timestamp <= (others => timestamp_zero_c);
    end if;
  end process;

  transition: process(r, timestamp_i, strobe_i, id_i) is
  begin
    rin <= r;

    if strobe_i = '1' then
      rin.timestamp(to_integer(id_i(id_bits_c-1 downto 0))) <= timestamp_i;
    end if;
  end process;

  mealy: process(r, read_id_i) is
  begin
    read_timestamp_o <= r.timestamp(to_integer(read_id_i(id_bits_c-1 downto 0)));
  end process;

end architecture;
