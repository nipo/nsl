library ieee;
use ieee.std_logic_1164.all;

entity async_edge is
  generic(
    cycle_count_c : natural range 2 to 8 := 2;
    target_value_c : std_ulogic := '1';
    async_reset_c : boolean := true
    );
  port(
    clock_i : in  std_ulogic;
    data_i  : in  std_ulogic;
    data_o  : out std_ulogic
    );

end async_edge;

architecture rtl of async_edge is

  attribute shreg_extract : string;
  attribute keep : string;
  attribute syn_preserve : boolean;
begin

  async_pre: if async_reset_c and target_value_c = '0'
  generate
    signal tig_reg_pre : std_ulogic_vector(0 to cycle_count_c-1);
    attribute keep of tig_reg_pre : signal is "TRUE";
    attribute shreg_extract of tig_reg_pre : signal is "false";
    attribute syn_preserve of tig_reg_pre : signal is true;
  begin
    forward: process (clock_i, data_i)
    begin
      if data_i = '1' then
        tig_reg_pre <= (others => '1');
      elsif rising_edge(clock_i) then
        tig_reg_pre <= tig_reg_pre(tig_reg_pre'left + 1 to tig_reg_pre'right) & "0";
      end if;
    end process;

    data_o <= tig_reg_pre(tig_reg_pre'left);
  end generate;

  async_clr: if async_reset_c and target_value_c = '1'
  generate
    signal tig_reg_clr : std_ulogic_vector(0 to cycle_count_c-1);
    attribute keep of tig_reg_clr : signal is "TRUE";
    attribute shreg_extract of tig_reg_clr : signal is "false";
    attribute syn_preserve of tig_reg_clr : signal is true;
  begin
    forward: process (clock_i, data_i)
    begin
      if data_i = '0' then
        tig_reg_clr <= (others => '0');
      elsif rising_edge(clock_i) then
        tig_reg_clr <= tig_reg_clr(tig_reg_clr'left + 1 to tig_reg_clr'right) & "1";
      end if;
    end process;

    data_o <= tig_reg_clr(tig_reg_clr'left);
  end generate;

  sync: if not async_reset_c
  generate
    signal tig_reg_d : std_ulogic_vector(0 to cycle_count_c-1);
    attribute keep of tig_reg_d : signal is "TRUE";
    attribute shreg_extract of tig_reg_d : signal is "false";
    attribute syn_preserve of tig_reg_d : signal is true;
  begin
    forward: process (clock_i)
      constant opposed_value_c : std_ulogic := not target_value_c;
    begin
      if rising_edge(clock_i) then
        if data_i /= target_value_c then
          tig_reg_d <= (others => opposed_value_c);
        else
          tig_reg_d <= tig_reg_d(tig_reg_d'left + 1 to tig_reg_d'right) & target_value_c;
        end if;
      end if;
    end process;
    data_o <= tig_reg_d(tig_reg_d'left);
  end generate;
  
end rtl;
