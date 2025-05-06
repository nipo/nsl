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

  constant cfg_c: config_t := config(5, last => true, strobe => true);
  constant buf_cfg_c: buffer_config_t := buffer_config(cfg_c, 16);
  
begin

  tx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable buf : buffer_t;
    variable done: boolean := false;
    variable data_length: natural;
  begin
    done_s(0) <= '0';
    
    bus_s.m <= transfer_defaults(cfg_c);

    for byte_count in 1 to 16
    loop
      buf := reset(buf_cfg_c, prbs_byte_string(state_v, prbs31, byte_count));
      state_v := prbs_forward(state_v, prbs31, byte_count * 8);

      loop
        send(cfg_c, clock_s, bus_s.s, bus_s.m, next_beat(buf_cfg_c, buf, last => true));

        if is_last(buf_cfg_c, buf) then
          exit;
        end if;

        buf := shift(buf_cfg_c, buf);
      end loop;
    end loop;

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  rx: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable to_rx, did_rx : byte_string(0 to buf_cfg_c.data_width-1);
    variable buf : buffer_t;
    variable b: master_t;
    variable was_buf_last: boolean;
    variable rx_count: integer;
  begin
    done_s(1) <= '0';

    wait for 50 ns;

    for byte_count in 1 to 16
    loop
      to_rx(0 to byte_count-1) := prbs_byte_string(state_v, prbs31, byte_count);
      state_v := prbs_forward(state_v, prbs31, byte_count * 8);

      buf := reset(buf_cfg_c);

      rx_loop: loop
        receive(cfg_c, clock_s, bus_s.m, bus_s.s, b);

        was_buf_last := is_last(buf_cfg_c, buf);
        buf := shift(buf_cfg_c, buf, b);

        if is_last(cfg_c, b) then
          exit;
        end if;
      end loop;

      report "Received " & to_string(buf_cfg_c, buf);

      if was_buf_last then
        rx_count := buf_cfg_c.beat_count;
      else
        rx_count := buf.beat_count;
        loop
          was_buf_last := is_last(buf_cfg_c, buf);
          buf := realign(buf_cfg_c, buf);
          if was_buf_last then
            exit;
          end if;
        end loop;
      end if;

      report "Aligned  " & to_string(buf_cfg_c, buf);

      did_rx := bytes(buf_cfg_c, buf);
      
      assert_equal("data", to_rx(0 to byte_count-1), did_rx(0 to byte_count-1), failure);
      assert_equal("beat count", rx_count, (byte_count+cfg_c.data_width-1) / cfg_c.data_width, failure);
    end loop;

    wait for 50 ns;

    done_s(1) <= '1';
    wait;
  end process;
  
  dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "BUS "
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
