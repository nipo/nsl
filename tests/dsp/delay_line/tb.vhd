library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end entity;

library nsl_dsp, nsl_simulation;

architecture arch of tb is

  constant data_width_c : positive := 8;
  constant delay_width_c : positive := 2;

  subtype word_t is std_ulogic_vector(data_width_c-1 downto 0);

  signal clock_s : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);
  signal ready_s : std_ulogic;
  signal valid_s : std_ulogic;
  signal delay_s : unsigned(delay_width_c-1 downto 0);
  signal data_i_s : word_t;
  signal data_o_s : word_t;

  procedure check_cycle(
    signal clock : in std_ulogic;
    signal valid : out std_ulogic;
    signal data_i : out word_t;
    signal data_o : in word_t;
    constant value : in integer;
    constant expected : in integer;
    constant what : in string) is
  begin
    wait until falling_edge(clock);
    valid <= '1';
    data_i <= std_ulogic_vector(to_unsigned(value, data_width_c));

    wait until rising_edge(clock);
    wait for 1 ns;
    assert data_o = std_ulogic_vector(to_unsigned(expected, data_width_c))
      report what
      severity failure;
  end procedure;

  procedure check_idle(
    signal clock : in std_ulogic;
    signal valid : out std_ulogic;
    signal data_i : out word_t;
    signal data_o : in word_t;
    constant expected : in integer;
    constant what : in string) is
  begin
    wait until falling_edge(clock);
    valid <= '0';
    data_i <= (others => '0');

    wait until rising_edge(clock);
    wait for 1 ns;
    assert data_o = std_ulogic_vector(to_unsigned(expected, data_width_c))
      report what
      severity failure;
  end procedure;

begin

  driver : nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => 1)
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 12 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s);

  dut : nsl_dsp.delay_line.delay_line_variable
    generic map(
      data_width_c => data_width_c,
      delay_width_c => delay_width_c)
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      ready_o => ready_s,
      valid_i => valid_s,
      delay_i => delay_s,
      data_i => data_i_s,
      data_o => data_o_s);

  main : process
  begin
    valid_s <= '0';
    delay_s <= to_unsigned(2, delay_width_c);
    data_i_s <= (others => '0');
    done_s <= "0";

    wait until reset_n_s = '0';
    wait for 1 ns;
    assert ready_s = '0' and data_o_s = (data_o_s'range => '0')
      report "Reset did not zero the interface"
      severity failure;

    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    wait for 1 ns;
    assert ready_s = '1' and data_o_s = (data_o_s'range => '0')
      report "Interface was not zeroed while delay line initialized"
      severity failure;

    check_cycle(clock_s, valid_s, data_i_s, data_o_s, 1, 0,
                "First fixed-delay sample was not suppressed");
    check_cycle(clock_s, valid_s, data_i_s, data_o_s, 2, 0,
                "Second fixed-delay sample was not suppressed");
    check_cycle(clock_s, valid_s, data_i_s, data_o_s, 3, 1,
                "Fixed delay did not produce the first sample");
    check_cycle(clock_s, valid_s, data_i_s, data_o_s, 4, 2,
                "Fixed delay did not produce the second sample");

    check_idle(clock_s, valid_s, data_i_s, data_o_s, 2,
               "Invalid input changed the delayed output");
    check_cycle(clock_s, valid_s, data_i_s, data_o_s, 5, 3,
                "Invalid input advanced the delay line");

    wait until falling_edge(clock_s);
    delay_s <= to_unsigned(1, delay_width_c);
    valid_s <= '0';
    data_i_s <= (others => '0');
    wait for 1 ns;
    assert data_o_s = (data_o_s'range => '0')
      report "Delay change exposed stale data before refill"
      severity failure;

    wait until rising_edge(clock_s);
    wait for 1 ns;
    assert data_o_s = (data_o_s'range => '0')
      report "Delay change exposed stale data during reinitialization"
      severity failure;

    check_cycle(clock_s, valid_s, data_i_s, data_o_s, 100, 0,
                "First sample after delay change was not suppressed");
    check_cycle(clock_s, valid_s, data_i_s, data_o_s, 101, 100,
                "Changed delay did not produce fresh data");

    valid_s <= '0';
    report "Terminating with error level: 0" severity note;
    done_s <= "1";
    wait;
  end process;

end architecture;
