library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;

entity tb is
end tb;

architecture arch of tb is

  constant data_width : integer := 2;
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  
  signal clk   : std_ulogic;
  signal io_a_d, io_b_d, io_clk   : std_ulogic;
  signal a_clk, b_clk : nsl_io.diff.diff_pair;

  signal a_d, b_d : word_t := (others => '0');

  constant c_pattern0 : std_ulogic_vector(8 downto 0) := "000101000";
  constant c_pattern1 : std_ulogic_vector(8 downto 0) := "010100010";

  signal pat : word_t := (others => '0');
  signal patm1 : word_t := (others => '0');
  signal patm2 : word_t := (others => '0');
  
begin

  o: nsl_io.ddr.ddr_output
    port map(
      clock_i => a_clk,
      d_i => a_d,
      dd_o => io_a_d
      );

  i: nsl_io.ddr.ddr_input
    port map(
      clock_i => b_clk,
      dd_i => io_b_d,
      d_o => b_d
      );

  cko: nsl_io.clock.clock_output_diff_to_se
    port map(
      clock_i => a_clk,
      port_o => io_clk
      );

  a_clk.p <= clk;
  a_clk.n <= not clk;

  b_clk.p <= io_clk after 300 ps;
  b_clk.n <= not b_clk.p;

  io_b_d <= io_a_d after 350 ps;

  shift: process(clk)
  begin
    if rising_edge(clk) then
      patm2 <= patm1 after 300 ps;
      patm1 <= pat after 300 ps;
    end if;
  end process;
  
  run: process
  begin
    for repeat in 0 to 15
    loop
      for i in 0 to 4
      loop
        wait for 1 ns;
        clk <= '0';
        wait for 1 ns;
        clk <= '1';
      end loop;
    
      for i in c_pattern1'range
      loop
        wait for 1 ns;
        pat <= c_pattern1(i) & c_pattern0(i);
        clk <= '0';
        wait for 0.5 ns;
        a_d <= pat;
        wait for 0.5 ns;
        clk <= '1';
      end loop;

      for i in 0 to 4
      loop
        wait for 1 ns;
        clk <= '0';
        wait for 1 ns;
        clk <= '1';
      end loop;
    
    end loop;

    assert false report "Simulation done" severity note;
    wait;
  end process;

  check: process
  begin
    wait until rising_edge(clk);
    assert patm2 = b_d report "Bad encoding or decoding" severity warning;
  end process;
  
end;
