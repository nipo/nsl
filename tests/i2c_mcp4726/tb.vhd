library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_i2c, nsl_simulation, nsl_data;
use nsl_data.bytestream.all;
use nsl_i2c.mcp4726.all;

entity tb is
end tb;

-- The DAC control path as a design uses it: a one-shot initer and
-- the updater share one transactor through an arbiter, toward an
-- acknowledging slave.  Every code change must leave the updater
-- ready again.
architecture arch of tb is

  constant clock_period_c : time := 10 ns;
  constant address_c : unsigned(6 downto 0) := mcp4726_addr(0);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal i2c_i_s : nsl_i2c.i2c.i2c_i;
  signal i2c_slave_s, i2c_master_s : nsl_i2c.i2c.i2c_o;

  signal cmd_req_s, rsp_req_s : nsl_bnoc.framed.framed_req_array(0 to 1);
  signal cmd_ack_s, rsp_ack_s : nsl_bnoc.framed.framed_ack_array(0 to 1);
  signal t_cmd_req_s, t_rsp_req_s : nsl_bnoc.framed.framed_req;
  signal t_cmd_ack_s, t_rsp_ack_s : nsl_bnoc.framed.framed_ack;

  signal init_done_s, ready_s : std_ulogic;
  signal value_s : unsigned(11 downto 0);

begin

  initer: nsl_bnoc.framed_transactor.framed_transactor_once
    generic map(
      config_c => nsl_bnoc.framed_transactor.framed_transaction(
        null_byte_string
        & nsl_bnoc.framed_transactor.i2c_div(4)
        & mcp4726_init(
          saddr => address_c,
          vref => VREF_BUFFERED,
          power => POWER_ON,
          gain => 1,
          value => x"800")
        )
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      done_o => init_done_s,
      cmd_o => cmd_req_s(0),
      cmd_i => cmd_ack_s(0),
      rsp_i => rsp_req_s(0),
      rsp_o => rsp_ack_s(0)
      );

  updater: nsl_i2c.mcp4726.mcp4726_updater
    generic map(
      i2c_addr_c => address_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      enable_i => init_done_s,
      value_i => value_s,
      ready_o => ready_s,
      cmd_o => cmd_req_s(1),
      cmd_i => cmd_ack_s(1),
      rsp_i => rsp_req_s(1),
      rsp_o => rsp_ack_s(1)
      );

  arbiter: nsl_bnoc.framed.framed_arbitrer
    generic map(
      source_count => 2
      )
    port map(
      p_resetn => reset_n_s,
      p_clk => clock_s,
      p_cmd_val => cmd_req_s,
      p_cmd_ack => cmd_ack_s,
      p_rsp_val => rsp_req_s,
      p_rsp_ack => rsp_ack_s,
      p_target_cmd_val => t_cmd_req_s,
      p_target_cmd_ack => t_cmd_ack_s,
      p_target_rsp_val => t_rsp_req_s,
      p_target_rsp_ack => t_rsp_ack_s
      );

  transactor: nsl_i2c.transactor.transactor_framed_controller
    generic map(
      clock_i_hz_c => 100000000
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      cmd_i => t_cmd_req_s,
      cmd_o => t_cmd_ack_s,
      rsp_o => t_rsp_req_s,
      rsp_i => t_rsp_ack_s,
      i2c_o => i2c_master_s,
      i2c_i => i2c_i_s
      );

  slave: nsl_i2c.clockfree.clockfree_memory
    generic map(
      address => address_c,
      addr_width => 8
      )
    port map(
      i2c_i => i2c_i_s,
      i2c_o => i2c_slave_s
      );

  resolver: nsl_i2c.i2c.i2c_resolver
    generic map(
      port_count => 2
      )
    port map(
      bus_i(0) => i2c_slave_s,
      bus_i(1) => i2c_master_s,
      bus_o => i2c_i_s
      );

  stim: process
    procedure set(code : unsigned(11 downto 0)) is
      variable waited : natural := 0;
    begin
      value_s <= code;
      wait until rising_edge(clock_s);
      wait until rising_edge(clock_s);
      -- The write is under way once the updater drops ready.
      while ready_s = '1' loop
        wait until rising_edge(clock_s);
        waited := waited + 1;
        assert waited < 1000
          report "updater never picked code " & integer'image(to_integer(code))
          severity failure;
      end loop;
      waited := 0;
      while ready_s = '0' loop
        wait until rising_edge(clock_s);
        waited := waited + 1;
        assert waited < 200000
          report "updater stuck after code " & integer'image(to_integer(code))
          severity failure;
      end loop;
      report "code " & integer'image(to_integer(code)) & " written in "
        & integer'image(waited) & " cycles";
    end procedure;
  begin
    done_s(0) <= '0';
    value_s <= x"800";
    wait until reset_n_s = '1';
    wait until init_done_s = '1';
    wait for 1 us;

    set(x"821");
    set(x"8ff");
    set(x"900");
    set(x"7c1");
    set(x"800");

    done_s(0) <= '1';
    wait;
  end process;

  -- Flit trace at the transactor, for the log.
  trace: process(clock_s)
    variable stall : natural := 0;
  begin
    if rising_edge(clock_s) then
      if t_cmd_req_s.valid = '1' and t_cmd_ack_s.ready = '1' then
        report "cmd flit " & integer'image(to_integer(unsigned(t_cmd_req_s.data)))
          & " last=" & std_ulogic'image(t_cmd_req_s.last);
      end if;
      if t_rsp_req_s.valid = '1' and t_rsp_ack_s.ready = '1' then
        report "rsp flit " & integer'image(to_integer(unsigned(t_rsp_req_s.data)))
          & " last=" & std_ulogic'image(t_rsp_req_s.last);
        stall := 0;
      elsif t_rsp_req_s.valid = '1' then
        stall := stall + 1;
        if stall = 5000 then
          report "rsp flit " & integer'image(to_integer(unsigned(t_rsp_req_s.data)))
            & " last=" & std_ulogic'image(t_rsp_req_s.last)
            & " not accepted for 5000 cycles, updater ready="
            & std_ulogic'image(ready_s);
        end if;
      end if;
    end if;
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => clock_period_c,
      reset_duration(0) => clock_period_c * 5,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end;
