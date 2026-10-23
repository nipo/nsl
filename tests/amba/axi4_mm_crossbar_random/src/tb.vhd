library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_amba;
use nsl_amba.axi4_mm.all;

package tb_pkg is

  constant master_count_c : positive := 3;
  constant slave_count_c : positive := 3;
  constant burst_count_c : positive := 200;

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

  procedure rand_int(variable s1, s2 : inout positive;
                     max : natural;
                     variable v : out natural);

  -- Random burst to a random slave.  Slave s lives at s * 0x10000000.
  procedure rand_burst(variable s1, s2 : inout positive;
                       variable addr : out unsigned(31 downto 0);
                       variable len_m1 : out natural);

end package;

package body tb_pkg is

  procedure rand_int(variable s1, s2 : inout positive;
                     max : natural;
                     variable v : out natural)
  is
    variable x : real;
    variable ret : natural;
  begin
    uniform(s1, s2, x);
    ret := integer(trunc(x * real(max + 1)));
    if ret > max then
      ret := max;
    end if;
    v := ret;
  end procedure;

  procedure rand_burst(variable s1, s2 : inout positive;
                       variable addr : out unsigned(31 downto 0);
                       variable len_m1 : out natural)
  is
    variable slave, offset, len : natural;
  begin
    rand_int(s1, s2, slave_count_c-1, slave);
    rand_int(s1, s2, 16#3c0#, offset);
    rand_int(s1, s2, 15, len);
    addr := to_unsigned(slave * 16#10000000# + offset * 4, 32);
    len_m1 := len;
  end procedure;

end package body;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_data.text.all;
use work.tb_pkg.all;

-- Slave model.  Accepts addresses ahead of data, checks every write
-- data beat carries its own address, returns its address as read
-- data, after read_latency_c cycles.  Ready signals are random.
entity tb_slave is
  generic(
    seed_c : positive;
    -- Wait for WVALID before asserting AWREADY
    aw_after_w_c : boolean;
    read_latency_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    axi_i : in master_t;
    axi_o : out slave_t
    );
end entity;

architecture beh of tb_slave is
begin

  model: process is
    constant depth_c : positive := 16;
    type address_array is array (0 to depth_c-1) of address_t;
    type natural_array is array (0 to depth_c-1) of natural;
    variable aw_q, b_q, ar_q : address_array;
    variable ar_time : natural_array;
    variable aw_w, aw_r, b_w, b_r, ar_w, ar_r : natural := 0;
    variable w_beat, r_beat : natural := 0;
    variable cycle : natural := 0;
    variable aw_rdy, w_rdy, b_vld, ar_rdy, r_vld : boolean := false;
    variable s1 : positive := seed_c;
    variable s2 : positive := 17;
    variable dice : natural;
    variable expected : unsigned(31 downto 0);
  begin
    axi_o.aw <= accept(slave_config_c, false);
    axi_o.w <= accept(slave_config_c, false);
    axi_o.b <= write_response_defaults(slave_config_c);
    axi_o.ar <= accept(slave_config_c, false);
    axi_o.r <= read_data_defaults(slave_config_c);

    loop
      wait until rising_edge(clock_i);

      if reset_n_i = '0' then
        aw_rdy := false;
        w_rdy := false;
        b_vld := false;
        ar_rdy := false;
        r_vld := false;
      end if;

      if aw_rdy and is_valid(slave_config_c, axi_i.aw) then
        aw_q(aw_w mod depth_c) := axi_i.aw;
        aw_w := aw_w + 1;
      end if;

      if w_rdy and is_valid(slave_config_c, axi_i.w) then
        expected := address(slave_config_c, aw_q(aw_r mod depth_c)) + w_beat * 4;
        assert value(slave_config_c, axi_i.w) = expected
          report "Write data beat for address " & to_hex_string(std_ulogic_vector(expected))
          & " carries " & to_hex_string(std_ulogic_vector(value(slave_config_c, axi_i.w)))
          severity failure;

        if w_beat = to_integer(length_m1(slave_config_c, aw_q(aw_r mod depth_c), slave_config_c.len_width)) then
          assert is_last(slave_config_c, axi_i.w)
            report "Missing last on write data"
            severity failure;
          b_q(b_w mod depth_c) := aw_q(aw_r mod depth_c);
          b_w := b_w + 1;
          aw_r := aw_r + 1;
          w_beat := 0;
        else
          assert not is_last(slave_config_c, axi_i.w)
            report "Early last on write data"
            severity failure;
          w_beat := w_beat + 1;
        end if;
      end if;

      if b_vld and is_ready(slave_config_c, axi_i.b) then
        b_r := b_r + 1;
      end if;

      if ar_rdy and is_valid(slave_config_c, axi_i.ar) then
        ar_q(ar_w mod depth_c) := axi_i.ar;
        ar_time(ar_w mod depth_c) := cycle;
        ar_w := ar_w + 1;
      end if;

      if r_vld and is_ready(slave_config_c, axi_i.r) then
        if r_beat = to_integer(length_m1(slave_config_c, ar_q(ar_r mod depth_c), slave_config_c.len_width)) then
          ar_r := ar_r + 1;
          r_beat := 0;
        else
          r_beat := r_beat + 1;
        end if;
        r_vld := false;
      end if;

      cycle := cycle + 1;

      wait until falling_edge(clock_i);

      rand_int(s1, s2, 3, dice);
      aw_rdy := aw_w - aw_r < 8 and b_w - b_r < 8 and dice /= 0
                and (not aw_after_w_c or is_valid(slave_config_c, axi_i.w));
      rand_int(s1, s2, 3, dice);
      w_rdy := aw_w /= aw_r and dice /= 0;
      rand_int(s1, s2, 3, dice);
      ar_rdy := ar_w - ar_r < 8 and dice /= 0;

      b_vld := b_w /= b_r;
      if not r_vld and ar_w /= ar_r and cycle >= ar_time(ar_r mod depth_c) + read_latency_c then
        rand_int(s1, s2, 3, dice);
        r_vld := dice /= 0;
      end if;

      axi_o.aw <= accept(slave_config_c, aw_rdy);
      axi_o.w <= accept(slave_config_c, w_rdy);
      axi_o.ar <= accept(slave_config_c, ar_rdy);

      if b_vld then
        axi_o.b <= write_response(slave_config_c,
                                  id => id(slave_config_c, b_q(b_r mod depth_c)),
                                  resp => RESP_OKAY);
      else
        axi_o.b <= write_response_defaults(slave_config_c);
      end if;

      if r_vld then
        axi_o.r <= read_data(slave_config_c,
                             id => id(slave_config_c, ar_q(ar_r mod depth_c)),
                             value => address(slave_config_c, ar_q(ar_r mod depth_c)) + r_beat * 4,
                             resp => RESP_OKAY,
                             last => r_beat = to_integer(length_m1(slave_config_c, ar_q(ar_r mod depth_c), slave_config_c.len_width)));
      else
        axi_o.r <= read_data_defaults(slave_config_c);
      end if;
    end loop;
  end process;

end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_amba, nsl_data;
use nsl_simulation.logging.all;
use nsl_amba.axi4_mm.all;
use nsl_data.text.all;
use work.tb_pkg.all;

-- Random traffic through the crossbar.  Each master issues reads and
-- writes with a single ID to random slaves, so responses must come
-- back in issue order.  Masters send write data without waiting for
-- write addresses, one slave waits for write data before accepting
-- write addresses, slaves have different read latencies.
entity tb is
end tb;

architecture arch of tb is

  constant routing_table_c : nsl_amba.address.address_vector := nsl_amba.address.routing_table(
    32,
    "x0-------/4",
    "x1-------/4",
    "x2-------/4"
    );

  type natural_vector is array (natural range <>) of natural;
  type boolean_vector is array (natural range <>) of boolean;

  constant read_latency_c : natural_vector(0 to slave_count_c-1) := (30, 0, 5);
  constant aw_after_w_c : boolean_vector(0 to slave_count_c-1) := (false, true, false);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to master_count_c-1);
  signal write_done_s, read_done_s : std_ulogic_vector(0 to master_count_c-1);

  signal master_bus : bus_vector(0 to master_count_c-1);
  signal slave_bus : bus_vector(0 to slave_count_c-1);

begin

  masters: for m in 0 to master_count_c-1
  generate
    constant id_c : std_ulogic_vector(master_config_c.id_width-1 downto 0)
      := std_ulogic_vector(to_unsigned(m, master_config_c.id_width));
    constant write_seed_c : positive := 7 * m + 1;
    constant read_seed_c : positive := 7 * m + 3;
  begin
    aw_proc: process is
      variable s1 : positive := write_seed_c;
      variable s2 : positive := 11;
      variable g1 : positive := write_seed_c;
      variable g2 : positive := 23;
      variable addr : unsigned(31 downto 0);
      variable len_m1, gap : natural;
    begin
      master_bus(m).m.aw <= address_defaults(master_config_c);
      wait until reset_n_s = '1';
      wait until falling_edge(clock_s);

      for i in 0 to burst_count_c-1
      loop
        rand_burst(s1, s2, addr, len_m1);
        rand_int(g1, g2, 3, gap);
        for j in 1 to gap
        loop
          wait until falling_edge(clock_s);
        end loop;

        master_bus(m).m.aw <= address(master_config_c,
                                      id => id_c,
                                      addr => addr,
                                      len_m1 => to_unsigned(len_m1, master_config_c.len_width));
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(master_config_c, master_bus(m).s.aw);
        end loop;
        wait until falling_edge(clock_s);
        master_bus(m).m.aw <= address_defaults(master_config_c);
      end loop;
      wait;
    end process;

    w_proc: process is
      variable s1 : positive := write_seed_c;
      variable s2 : positive := 11;
      variable g1 : positive := write_seed_c;
      variable g2 : positive := 29;
      variable addr : unsigned(31 downto 0);
      variable len_m1, gap : natural;
    begin
      master_bus(m).m.w <= write_data_defaults(master_config_c);
      wait until reset_n_s = '1';
      wait until falling_edge(clock_s);

      for i in 0 to burst_count_c-1
      loop
        rand_burst(s1, s2, addr, len_m1);
        for beat in 0 to len_m1
        loop
          rand_int(g1, g2, 2, gap);
          for j in 1 to gap
          loop
            wait until falling_edge(clock_s);
          end loop;

          master_bus(m).m.w <= write_data(master_config_c,
                                          value => addr + beat * 4,
                                          strb => "1111",
                                          last => beat = len_m1);
          loop
            wait until rising_edge(clock_s);
            exit when is_ready(master_config_c, master_bus(m).s.w);
          end loop;
          wait until falling_edge(clock_s);
          master_bus(m).m.w <= write_data_defaults(master_config_c);
        end loop;
      end loop;
      wait;
    end process;

    b_proc: process is
      variable g1 : positive := write_seed_c;
      variable g2 : positive := 31;
      variable dice : natural;
      variable rdy : boolean := false;
      variable count : natural := 0;
    begin
      write_done_s(m) <= '0';
      master_bus(m).m.b <= accept(master_config_c, false);
      wait until reset_n_s = '1';

      while count < burst_count_c
      loop
        wait until falling_edge(clock_s);
        rand_int(g1, g2, 3, dice);
        rdy := dice /= 0;
        master_bus(m).m.b <= accept(master_config_c, rdy);

        wait until rising_edge(clock_s);
        if rdy and is_valid(master_config_c, master_bus(m).s.b) then
          assert id(master_config_c, master_bus(m).s.b) = id_c
            report "Master " & integer'image(m) & ": bad write response ID"
            severity failure;
          assert resp(master_config_c, master_bus(m).s.b) = RESP_OKAY
            report "Master " & integer'image(m) & ": bad write response"
            severity failure;
          count := count + 1;
        end if;
      end loop;

      wait until falling_edge(clock_s);
      master_bus(m).m.b <= accept(master_config_c, false);
      log_info("Master " & integer'image(m) & ": writes done");
      write_done_s(m) <= '1';
      wait;
    end process;

    ar_proc: process is
      variable s1 : positive := read_seed_c;
      variable s2 : positive := 13;
      variable g1 : positive := read_seed_c;
      variable g2 : positive := 37;
      variable addr : unsigned(31 downto 0);
      variable len_m1, gap : natural;
    begin
      master_bus(m).m.ar <= address_defaults(master_config_c);
      wait until reset_n_s = '1';
      wait until falling_edge(clock_s);

      for i in 0 to burst_count_c-1
      loop
        rand_burst(s1, s2, addr, len_m1);
        rand_int(g1, g2, 3, gap);
        for j in 1 to gap
        loop
          wait until falling_edge(clock_s);
        end loop;

        master_bus(m).m.ar <= address(master_config_c,
                                      id => id_c,
                                      addr => addr,
                                      len_m1 => to_unsigned(len_m1, master_config_c.len_width));
        loop
          wait until rising_edge(clock_s);
          exit when is_ready(master_config_c, master_bus(m).s.ar);
        end loop;
        wait until falling_edge(clock_s);
        master_bus(m).m.ar <= address_defaults(master_config_c);
      end loop;
      wait;
    end process;

    r_proc: process is
      variable s1 : positive := read_seed_c;
      variable s2 : positive := 13;
      variable g1 : positive := read_seed_c;
      variable g2 : positive := 41;
      variable addr : unsigned(31 downto 0);
      variable len_m1, dice : natural;
      variable beat : natural := 0;
      variable count : natural := 0;
      variable rdy : boolean := false;
    begin
      read_done_s(m) <= '0';
      master_bus(m).m.r <= accept(master_config_c, false);
      wait until reset_n_s = '1';
      rand_burst(s1, s2, addr, len_m1);

      while count < burst_count_c
      loop
        wait until falling_edge(clock_s);
        rand_int(g1, g2, 3, dice);
        rdy := dice /= 0;
        master_bus(m).m.r <= accept(master_config_c, rdy);

        wait until rising_edge(clock_s);
        if rdy and is_valid(master_config_c, master_bus(m).s.r) then
          assert id(master_config_c, master_bus(m).s.r) = id_c
            report "Master " & integer'image(m) & ": bad read data ID"
            severity failure;
          assert value(master_config_c, master_bus(m).s.r) = addr + beat * 4
            report "Master " & integer'image(m) & ": read data beat for address "
            & to_hex_string(std_ulogic_vector(addr + beat * 4))
            & " carries " & to_hex_string(std_ulogic_vector(value(master_config_c, master_bus(m).s.r)))
            severity failure;
          assert is_last(master_config_c, master_bus(m).s.r) = (beat = len_m1)
            report "Master " & integer'image(m) & ": bad read data last"
            severity failure;

          if beat = len_m1 then
            count := count + 1;
            beat := 0;
            rand_burst(s1, s2, addr, len_m1);
          else
            beat := beat + 1;
          end if;
        end if;
      end loop;

      wait until falling_edge(clock_s);
      master_bus(m).m.r <= accept(master_config_c, false);
      log_info("Master " & integer'image(m) & ": reads done");
      read_done_s(m) <= '1';
      wait;
    end process;

    done_s(m) <= write_done_s(m) and read_done_s(m);
  end generate;

  slaves: for s in 0 to slave_count_c-1
  generate
    slave: entity work.tb_slave
      generic map(
        seed_c => 5 * s + 2,
        aw_after_w_c => aw_after_w_c(s),
        read_latency_c => read_latency_c(s)
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,
        axi_i => slave_bus(s).m,
        axi_o => slave_bus(s).s
        );
  end generate;

  watchdog: process is
  begin
    wait for 2 ms;
    assert false
      report "Timeout, crossbar deadlock"
      severity failure;
    wait;
  end process;

  dut: nsl_amba.mm_routing.axi4_mm_crossbar
    generic map(
      master_config_c => master_config_c,
      slave_config_c => slave_config_c,
      master_count_c => master_count_c,
      routing_table_c => routing_table_c,
      default_slave_c => -1,
      aw_tracking_depth_c => 4,
      master_slice_c => true,
      slave_slice_c => true
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
      master_o(1) => slave_bus(1).m,
      master_o(2) => slave_bus(2).m,
      master_i(0) => slave_bus(0).s,
      master_i(1) => slave_bus(1).s,
      master_i(2) => slave_bus(2).s
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

end architecture;
