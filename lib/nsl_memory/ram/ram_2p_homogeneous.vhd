library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_2p_homogeneous is
  generic(
    addr_size_c  : integer := 10;
    word_size_c  : integer := 8;
    data_word_count_c : integer := 4;
    registered_output_c : boolean := false;
    b_can_write_c : boolean := true
    );
  port(
    a_clock_i    : in  std_ulogic;
    a_enable_i   : in  std_ulogic                                                      := '1';
    a_write_en_i : in  std_ulogic_vector(data_word_count_c - 1 downto 0)               := (others => '0');
    a_address_i  : in  unsigned(addr_size_c - 1 downto 0);
    a_data_i     : in  std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0) := (others => '-');
    a_data_o     : out std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0);
    b_clock_i    : in  std_ulogic;
    b_enable_i   : in  std_ulogic                                                      := '1';
    b_write_en_i : in  std_ulogic_vector(data_word_count_c - 1 downto 0)               := (others => '0');
    b_address_i  : in  unsigned(addr_size_c - 1 downto 0);
    b_data_i     : in  std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0) := (others => '-');
    b_data_o     : out std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0)
    );
end ram_2p_homogeneous;

architecture byte_wr_ram_rf of ram_2p_homogeneous is

  constant word_count : integer := 2 ** addr_size_c;
  subtype word_t is std_ulogic_vector(data_word_count_c * word_size_c - 1 downto 0);
  signal a_out_reg, b_out_reg: word_t;
  type ram_type is array (0 to word_count - 1) of word_t;
  shared variable dpram_reg : ram_type;

begin

  a_port: process(a_clock_i)
  begin
    if rising_edge(a_clock_i) then
      if a_enable_i = '1' then
        if registered_output_c then
          a_data_o <= a_out_reg;
          a_out_reg <= dpram_reg(to_integer(to_01(a_address_i, '0')));
        else
          a_data_o <= dpram_reg(to_integer(to_01(a_address_i, '0')));
        end if;

        for i in 0 to data_word_count_c - 1
        loop
          if a_write_en_i(i) = '1' then
            dpram_reg(to_integer(to_01(a_address_i, '0')))((i + 1) * word_size_c - 1 downto i * word_size_c)
              := a_data_i((i + 1) * word_size_c - 1 downto i * word_size_c);
          end if;
        end loop;
      end if;
    end if;
  end process;

  b_port: process(b_clock_i)
  begin
    if rising_edge(b_clock_i)
    then
      if b_enable_i = '1' then
        if registered_output_c then
          b_data_o <= b_out_reg;
          b_out_reg <= dpram_reg(to_integer(to_01(b_address_i, '0')));
        else
          b_data_o <= dpram_reg(to_integer(to_01(b_address_i, '0')));
        end if;

        if b_can_write_c then
          for i in 0 to data_word_count_c - 1
          loop
            if b_write_en_i(i) = '1' then
              dpram_reg(to_integer(to_01(b_address_i, '0')))((i + 1) * word_size_c - 1 downto i * word_size_c)
                := b_data_i((i + 1) * word_size_c - 1 downto i * word_size_c);
            end if;
          end loop;
        end if;
      end if;
    end if;
  end process;
end byte_wr_ram_rf;
