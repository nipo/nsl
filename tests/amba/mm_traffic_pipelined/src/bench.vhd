library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, work;
use nsl_amba.axi4_mm.all;
use nsl_amba.mm_traffic.all;
use nsl_data.text.all;

-- One walker against one slave model, started on reset release.  It
-- counts the cycles the walker spends writing and reading, and
-- reports the number of checks that failed: a walk expected clean
-- must read back no error, a walk with a corrupted beat must read back
-- exactly that one, and the slave must have seen every beat of the
-- region written with its own payload, without protocol error.
entity bench is
  generic(
    name_c: string;
    config_c: config_t;
    region_byte_l2_c: natural;
    burst_length_c: positive;
    seed_c: natural;
    scramble_c: boolean;
    outstanding_c: positive;
    address_depth_c: positive;
    read_latency_c: natural;
    backpressure_c: boolean;
    random_seed_c: positive;
    corrupt_address_c: integer := -1
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    done_o: out boolean;
    failures_o: out natural;
    write_cycles_o: out natural;
    read_cycles_o: out natural
    );
end entity;

architecture beh of bench is

  constant beat_count_c: natural := 2 ** (region_byte_l2_c - config_c.data_bus_width_l2);

  signal axi_s: bus_t;
  signal start_s: std_ulogic := '0';
  signal busy_s, writing_s, done_s: std_ulogic;
  signal error_count_s: unsigned(31 downto 0);
  signal first_error_s: unsigned(config_c.address_width - 1 downto 0);
  signal write_beats_s, write_bad_s, protocol_errors_s: natural;

begin

  tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => burst_length_c,
      seed_c => seed_c,
      scramble_c => scramble_c,
      outstanding_c => outstanding_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      start_i => start_s,
      axi_o => axi_s.m,
      axi_i => axi_s.s,
      busy_o => busy_s,
      writing_o => writing_s,
      done_o => done_s,
      error_count_o => error_count_s,
      first_error_address_o => first_error_s
      );

  memory: entity work.slave_model
    generic map(
      config_c => config_c,
      byte_size_l2_c => region_byte_l2_c,
      seed_c => seed_c,
      address_depth_c => address_depth_c,
      read_latency_c => read_latency_c,
      backpressure_c => backpressure_c,
      random_seed_c => random_seed_c,
      corrupt_address_c => corrupt_address_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      axi_i => axi_s.m,
      axi_o => axi_s.s,
      write_beats_o => write_beats_s,
      write_bad_o => write_bad_s,
      protocol_errors_o => protocol_errors_s
      );

  run: process is
    variable write_cycles, read_cycles, failures: natural := 0;
  begin
    done_o <= false;
    failures_o <= 0;
    write_cycles_o <= 0;
    read_cycles_o <= 0;

    wait until reset_n_i = '1';
    wait until falling_edge(clock_i);
    start_s <= '1';

    loop
      wait until rising_edge(clock_i);
      exit when done_s = '1';

      if busy_s = '1' and writing_s = '1' then
        write_cycles := write_cycles + 1;
      elsif busy_s = '1' then
        read_cycles := read_cycles + 1;
      elsif writing_s = '1' then
        failures := failures + 1;
        report name_c & ": writing without busy" severity error;
      end if;
    end loop;

    if corrupt_address_c < 0 then
      if error_count_s /= 0 then
        failures := failures + 1;
        report name_c & ": read back " & to_string(to_integer(error_count_s))
          & " bad beats, first at " & to_string(to_integer(first_error_s))
          severity error;
      end if;
    else
      if error_count_s /= 1
        or to_integer(first_error_s) /= corrupt_address_c then
        failures := failures + 1;
        report name_c & ": corrupted beat at "
          & to_string(corrupt_address_c) & " seen as "
          & to_string(to_integer(error_count_s)) & " errors, first at "
          & to_string(to_integer(first_error_s))
          severity error;
      end if;
    end if;

    if write_beats_s /= beat_count_c or write_bad_s /= 0 then
      failures := failures + 1;
      report name_c & ": slave got " & to_string(write_beats_s)
        & " write beats, " & to_string(write_bad_s)
        & " with the wrong payload, region has " & to_string(beat_count_c)
        severity error;
    end if;

    if protocol_errors_s /= 0 then
      failures := failures + 1;
      report name_c & ": " & to_string(protocol_errors_s)
        & " protocol errors" severity error;
    end if;

    report name_c & ": " & to_string(beat_count_c) & " beats, "
      & to_string(write_cycles) & " cycles writing, "
      & to_string(read_cycles) & " cycles reading, "
      & to_string(to_integer(error_count_s)) & " read errors, "
      & to_string(failures) & " failures";

    failures_o <= failures;
    write_cycles_o <= write_cycles;
    read_cycles_o <= read_cycles;
    done_o <= true;
    wait;
  end process;

end architecture;
