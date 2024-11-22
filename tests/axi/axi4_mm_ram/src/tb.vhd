library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_axi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_axi.axi4_mm.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal bus_s: bus_t;

  constant config_c : config_t := config(address_width => 32,
                                         data_bus_width => 32,
                                         max_length => 16,
                                         burst => true);

begin

  writer: process is
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable i: integer;
  begin
    done_s(0) <= '0';
    
    bus_s.m.aw <= address_defaults(config_c);
    bus_s.m.w <= write_data_defaults(config_c);
    bus_s.m.b <= accept(config_c, true);
    wait for 30 ns;
    wait until falling_edge(clock_s);

    while true
    loop
      bus_s.m.aw <= address(config_c, addr => x"00000000", len_m1 => x"7");
      wait until rising_edge(clock_s);
      if is_ready(config_c, bus_s.s.aw) then
        wait until falling_edge(clock_s);
        bus_s.m.aw <= address_defaults(config_c);
        exit;
      end if;
    end loop;

    i := 0;
    while true
    loop
      wait until falling_edge(clock_s);
      bus_s.m.w <= write_data(config_c, bytes => prbs_byte_string(state_v, prbs31, 4), last => i = 7);
      wait until rising_edge(clock_s);
      if is_ready(config_c, bus_s.s.w) then
        state_v := prbs_forward(state_v, prbs31, 32);
        if i /= 7 then
          i := i + 1;
        else
          wait until falling_edge(clock_s);
          bus_s.m.w <= write_data_defaults(config_c);
          exit;
        end if;
      end if;
    end loop;

    while true
    loop
      bus_s.m.aw <= address(config_c, addr => x"00000028", len_m1 => x"7", burst => BURST_WRAP);
      wait until rising_edge(clock_s);
      if is_ready(config_c, bus_s.s.aw) then
        wait until falling_edge(clock_s);
        bus_s.m.aw <= address_defaults(config_c);
        exit;
      end if;
    end loop;

    i := 0;
    while true
    loop
      wait until falling_edge(clock_s);
      bus_s.m.w <= write_data(config_c, bytes => prbs_byte_string(state_v, prbs31, 4), last => i = 7);
      wait until rising_edge(clock_s);
      if is_ready(config_c, bus_s.s.w) then
        state_v := prbs_forward(state_v, prbs31, 32);
        if i /= 7 then
          i := i + 1;
        else
          wait until falling_edge(clock_s);
          bus_s.m.w <= write_data_defaults(config_c);
          exit;
        end if;
      end if;
    end loop;
    
    done_s(0) <= '1';
    wait;
  end process;
  
  reader: process is
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable pushback_v : prbs_state(30 downto 0) := x"5555555"&"101";
    variable do_accept: boolean;
    variable rdata, expected: byte_string(0 to 2**config_c.data_bus_width_l2-1);
  begin
    done_s(1) <= '0';

    pushback_v := prbs_forward(pushback_v, prbs31, 49);

    bus_s.m.ar <= address_defaults(config_c);
    bus_s.m.r <= handshake_defaults(config_c);

    wait until rising_edge(clock_s);
    wait until done_s(0) = '1';

    while true
    loop
      bus_s.m.ar <= address(config_c, addr => x"00000000", len_m1 => x"7");
      wait until rising_edge(clock_s);
      if is_ready(config_c, bus_s.s.ar) then
        wait until falling_edge(clock_s);
        bus_s.m.ar <= address_defaults(config_c);
        exit;
      end if;
    end loop;

    while true
    loop
      wait until falling_edge(clock_s);
      do_accept := pushback_v(30) = '1';
      pushback_v := prbs_forward(pushback_v, prbs31, 1);
      bus_s.m.r <= accept(config_c, do_accept);
      wait until rising_edge(clock_s);
      if is_valid(config_c, bus_s.s.r) and do_accept then
        rdata := bytes(config_c, bus_s.s.r);
        expected := prbs_byte_string(state_v, prbs31, 4);

        assert_equal("Rdata1", rdata, expected, FAILURE);

        state_v := prbs_forward(state_v, prbs31, 32);
        if is_last(config_c, bus_s.s.r)then
          wait until falling_edge(clock_s);
          bus_s.m.r <= handshake_defaults(config_c);
          exit;
        end if;
      end if;
    end loop;

    while true
    loop
      bus_s.m.ar <= address(config_c, addr => x"00000028", len_m1 => x"7", burst => BURST_WRAP);
      wait until rising_edge(clock_s);
      if is_ready(config_c, bus_s.s.ar) then
        wait until falling_edge(clock_s);
        bus_s.m.ar <= address_defaults(config_c);
        exit;
      end if;
    end loop;

    while true
    loop
      wait until falling_edge(clock_s);
      do_accept := pushback_v(30) = '1';
      pushback_v := prbs_forward(pushback_v, prbs31, 1);
      bus_s.m.r <= accept(config_c, do_accept);
      wait until rising_edge(clock_s);
      if is_valid(config_c, bus_s.s.r) and do_accept then
        rdata := bytes(config_c, bus_s.s.r);
        expected := prbs_byte_string(state_v, prbs31, 4);

        assert_equal("Rdata1", rdata, expected, FAILURE);

        state_v := prbs_forward(state_v, prbs31, 32);
        if is_last(config_c, bus_s.s.r)then
          wait until falling_edge(clock_s);
          bus_s.m.r <= handshake_defaults(config_c);
          exit;
        end if;
      end if;
    end loop;
    
    wait for 150 ns;
    
    done_s(1) <= '1';
    wait;
  end process;

  dumper: nsl_axi.axi4_mm.axi4_mm_dumper
    generic map(
      config_c => config_c,
      prefix_c => "RAM"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      master_i => bus_s.m,
      slave_i => bus_s.s
      );
  
  dut: nsl_axi.axi4_mm.axi4_mm_ram
    generic map(
      config_c => config_c,
      word_count_l2_c => 8
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      axi_i => bus_s.m,
      axi_o => bus_s.s
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
