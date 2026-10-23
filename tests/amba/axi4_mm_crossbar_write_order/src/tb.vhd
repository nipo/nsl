library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_amba, nsl_data;
use nsl_simulation.logging.all;
use nsl_data.text.all;
use nsl_amba.axi4_mm.all;

-- Write data must reach a slave in the order its write addresses were
-- accepted.  Master 2 holds slave port W channel with a slow burst
-- while master 1, then master 0, get their write addresses accepted.
-- When master 2 burst ends, write data from both master 1 and 0 is
-- pending, master 1 must go first.
--
-- Slave model accepts addresses ahead of data and checks each data
-- beat carries its own beat address.
entity tb is
end tb;

architecture arch of tb is

  constant master_config_c : config_t := config(
    address_width => 32,
    data_bus_width => 32,
    id_width => 4,
    max_length => 16,
    burst => true
    );

  constant slave_config_c : config_t := config(
    address_width => 32,
    data_bus_width => 32,
    id_width => 6,
    max_length => 16,
    burst => true
    );

  constant master_count_c : positive := 3;

  constant routing_table_c : nsl_amba.address.address_vector := nsl_amba.address.routing_table(
    32,
    "x0-------/4"
    );

  type burst_t is
  record
    delay : natural;
    addr : natural;
    len_m1 : natural;
    gap : natural;
  end record;

  type burst_vector is array (natural range <>) of burst_t;

  -- One burst per master, first write data beat is offered right
  -- after address is accepted.
  constant scenario_c : burst_vector(0 to master_count_c-1) := (
    0 => (delay => 20, addr => 16#0000#, len_m1 => 3, gap => 0),
    1 => (delay => 10, addr => 16#1000#, len_m1 => 3, gap => 0),
    2 => (delay => 0, addr => 16#2000#, len_m1 => 15, gap => 3)
    );

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to master_count_c-1);

  signal master_bus : bus_vector(0 to master_count_c-1);
  signal slave_bus : bus_vector(0 to 0);

begin

  masters: for m in 0 to master_count_c-1
  generate
    aw_proc: process is
      constant b : burst_t := scenario_c(m);
    begin
      master_bus(m).m.aw <= address_defaults(master_config_c);
      wait until reset_n_s = '1';
      for i in 0 to b.delay
      loop
        wait until falling_edge(clock_s);
      end loop;

      master_bus(m).m.aw <= address(master_config_c,
                                    id => std_ulogic_vector(to_unsigned(m, master_config_c.id_width)),
                                    addr => to_unsigned(b.addr, master_config_c.address_width),
                                    len_m1 => to_unsigned(b.len_m1, master_config_c.len_width));
      loop
        wait until rising_edge(clock_s);
        exit when is_ready(master_config_c, master_bus(m).s.aw);
      end loop;
      wait until falling_edge(clock_s);
      master_bus(m).m.aw <= address_defaults(master_config_c);
      wait;
    end process;

    w_proc: process is
      constant b : burst_t := scenario_c(m);
    begin
      master_bus(m).m.w <= write_data_defaults(master_config_c);
      wait until reset_n_s = '1';
      for i in 0 to b.delay
      loop
        wait until falling_edge(clock_s);
      end loop;

      for beat in 0 to b.len_m1
      loop
        master_bus(m).m.w <= write_data(master_config_c,
                                        value => to_unsigned(b.addr + beat * 4, 32),
                                        strb => "1111",
                                        last => beat = b.len_m1);
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(master_config_c, master_bus(m).s.w);
        end loop;
        wait until falling_edge(clock_s);
        master_bus(m).m.w <= write_data_defaults(master_config_c);
        for i in 1 to b.gap
        loop
          wait until falling_edge(clock_s);
        end loop;
      end loop;
      wait;
    end process;

    b_proc: process is
    begin
      done_s(m) <= '0';
      master_bus(m).m.b <= accept(master_config_c, true);
      master_bus(m).m.ar <= address_defaults(master_config_c);
      master_bus(m).m.r <= accept(master_config_c, false);

      loop
        wait until rising_edge(clock_s);
        exit when is_valid(master_config_c, master_bus(m).s.b);
      end loop;

      assert id(master_config_c, master_bus(m).s.b) = std_ulogic_vector(to_unsigned(m, master_config_c.id_width))
        report "Master " & integer'image(m) & ": bad write response ID"
        severity failure;
      assert resp(master_config_c, master_bus(m).s.b) = RESP_OKAY
        report "Master " & integer'image(m) & ": bad write response"
        severity failure;

      log_info("Master " & integer'image(m) & ": write done");
      done_s(m) <= '1';
      wait;
    end process;
  end generate;

  watchdog: process is
  begin
    wait for 10 us;
    assert false
      report "Timeout, write order deadlock"
      severity failure;
    wait;
  end process;

  slave: process is
    type address_array is array (0 to 15) of address_t;
    variable aw_q, b_q : address_array;
    variable aw_wptr, aw_rptr, b_wptr, b_rptr : natural := 0;
    variable beat : natural := 0;
    variable expected : unsigned(31 downto 0);
  begin
    slave_bus(0).s.aw <= accept(slave_config_c, true);
    slave_bus(0).s.w <= accept(slave_config_c, true);
    slave_bus(0).s.b <= write_response_defaults(slave_config_c);
    slave_bus(0).s.ar <= accept(slave_config_c, false);
    slave_bus(0).s.r <= read_data_defaults(slave_config_c);

    loop
      wait until rising_edge(clock_s);

      if is_valid(slave_config_c, slave_bus(0).m.aw) then
        aw_q(aw_wptr) := slave_bus(0).m.aw;
        aw_wptr := aw_wptr + 1;
      end if;

      if is_valid(slave_config_c, slave_bus(0).m.w) then
        assert aw_rptr /= aw_wptr
          report "Write data before its address"
          severity failure;

        expected := address(slave_config_c, aw_q(aw_rptr)) + beat * 4;
        assert value(slave_config_c, slave_bus(0).m.w) = expected
          report "Write data beat for address " & to_hex_string(std_ulogic_vector(expected))
          & " carries " & to_hex_string(std_ulogic_vector(value(slave_config_c, slave_bus(0).m.w)))
          severity failure;

        if beat = to_integer(length_m1(slave_config_c, aw_q(aw_rptr), slave_config_c.len_width)) then
          assert is_last(slave_config_c, slave_bus(0).m.w)
            report "Missing last on write data"
            severity failure;
          b_q(b_wptr) := aw_q(aw_rptr);
          b_wptr := b_wptr + 1;
          aw_rptr := aw_rptr + 1;
          beat := 0;
        else
          assert not is_last(slave_config_c, slave_bus(0).m.w)
            report "Early last on write data"
            severity failure;
          beat := beat + 1;
        end if;
      end if;

      if is_valid(slave_config_c, slave_bus(0).s.b)
        and is_ready(slave_config_c, slave_bus(0).m.b) then
        b_rptr := b_rptr + 1;
      end if;

      wait until falling_edge(clock_s);

      if b_rptr /= b_wptr then
        slave_bus(0).s.b <= write_response(slave_config_c,
                                           id => id(slave_config_c, b_q(b_rptr)),
                                           resp => RESP_OKAY);
      else
        slave_bus(0).s.b <= write_response_defaults(slave_config_c);
      end if;
    end loop;
  end process;

  dut: nsl_amba.mm_routing.axi4_mm_crossbar
    generic map(
      master_config_c => master_config_c,
      slave_config_c => slave_config_c,
      master_count_c => master_count_c,
      routing_table_c => routing_table_c,
      default_slave_c => -1,
      aw_tracking_depth_c => 4
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      slave_i(0) => master_bus(0).m,
      slave_i(1) => master_bus(1).m,
      slave_i(2) => master_bus(2).m,
      slave_o(0) => master_bus(0).s,
      slave_o(1) => master_bus(1).s,
      slave_o(2) => master_bus(2).s,
      master_o(0) => slave_bus(0).m,
      master_i(0) => slave_bus(0).s
      );


  dumper_s0: nsl_amba.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => slave_config_c,
      prefix_c => "S0"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      master_i => slave_bus(0).m,
      slave_i => slave_bus(0).s
      );

  master_dumpers: for m in 0 to master_count_c-1
  generate
    dumper: nsl_amba.axi4_mm.axi4_mm_dumper
      generic map(
        config_c => master_config_c,
        prefix_c => "M" & integer'image(m)
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        master_i => master_bus(m).m,
        slave_i => master_bus(m).s
        );
  end generate;

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

end architecture;
