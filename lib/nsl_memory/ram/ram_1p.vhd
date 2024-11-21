library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_1p is
  generic (
    addr_size_c : natural;
    data_size_c : natural
    );
  port (
    clock_i   : in  std_ulogic;

    address_i  : in  unsigned(addr_size_c-1 downto 0);
    enable_i   : in  std_ulogic := '1';

    write_en_i   : in  std_ulogic;
    write_data_i : in  std_ulogic_vector (data_size_c-1 downto 0);

    read_data_o : out std_ulogic_vector (data_size_c-1 downto 0)
    );
end ram_1p;

architecture inferred of ram_1p is

  subtype word_t is std_ulogic_vector(data_size_c - 1 downto 0);
  type mem_t is array(2**addr_size_c - 1 downto 0) of word_t;
  shared variable r_mem: mem_t;

begin

  process (clock_i)
    variable addr : natural range 0 to 2**addr_size_c-1;
  begin
    if rising_edge(clock_i) then
      addr := to_integer(to_01(address_i, '0'));

      if enable_i = '1' then
        if write_en_i = '1' then
          r_mem(addr) := write_data_i;
        end if;

        read_data_o <= r_mem(addr);
      end if;
    end if;
  end process;

end inferred;
