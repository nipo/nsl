library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library hwdep;
library signalling;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 2;
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  
  signal a_clk   : std_ulogic;
  signal io_a_d   : std_ulogic;
  signal io_b_d   : std_ulogic;
  signal io_a_clk : std_ulogic;
  signal io_b_clk : std_ulogic;
  signal b_clk90 : signalling.diff.diff_pair;
  signal b_clk   : std_ulogic;

  signal a_d : word_t := (others => '0');
  signal b_d : word_t := (others => '0');

  constant c_pattern0 : std_ulogic_vector(8 downto 0) := "000101000";
  constant c_pattern1 : std_ulogic_vector(8 downto 0) := "010100010";
  
begin

  o: hwdep.io.io_ddr_output
    port map(
      p_clk => a_clk,
      p_d => a_d,
      p_dd => io_a_d
      );

  i: hwdep.io.io_ddr_input
    port map(
      p_clk90 => b_clk90,
      p_dd => io_b_d,
      p_d => b_d
      );

  cko: hwdep.io.io_ddr_output
    port map(
      p_clk => a_clk,
      p_d => "01",
      p_dd => io_a_clk
      );

  io_b_d <= io_a_d after 300 ps;
  io_b_clk <= io_a_clk after 300 ps;

  b_clk <= io_b_clk after 10 ps;
  b_clk90.p <= io_b_clk after 0.25 ns;
  b_clk90.n <= not io_b_clk after 0.25 ns;

  clk: process
  begin
    for repeat in 0 to 15
    loop
      for i in 0 to 4
      loop
        wait for 1 ns;
        a_clk <= '0';
        wait for 1 ns;
        a_clk <= '1';
      end loop;
    
      for i in c_pattern1'range
      loop
        wait for 1 ns;
        a_clk <= '0';
        wait for 0.5 ns;
        a_d <= c_pattern1(i) & c_pattern0(i);
        wait for 0.5 ns;
        a_clk <= '1';
--        assert s_bin = s_bin2 report "Bad encoding or decoding" severity failure;
      end loop;

      for i in 0 to 4
      loop
        wait for 1 ns;
        a_clk <= '0';
        wait for 1 ns;
        a_clk <= '1';
      end loop;
    
    end loop;

    wait;
  end process;
  
end;
