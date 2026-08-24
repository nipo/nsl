library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_clocking;

entity tb is
end tb;

architecture arch of tb is

  constant data_width_c : integer := 6;
  constant settle_cycle_count_c : integer := 2**data_width_c + 63;

  signal clock_s : std_ulogic_vector(0 to 1);
  signal reset_n_s : std_ulogic_vector(0 to 0);
  signal done_s : std_ulogic_vector(0 to 0);

  signal target_s, publish_s, data_s : unsigned(data_width_c-1 downto 0);
  signal backward_s : std_ulogic;

  -- Value publish_s had when target_s was last changed. Together with
  -- target_s and backward_s, this defines the arc data_s is allowed to
  -- take its values from.
  signal start_s : unsigned(data_width_c-1 downto 0);
  signal checking_s : boolean;

begin

  dut: nsl_clocking.interdomain.interdomain_publish_counter
    generic map(
      data_width_c => data_width_c
      )
    port map(
      reset_n_i => reset_n_s(0),
      clock_in_i => clock_s(0),
      clock_out_i => clock_s(1),
      target_i => target_s,
      backward_i => backward_s,
      publish_o => publish_s,
      data_o => data_s
      );

  -- Publish register may only step by one, in the requested direction,
  -- and only as long as it did not reach the target.
  source_monitor: process(clock_s(0)) is
    variable valid_v : boolean := false;
    variable publish_v, target_v, expected_v : unsigned(data_width_c-1 downto 0);
    variable backward_v : std_ulogic;
  begin
    if rising_edge(clock_s(0)) then
      if valid_v then
        if publish_v = target_v then
          expected_v := publish_v;
        elsif backward_v = '1' then
          expected_v := publish_v - 1;
        else
          expected_v := publish_v + 1;
        end if;

        nsl_simulation.assertions.assert_equal(
          "publish step",
          publish_s, expected_v,
          failure);
      end if;

      publish_v := publish_s;
      target_v := target_s;
      backward_v := backward_s;
      valid_v := reset_n_s(0) = '1';
    end if;
  end process;

  -- Destination-domain value may only take values on the arc from
  -- start to target, in the chasing direction.
  dest_monitor: process(clock_s(1)) is
    variable travelled_v, distance_v : integer;
  begin
    if rising_edge(clock_s(1)) then
      if checking_s then
        if backward_s = '1' then
          travelled_v := to_integer(start_s - data_s);
          distance_v := to_integer(start_s - target_s);
        else
          travelled_v := to_integer(data_s - start_s);
          distance_v := to_integer(target_s - start_s);
        end if;

        if travelled_v > distance_v then
          nsl_simulation.logging.log_fatal(
            "Published value went past target: "
            &integer'image(travelled_v)&" steps from start, "
            &"target is "&integer'image(distance_v)&" steps away");
        end if;
      end if;
    end if;
  end process;

  stim: process is
    procedure jump(value : natural; backward : boolean) is
    begin
      wait until falling_edge(clock_s(0));
      start_s <= publish_s;
      target_s <= to_unsigned(value, data_width_c);
      if backward then
        backward_s <= '1';
      else
        backward_s <= '0';
      end if;

      for i in 1 to settle_cycle_count_c
      loop
        wait until falling_edge(clock_s(0));
      end loop;

      nsl_simulation.assertions.assert_equal(
        "publish converged",
        publish_s, to_unsigned(value, data_width_c),
        failure);
      nsl_simulation.assertions.assert_equal(
        "resynchronized value converged",
        data_s, to_unsigned(value, data_width_c),
        failure);
    end procedure;
  begin
    done_s <= "0";
    checking_s <= false;
    backward_s <= '0';
    target_s <= (others => '0');
    start_s <= (others => '0');

    wait until reset_n_s(0) = '1';
    -- Let the crossing pipeline flush its uninitialized contents
    wait for 500 ns;
    checking_s <= true;

    jump(20, false);
    jump(60, false);
    -- Wraps through the counter top
    jump(5, false);
    -- No move at all
    jump(5, false);

    jump(50, true);
    -- Wraps through the counter bottom
    jump(10, true);
    jump(10, true);
    jump(0, true);

    done_s <= "1";
    wait;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 13 ns,
      reset_duration(0) => 25 ns,
      reset_n_o(0) => reset_n_s(0),
      clock_o => clock_s,
      done_i => done_s
      );

end;
