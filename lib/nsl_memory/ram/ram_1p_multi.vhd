library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_1p_multi is
  generic (
    addr_size_c : natural;
    word_size_c : natural := 8;
    data_word_count_c : integer := 4
    );
  port (
    clock_i : in std_ulogic;

    address_i : in unsigned(addr_size_c-1 downto 0);
    enable_i : in std_ulogic := '1';

    write_en_i : in std_ulogic_vector(data_word_count_c-1 downto 0);
    write_data_i : in std_ulogic_vector(word_size_c * data_word_count_c-1 downto 0);

    read_data_o : out std_ulogic_vector(word_size_c * data_word_count_c-1 downto 0)
    );
end ram_1p_multi;

architecture inferred of ram_1p_multi is

  subtype word_t is std_ulogic_vector(data_word_count_c*word_size_c - 1 downto 0);
  type mem_t is array(2**addr_size_c - 1 downto 0) of word_t;
  shared variable r_mem: mem_t;

begin

  process (clock_i)
    variable addr : natural range 0 to 2**addr_size_c-1;
  begin
    addr := to_integer(to_01(address_i, '0'));

    if rising_edge(clock_i) then
      if enable_i = '1' then
        for i in 0 to data_word_count_c-1
        loop
          if write_en_i(i) = '1' then
            r_mem(addr)((i+1) * word_size_c - 1 downto i * word_size_c) := write_data_i((i+1) * word_size_c - 1 downto i * word_size_c);
          end if;

        end loop;
        read_data_o <= r_mem(addr);
      end if;
    end if;
  end process;

end inferred;
