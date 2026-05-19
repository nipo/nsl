library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_avalon;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.control.all;
use nsl_simulation.logging.all;
use nsl_avalon.avalon_st.all;

entity tb is
end tb;

architecture arch of tb is

  constant beat_count_c : natural := 32;

  signal clock_s   : std_ulogic;
  signal reset_n_s : std_ulogic;
  signal done_s    : std_ulogic_vector(0 to 3);

  function mkcfg(rl: natural) return config_t is
  begin
    return config(symbols_per_beat => 1,
                  data_bits_per_symbol => 8,
                  has_ready => true,
                  ready_latency => rl,
                  ready_allowance => rl);
  end function;

  function pick_in_rl(i: integer) return natural is
  begin
    case i is
      when 0 => return 0;
      when 1 => return 0;
      when 2 => return 2;
      when others => return 1;
    end case;
  end function;

  function pick_out_rl(i: integer) return natural is
  begin
    case i is
      when 0 => return 0;
      when 1 => return 2;
      when 2 => return 0;
      when others => return 3;
    end case;
  end function;

  -- One adapter per scenario, plus per-scenario bus signals.
  type bus_array_t is array (0 to 3) of bus_t;
  signal in_bus_s  : bus_array_t;
  signal out_bus_s : bus_array_t;

begin

  scenarios: for i in 0 to 3 generate
    constant in_cfg_c  : config_t := mkcfg(pick_in_rl(i));
    constant out_cfg_c : config_t := mkcfg(pick_out_rl(i));
    constant in_rl_c   : natural  := pick_in_rl(i);
  begin
    dut: avalon_st_ready_latency_adapter
      generic map(in_config_c => in_cfg_c, out_config_c => out_cfg_c)
      port map(clock_i   => clock_s,
               reset_n_i => reset_n_s,
               in_i      => in_bus_s(i).src,
               in_o      => in_bus_s(i).snk,
               out_o     => out_bus_s(i).src,
               out_i     => out_bus_s(i).snk);

    tester: process
      variable expected_v   : byte_string(0 to beat_count_c-1);
      variable observed_v   : byte_string(0 to beat_count_c-1);
      variable in_idx_v     : natural := 0;
      variable out_idx_v    : natural := 0;
      variable promise_sr_v : std_ulogic_vector(7 downto 0) := (others => '0');
      variable state_v      : prbs_state(30 downto 0) := x"deadbee"&"111";
    begin
      done_s(i)         <= '0';
      in_bus_s(i).src   <= transfer_defaults(in_cfg_c);
      out_bus_s(i).snk  <= accept(out_cfg_c, ready => true);

      expected_v := prbs_byte_string(state_v, prbs31, beat_count_c);

      wait until reset_n_s = '1';
      wait until rising_edge(clock_s);

      while out_idx_v < beat_count_c loop
        -- Sample post-edge: registers and combinational outputs have settled.
        wait until rising_edge(clock_s);

        if out_bus_s(i).src.valid = '1' and out_idx_v < beat_count_c then
          observed_v(out_idx_v) :=
            std_ulogic_vector(out_bus_s(i).src.data(7 downto 0));
          out_idx_v := out_idx_v + 1;
        end if;

        -- Shift in this cycle's ready into the promise tracker.
        if in_rl_c > 0 then
          promise_sr_v := promise_sr_v(6 downto 0) & in_bus_s(i).snk.ready;
        end if;

        -- Drive on the falling edge so values are stable well before
        -- the next rising_edge.
        wait until falling_edge(clock_s);

        if in_rl_c = 0 then
          if in_bus_s(i).snk.ready = '1' and in_idx_v < beat_count_c then
            in_bus_s(i).src <= transfer(in_cfg_c,
                                        bytes => expected_v(in_idx_v to in_idx_v),
                                        valid => true);
            in_idx_v := in_idx_v + 1;
          else
            in_bus_s(i).src <= transfer_defaults(in_cfg_c);
          end if;
        else
          if promise_sr_v(in_rl_c-1) = '1' and in_idx_v < beat_count_c then
            in_bus_s(i).src <= transfer(in_cfg_c,
                                        bytes => expected_v(in_idx_v to in_idx_v),
                                        valid => true);
            in_idx_v := in_idx_v + 1;
          else
            in_bus_s(i).src <= transfer_defaults(in_cfg_c);
          end if;
        end if;
      end loop;

      for k in 0 to beat_count_c-1 loop
        assert_equal("scenario "&integer'image(i)&" beat "&integer'image(k),
                     observed_v(k), expected_v(k), failure);
      end loop;

      log_info("scenario "&integer'image(i)
               &" (in.RL="&integer'image(in_cfg_c.ready_latency)
               &", out.RL="&integer'image(out_cfg_c.ready_latency)
               &") OK");

      done_s(i) <= '1';
      wait;
    end process;
  end generate;

  watchdog: process
  begin
    wait for 50 us;
    log_info("watchdog timeout: done_s = "&to_string(done_s));
    terminate(1);
  end process;

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count  => 4
      )
    port map(
      clock_period(0)   => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0)      => reset_n_s,
      clock_o(0)        => clock_s,
      done_i            => done_s
      );

end;
