library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sync_reg is
  generic(
    cycle_count : natural range 2 to 40 := 2;
    data_width : integer;
    cross_region : boolean := true;
    async_sampler : boolean := false
    );
  port(
    p_clk    : in std_ulogic;
    p_in     : in std_ulogic_vector(data_width-1 downto 0);
    p_out    : out std_ulogic_vector(data_width-1 downto 0)
    );
end sync_reg;

architecture rtl of sync_reg is
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type word_vector_t is array (natural range <>) of word_t;
  attribute keep : string;
  attribute async_reg : string;
  attribute syn_keep : boolean;
  attribute nomerge : string;
begin

  cross: if cross_region generate
    signal cross_region_reg_d : word_t;
    signal metastable_reg_d : word_vector_t (0 to cycle_count-2);
    attribute keep of cross_region_reg_d, metastable_reg_d : signal is "TRUE";
    attribute async_reg of cross_region_reg_d, metastable_reg_d : signal is "TRUE";
    attribute syn_keep of cross_region_reg_d, metastable_reg_d : signal is true;
    attribute nomerge of cross_region_reg_d, metastable_reg_d : signal is "";
  begin
    clock: process (p_clk)
    begin
      if rising_edge(p_clk) then
        metastable_reg_d
          <= metastable_reg_d(1 to metastable_reg_d'high)
             & cross_region_reg_d;
        cross_region_reg_d <= p_in;
      end if;
    end process clock;

    p_out <= metastable_reg_d(metastable_reg_d'left);
  end generate cross;

  async: if async_sampler and not cross_region generate
    signal tig_reg_d : word_t;
    signal metastable_reg_d : word_vector_t (0 to cycle_count-2);
    attribute keep of tig_reg_d, metastable_reg_d : signal is "TRUE";
    attribute async_reg of tig_reg_d, metastable_reg_d : signal is "TRUE";
    attribute nomerge of tig_reg_d, metastable_reg_d : signal is "";
  begin
    clock: process (p_clk)
    begin
      if rising_edge(p_clk) then
        metastable_reg_d
          <= metastable_reg_d(1 to metastable_reg_d'high) & tig_reg_d;
        tig_reg_d <= p_in;
      end if;
    end process clock;

    p_out <= metastable_reg_d(metastable_reg_d'left);
  end generate async;

  nocross: if not cross_region and not async_sampler generate
    signal r_regs : word_vector_t (0 to cycle_count-1);
  begin
    clock: process (p_clk)
    begin
      if rising_edge(p_clk) then
        r_regs(r_regs'left to r_regs'right-1) <= r_regs(r_regs'left+1 to r_regs'right);
        r_regs(r_regs'right) <= p_in;
      end if;
    end process clock;

    p_out <= r_regs(r_regs'left);
  end generate nocross;
  
end rtl;
