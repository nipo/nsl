library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_amba.mm_traffic.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- Checks the memory walker against a plain RAM, and separately checks
-- what it puts on the bus.
--
-- The walk on its own cannot tell whether the payload belongs to the
-- address it was written at.  It writes a region and reads it back
-- through the same generator, so a payload shifted by a constant
-- number of beats is written and expected in the same wrong place and
-- the walk passes.  That is not a hypothetical: pipelining the hash
-- moves the payload against the address by exactly such a constant,
-- and the memory benches see nothing.
--
-- So the write channel is watched here, and every beat is held against
-- the payload its own address stands for, computed straight from the
-- function.  That pins the association the walk cannot.
entity tb is
end entity;

architecture beh of tb is

  constant config_c: config_t := config(address_width => 32,
                                        data_bus_width => 32,
                                        max_length => 256,
                                        size => true,
                                        burst => true);

  constant seed_c: natural := 31337;
  constant burst_length_c: natural := 4;
  constant region_byte_l2_c: natural := 10;
  constant beat_byte_c: natural := 2 ** config_c.data_bus_width_l2;

  constant seed_u_c: unsigned(31 downto 0) := to_unsigned(seed_c, 32);

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal axi_s: bus_t;
  signal start_s: std_ulogic := '0';
  signal done_s: std_ulogic;
  signal error_count_s: unsigned(31 downto 0);
  signal first_error_s: unsigned(config_c.address_width - 1 downto 0);

  signal snoop_beat_s: natural := 0;
  signal snoop_bad_s: natural := 0;

begin

  clock_s <= (not clock_s) after 5 ns when not stopped_s else '0';
  reset_n_s <= '1' after 30 ns;

  tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => seed_c,
      scramble_c => false
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      start_i => start_s,
      axi_o => axi_s.m,
      axi_i => axi_s.s,
      busy_o => open,
      done_o => done_s,
      error_count_o => error_count_s,
      first_error_address_o => first_error_s
      );

  memory: nsl_amba.ram.axi4_mm_ram
    generic map(
      config_c => config_c,
      byte_size_l2_c => region_byte_l2_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      axi_i => axi_s.m,
      axi_o => axi_s.s
      );

  -- Every write beat, against the payload its own address stands for.
  snoop: process is
    variable base: unsigned(config_c.address_width - 1 downto 0);
    variable beat: natural;
    variable seen, want: byte_string(0 to beat_byte_c - 1);
    variable beat_addr: unsigned(config_c.address_width - 1 downto 0);
    variable beats, bad: natural := 0;
  begin
    base := (others => '0');
    beat := 0;

    loop
      wait until rising_edge(clock_s);
      exit when stopped_s;

      if is_valid(config_c, axi_s.m.aw)
        and is_ready(config_c, axi_s.s.aw) then
        base := address(config_c, axi_s.m.aw);
        beat := 0;
      end if;

      if is_valid(config_c, axi_s.m.w)
        and is_ready(config_c, axi_s.s.w) then
        beat_addr := base + to_unsigned(beat * beat_byte_c,
                                      config_c.address_width);
        seen := bytes(config_c, axi_s.m.w)(0 to beat_byte_c - 1);
        want := pattern(seed_u_c, beat_addr, beat_byte_c);

        beats := beats + 1;
        if seen /= want then
          bad := bad + 1;
          if bad = 1 then
            report "write at " & to_string(to_integer(beat_addr))
              & " carried " & to_string(seen)
              & ", the payload of that address is " & to_string(want)
              severity error;
          end if;
        end if;

        beat := beat + 1;
        snoop_beat_s <= beats;
        snoop_bad_s <= bad;
      end if;
    end loop;

    wait;
  end process;

  watchdog: process is
  begin
    wait for 10 ms;
    assert stopped_s
      report "watchdog fired, the walker is stuck"
      severity failure;
    wait;
  end process;

  stim: process is
    variable errors: natural := 0;
  begin
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);
    start_s <= '1';

    wait until done_s = '1';
    wait until falling_edge(clock_s);

    errors := to_integer(error_count_s) + snoop_bad_s;

    assert to_integer(error_count_s) = 0
      report "the walk read back "
      & to_string(to_integer(error_count_s)) & " bad beats, first at "
      & to_string(to_integer(first_error_s))
      severity error;

    -- A walk that never wrote anything would report no errors too.
    assert snoop_beat_s = 2 ** (region_byte_l2_c - config_c.data_bus_width_l2)
      report "the walk wrote " & to_string(snoop_beat_s)
      & " beats, the region holds "
      & to_string(2 ** (region_byte_l2_c - config_c.data_bus_width_l2))
      severity error;

    if snoop_beat_s /= 2 ** (region_byte_l2_c - config_c.data_bus_width_l2) then
      errors := errors + 1;
    end if;

    report "walk done, " & to_string(snoop_beat_s) & " beats written, "
      & to_string(snoop_bad_s) & " carrying the wrong payload, "
      & to_string(to_integer(error_count_s)) & " read back wrong";

    stopped_s <= true;
    if errors = 0 then
      nsl_simulation.control.terminate(0);
    else
      nsl_simulation.control.terminate(1);
    end if;
    wait;
  end process;

end architecture;
