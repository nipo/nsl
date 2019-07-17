library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ram_2p_homogeneous is
  generic(
    addr_size  : integer := 10;
    byte_size  : integer := 8;
    data_bytes : integer := 4;
    registered_output : boolean := false
    );
  port(
    p_a_clk  : in  std_ulogic;
    p_a_en   : in  std_ulogic := '1';
    p_a_wen   : in  std_ulogic_vector(data_bytes - 1 downto 0) := (others => '0');
    p_a_addr : in  std_ulogic_vector(addr_size - 1 downto 0);
    p_a_wdata   : in  std_ulogic_vector(data_bytes * byte_size - 1 downto 0) := (others => '-');
    p_a_rdata   : out std_ulogic_vector(data_bytes * byte_size - 1 downto 0);
    p_b_clk  : in  std_ulogic;
    p_b_en   : in  std_ulogic := '1';
    p_b_wen   : in  std_ulogic_vector(data_bytes - 1 downto 0) := (others => '0');
    p_b_addr : in  std_ulogic_vector(addr_size - 1 downto 0);
    p_b_wdata   : in  std_ulogic_vector(data_bytes * byte_size - 1 downto 0) := (others => '-');
    p_b_rdata   : out std_ulogic_vector(data_bytes * byte_size - 1 downto 0)
    );
end ram_2p_homogeneous;

architecture byte_wr_ram_rf of ram_2p_homogeneous is

  constant word_count : integer := 2 ** addr_size;
  subtype word_t is std_ulogic_vector(data_bytes * byte_size - 1 downto 0);
  signal a_out_reg, b_out_reg: word_t;
  type ram_type is array (0 to word_count - 1) of word_t;
  shared variable r_mem : ram_type := (others => (others => '-'));

begin

  a_port: process(p_a_clk)
  begin
    if rising_edge(p_a_clk) then
      if p_a_en = '1' then
        if registered_output then
          p_a_rdata <= a_out_reg;
          a_out_reg <= r_mem(to_integer(to_01(unsigned(p_a_addr), '0')));
        else
          p_a_rdata <= r_mem(to_integer(to_01(unsigned(p_a_addr), '0')));
        end if;

        for i in 0 to data_bytes - 1
        loop
          if p_a_wen(i) = '1' then
            r_mem(to_integer(to_01(unsigned(p_a_addr), '0')))((i + 1) * byte_size - 1 downto i * byte_size)
              := p_a_wdata((i + 1) * byte_size - 1 downto i * byte_size);
          end if;
        end loop;
      end if;
    end if;
  end process;

  b_port: process(p_b_clk)
  begin
    if rising_edge(p_b_clk)
    then
      if p_b_en = '1' then
        if registered_output then
          p_b_rdata <= b_out_reg;
          b_out_reg <= r_mem(to_integer(to_01(unsigned(p_b_addr), '0')));
        else
          p_b_rdata <= r_mem(to_integer(to_01(unsigned(p_b_addr), '0')));
        end if;

        for i in 0 to data_bytes - 1
        loop
          if p_b_wen(i) = '1' then
            r_mem(to_integer(to_01(unsigned(p_b_addr), '0')))((i + 1) * byte_size - 1 downto i * byte_size)
              := p_b_wdata((i + 1) * byte_size - 1 downto i * byte_size);
          end if;
        end loop;
      end if;
    end if;
  end process;
end byte_wr_ram_rf;
