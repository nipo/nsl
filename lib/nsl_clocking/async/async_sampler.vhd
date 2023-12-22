library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity async_sampler is
  generic(
    cycle_count_c : natural := 2;
    data_width_c : integer
    );
  port(
    clock_i    : in std_ulogic;
    data_i     : in std_ulogic_vector(data_width_c-1 downto 0);
    data_o    : out std_ulogic_vector(data_width_c-1 downto 0)
    );
end async_sampler;

architecture rtl of async_sampler is
  
  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  attribute keep : string;
  attribute async_reg : string;
  attribute syn_keep : boolean;
  attribute nomerge : string;

begin

  has_sampler: if cycle_count_c >= 2
  generate
    signal tig_reg_d : word_t;
    signal metastable_reg_d : word_vector_t (0 to cycle_count_c-2);
    attribute keep of tig_reg_d, metastable_reg_d : signal is "TRUE";
    attribute syn_keep of tig_reg_d, metastable_reg_d : signal is true;
    attribute async_reg of tig_reg_d, metastable_reg_d : signal is "TRUE";
    attribute nomerge of tig_reg_d, metastable_reg_d : signal is "TRUE";
  begin
    clock: process (clock_i)
    begin
      if rising_edge(clock_i) then
        metastable_reg_d
          <= metastable_reg_d(1 to metastable_reg_d'high) & tig_reg_d;
        tig_reg_d <= data_i;
      end if;
    end process clock;

    data_o <= metastable_reg_d(metastable_reg_d'left);
  end generate;

  has_tig_only: if cycle_count_c = 1
  generate
    signal tig_reg_d : word_t;
    attribute keep of tig_reg_d : signal is "TRUE";
    attribute syn_keep of tig_reg_d : signal is true;
    attribute async_reg of tig_reg_d : signal is "TRUE";
    attribute nomerge of tig_reg_d : signal is "TRUE";
  begin
    clock: process (clock_i)
    begin
      if rising_edge(clock_i) then
        tig_reg_d <= data_i;
      end if;
    end process clock;

    data_o <= tig_reg_d;
  end generate;

  wire_only: if cycle_count_c = 0
  generate
    data_o <= data_i;
  end generate;
  
end rtl;
