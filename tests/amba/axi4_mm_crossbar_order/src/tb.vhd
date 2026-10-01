library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.text.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_mm.all;
use nsl_amba.address.all;

-- Response order across slaves of different latencies, same ID: a
-- master issues a read (write) to a slow slave, then at once another
-- with the same ID to an unmapped address, answered by the crossbar's
-- own error slave in a couple of cycles.  The responses must come back
-- in issue order: OKAY first, DECERR second.
entity tb is
end tb;

architecture arch of tb is

  constant master_config_c : config_t := config(
    address_width => 32, data_bus_width => 32, id_width => 4,
    max_length => 16, burst => true);
  constant slave_config_c : config_t := config(
    address_width => 32, data_bus_width => 32, id_width => 4,
    max_length => 16, burst => true);

  constant routing_table_c : nsl_amba.address.address_vector
    := routing_table(32, "x0-------/4");

  constant latency_c : natural := 20;
  constant id_c : std_ulogic_vector(3 downto 0) := "0011";
  constant rounds_c : natural := 4;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);
  signal master_s : bus_t;
  signal slave_s : bus_vector(0 to 0);

begin

  issuer: process is
    procedure address_beat(signal a : out nsl_amba.axi4_mm.address_t; addr : unsigned;
                           signal ready : in handshake_t) is
    begin
      a <= address(master_config_c, id => id_c, addr => addr,
                   len_m1 => "0000");
      loop
        wait until rising_edge(clock_s);
        exit when is_ready(master_config_c, ready);
      end loop;
      a <= address_defaults(master_config_c);
    end procedure;
  begin
    master_s.m.ar <= address_defaults(master_config_c);
    master_s.m.aw <= address_defaults(master_config_c);
    master_s.m.w <= write_data_defaults(master_config_c);
    wait until reset_n_s = '1';
    wait until falling_edge(clock_s);

    for round in 1 to rounds_c loop
      -- Reads: slow slave, then the error slave, back to back.
      address_beat(master_s.m.ar, x"00000010", master_s.s.ar);
      address_beat(master_s.m.ar, x"20000000", master_s.s.ar);

      -- Writes: the same, data right behind each address.
      master_s.m.w <= write_data(master_config_c, value => x"12345678",
                                 last => true);
      address_beat(master_s.m.aw, x"00000020", master_s.s.aw);
      loop
        exit when is_ready(master_config_c, master_s.s.w);
        wait until rising_edge(clock_s);
      end loop;
      wait until rising_edge(clock_s);
      master_s.m.w <= write_data(master_config_c, value => x"9abcdef0",
                                 last => true);
      address_beat(master_s.m.aw, x"20000020", master_s.s.aw);
      loop
        exit when is_ready(master_config_c, master_s.s.w);
        wait until rising_edge(clock_s);
      end loop;
      wait until rising_edge(clock_s);
      master_s.m.w <= write_data_defaults(master_config_c);
    end loop;

    done_s(0) <= '1';
    wait;
  end process;

  collector: process is
    variable reads, writes : natural := 0;
    variable expected : resp_enum_t;
  begin
    done_s(1) <= '0';
    master_s.m.r <= accept(master_config_c, true);
    master_s.m.b <= accept(master_config_c, true);
    while reads < 2 * rounds_c or writes < 2 * rounds_c loop
      wait until rising_edge(clock_s);
      if is_valid(master_config_c, master_s.s.r) then
        if reads mod 2 = 0 then
          expected := RESP_OKAY;
        else
          expected := RESP_DECERR;
        end if;
        assert resp(master_config_c, master_s.s.r) = expected
          and id(master_config_c, master_s.s.r) = id_c
          report "read response " & integer'image(reads) & ": "
          & to_string(resp(master_config_c, master_s.s.r))
          & ", expected " & to_string(expected)
          severity failure;
        reads := reads + 1;
      end if;
      if is_valid(master_config_c, master_s.s.b) then
        if writes mod 2 = 0 then
          expected := RESP_OKAY;
        else
          expected := RESP_DECERR;
        end if;
        assert resp(master_config_c, master_s.s.b) = expected
          and id(master_config_c, master_s.s.b) = id_c
          report "write response " & integer'image(writes) & ": "
          & to_string(resp(master_config_c, master_s.s.b))
          & ", expected " & to_string(expected)
          severity failure;
        writes := writes + 1;
      end if;
    end loop;
    log_info("responses in order");
    done_s(1) <= '1';
    wait;
  end process;

  -- A slave answering each read and write latency_c cycles after its
  -- address, one at a time.
  slow: process is
    variable rid, bid : std_ulogic_vector(3 downto 0);
  begin
    slave_s(0).s.ar <= accept(slave_config_c, false);
    slave_s(0).s.aw <= accept(slave_config_c, false);
    slave_s(0).s.w <= accept(slave_config_c, false);
    slave_s(0).s.r <= read_data_defaults(slave_config_c);
    slave_s(0).s.b <= write_response_defaults(slave_config_c);
    wait until reset_n_s = '1';
    loop
      wait until falling_edge(clock_s);
      slave_s(0).s.ar <= accept(slave_config_c, true);
      slave_s(0).s.aw <= accept(slave_config_c, true);
      wait until rising_edge(clock_s);
      if is_valid(slave_config_c, slave_s(0).m.ar) then
        rid := id(slave_config_c, slave_s(0).m.ar);
        wait until falling_edge(clock_s);
        slave_s(0).s.ar <= accept(slave_config_c, false);
        slave_s(0).s.aw <= accept(slave_config_c, false);
        for i in 1 to latency_c loop
          wait until falling_edge(clock_s);
        end loop;
        slave_s(0).s.r <= read_data(slave_config_c, id => rid,
                                    value => x"a5a5a5a5", last => true);
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(slave_config_c, slave_s(0).m.r);
        end loop;
        wait until falling_edge(clock_s);
        slave_s(0).s.r <= read_data_defaults(slave_config_c);
      elsif is_valid(slave_config_c, slave_s(0).m.aw) then
        bid := id(slave_config_c, slave_s(0).m.aw);
        wait until falling_edge(clock_s);
        slave_s(0).s.ar <= accept(slave_config_c, false);
        slave_s(0).s.aw <= accept(slave_config_c, false);
        slave_s(0).s.w <= accept(slave_config_c, true);
        loop
          wait until rising_edge(clock_s);
          exit when is_valid(slave_config_c, slave_s(0).m.w);
        end loop;
        wait until falling_edge(clock_s);
        slave_s(0).s.w <= accept(slave_config_c, false);
        for i in 1 to latency_c loop
          wait until falling_edge(clock_s);
        end loop;
        slave_s(0).s.b <= write_response(slave_config_c, id => bid);
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(slave_config_c, slave_s(0).m.b);
        end loop;
        wait until falling_edge(clock_s);
        slave_s(0).s.b <= write_response_defaults(slave_config_c);
      end if;
    end loop;
  end process;

  dut: nsl_amba.mm_routing.axi4_mm_crossbar
    generic map(
      master_config_c => master_config_c,
      slave_config_c => slave_config_c,
      master_count_c => 1,
      routing_table_c => routing_table_c,
      default_slave_c => -1
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      slave_i(0) => master_s.m,
      slave_o(0) => master_s.s,
      master_o(0) => slave_s(0).m,
      master_i(0) => slave_s(0).s
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 50 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
