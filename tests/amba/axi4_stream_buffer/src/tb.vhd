library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal bus_s: bus_t;

  constant cfg_c: config_t := config(6, last => true, strobe => true);
  constant buffer_cfg_c: buffer_config_t := buffer_config(cfg_c, 20);

begin

  tx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable buf : buffer_t;
  begin
    done_s(0) <= '0';

    wait for 50 ns;

    buf := reset(buffer_cfg_c, prbs_byte_string(state_v, prbs31, buffer_cfg_c.data_width));

    loop
      send(cfg_c, clock_s, bus_s.s, bus_s.m, next_beat(buffer_cfg_c, buf, last => true));

      if is_last(buffer_cfg_c, buf) then
        exit;
      end if;

      buf := shift(buffer_cfg_c, buf);
    end loop;

    wait for 500 ns;

    state_v := prbs_forward(state_v, prbs31, buffer_cfg_c.data_width * 8);

    packet_send(cfg_c, clock_s, bus_s.s, bus_s.m,
                packet => prbs_byte_string(state_v, prbs31, buffer_cfg_c.data_width));

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  rx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable rx_data : byte_stream;
    variable id, user, dest : std_ulogic_vector(1 to 0);
    variable beat: master_t;
    variable done: boolean;
    variable buf : buffer_t;
  begin
    done_s(1) <= '0';

    bus_s.s <= accept(cfg_c, false);

    wait for 50 ns;

    packet_receive(cfg_c, clock_s, bus_s.m, bus_s.s,
                   packet => rx_data,
                   id => id,
                   user => user,
                   dest => dest);

    assert_equal("data", rx_data.all(0 to buffer_cfg_c.data_width-1), prbs_byte_string(state_v, prbs31, buffer_cfg_c.data_width), failure);

    state_v := prbs_forward(state_v, prbs31, buffer_cfg_c.data_width * 8);

    buf := reset(buffer_cfg_c);

    done := false;
    while not done
    loop
      done := is_last(buffer_cfg_c, buf);

      receive(cfg_c, clock_s, bus_s.m, bus_s.s, beat);

      assert is_last(cfg_c, beat) = done;
      
      buf := shift(buffer_cfg_c, buf, beat);
    end loop;

    assert_equal("data2", bytes(buffer_cfg_c, buf), prbs_byte_string(state_v, prbs31, buffer_cfg_c.data_width), failure);

    wait for 500 ns;

    done_s(1) <= '1';
    wait;
  end process;

  dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "bus"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => bus_s
      );
  
  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 10 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );
  
end;
