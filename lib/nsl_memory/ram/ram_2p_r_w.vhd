library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_memory;

entity ram_2p_r_w is
  generic (
    addr_size_c : natural;
    data_size_c : natural;
    clock_count_c : natural range 1 to 2 := 1;
    registered_output_c : boolean := false
    );
  port (
    clock_i    : in  std_ulogic_vector(0 to clock_count_c-1);

    write_address_i  : in unsigned(addr_size_c-1 downto 0);
    write_en_i    : in  std_ulogic := '0';
    write_data_i  : in  std_ulogic_vector (data_size_c-1 downto 0) := (others => '-');

    read_address_i  : in unsigned(addr_size_c-1 downto 0);
    read_en_i  : in  std_ulogic := '0';
    read_data_o : out std_ulogic_vector (data_size_c-1 downto 0)
    );
end ram_2p_r_w;

architecture hier of ram_2p_r_w is

begin

  impl: nsl_memory.ram.ram_2p_homogeneous
    generic map(
      addr_size_c => addr_size_c,
      word_size_c => data_size_c,
      data_word_count_c => 1,
      registered_output_c => registered_output_c,
      b_can_write_c => false
      )
    port map(
      a_clock_i => clock_i(0),
      a_enable_i => write_en_i,
      a_write_en_i(0) => write_en_i,
      a_address_i => write_address_i,
      a_data_i => write_data_i,
      a_data_o => open,

      b_clock_i => clock_i(clock_count_c-1),
      b_enable_i => read_en_i,
      b_write_en_i(0) => '0',
      b_address_i => read_address_i,
      b_data_i => (others => '-'),
      b_data_o => read_data_o
      );

end hier;
