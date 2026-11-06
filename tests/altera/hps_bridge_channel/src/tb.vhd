library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_altera, nsl_simulation;

entity tb is
end tb;

architecture arch of tb is

  constant beat_count_c : natural := 2000;
  constant width_c : natural := 16;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

begin

  sides: for side in 0 to 1
  generate
    signal in_valid_s, in_ready_s, out_valid_s, out_ready_s : std_ulogic;
    signal in_data_s, out_data_s : std_ulogic_vector(width_c-1 downto 0);
  begin

    source: process(clock_s, reset_n_s)
      variable seed1, seed2 : positive := 1 + side;
      variable rnd : real;
      variable sent : natural := 0;
    begin
      if reset_n_s = '0' then
        in_valid_s <= '0';
        in_data_s <= (others => '0');
        sent := 0;
      elsif rising_edge(clock_s) then
        if in_valid_s = '1' and in_ready_s = '1' then
          sent := sent + 1;
          in_valid_s <= '0';
        end if;

        if (in_valid_s = '0' or in_ready_s = '1') and sent < beat_count_c then
          uniform(seed1, seed2, rnd);
          if rnd > 0.3 then
            in_valid_s <= '1';
            in_data_s <= std_ulogic_vector(to_unsigned(sent, width_c));
          end if;
        end if;
      end if;
    end process;

    sink: process(clock_s, reset_n_s)
      variable seed1, seed2 : positive := 7 + side;
      variable rnd : real;
      variable received : natural := 0;
    begin
      if reset_n_s = '0' then
        out_ready_s <= '0';
        done_s(side) <= '0';
        received := 0;
      elsif rising_edge(clock_s) then
        if out_valid_s = '1' and out_ready_s = '1' then
          assert unsigned(out_data_s) = received
            report "Got " & integer'image(to_integer(unsigned(out_data_s)))
            & ", expected " & integer'image(received)
            severity failure;
          received := received + 1;
          if received = beat_count_c then
            done_s(side) <= '1';
          end if;
        end if;

        uniform(seed1, seed2, rnd);
        if rnd > 0.5 then
          out_ready_s <= '1';
        else
          out_ready_s <= '0';
        end if;
      end if;
    end process;

    dut: nsl_altera.hps.hps_bridge_channel
      generic map(
        width_c => width_c,
        to_periphery_c => side = 0,
        fifo_c => true
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        in_valid_i => in_valid_s,
        in_data_i => in_data_s,
        in_ready_o => in_ready_s,
        out_valid_o => out_valid_s,
        out_data_o => out_data_s,
        out_ready_i => out_ready_s
        );
  end generate;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 32 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
