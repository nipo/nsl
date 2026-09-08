library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_mii, nsl_simulation, work;
use nsl_amba.axi4_stream.all;
use nsl_mii.flit.all;

entity tb is
end tb;

-- Two frames are pushed back to back into the MII transmit flit
-- converter while the flit sink is throttled below the core clock, as
-- the resync fifo does on hardware.  The idle byte times the converter
-- inserts between the frames must be a full inter-frame gap; an
-- ungated gap counter collapses it to a couple of bytes here.
architecture arch of tb is

  constant clock_period_c : time := 10 ns;
  constant cfg_c : config_t := axi4_flit_cfg;
  constant ipg_bits_c : natural := 96;
  constant ipg_bytes_c : natural := ipg_bits_c / 8;

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal in_s : master_t;
  signal in_ready_s : slave_t;
  signal flit_s : mii_flit_t;
  signal ready_s : std_ulogic;
  signal packet_s : std_ulogic;

begin

  dut: nsl_mii.flit.mii_flit_from_axi4_stream
    generic map(
      ipg_c => ipg_bits_c
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      in_i => in_s,
      in_o => in_ready_s,
      underrun_o => open,
      packet_o => packet_s,
      flit_o => flit_s,
      ready_i => ready_s
      );

  -- The flit sink: one flit accepted every fourth cycle, so the flit
  -- rate is a quarter of the core clock.
  throttle: process(clock_s, reset_n_s)
    variable phase : integer range 0 to 3;
  begin
    if rising_edge(clock_s) then
      if phase = 0 then
        phase := 3;
        ready_s <= '1';
      else
        phase := phase - 1;
        ready_s <= '0';
      end if;
    end if;
    if reset_n_s = '0' then
      phase := 3;
      ready_s <= '0';
    end if;
  end process;

  feed: process
    procedure send_frame(len : natural) is
    begin
      for i in 0 to len - 1 loop
        in_s <= transfer(cfg_c,
                         bytes => (0 => std_ulogic_vector(to_unsigned(i, 8))),
                         valid => true,
                         last => i = len - 1);
        wait until rising_edge(clock_s) and is_ready(cfg_c, in_ready_s);
      end loop;
      in_s <= transfer(cfg_c, bytes => (0 => x"00"), valid => false);
    end procedure;
  begin
    in_s <= transfer(cfg_c, bytes => (0 => x"00"), valid => false);
    wait until reset_n_s = '1';
    wait until rising_edge(clock_s);
    send_frame(16);
    send_frame(16);
    wait for 200 * clock_period_c;
    wait;
  end process;

  -- Count idle byte times between the two frames: flit consumption
  -- events (ready high) while no packet is being emitted, after the
  -- first frame ends and before the second begins.
  check: process
    variable seen_first, in_gap, seen_second : boolean := false;
    variable idle : natural := 0;
  begin
    done_s(0) <= '0';
    wait until reset_n_s = '1';
    loop
      wait until rising_edge(clock_s);
      exit when seen_second;
      if ready_s = '1' then
        if packet_s = '1' then
          if seen_first and in_gap then
            seen_second := true;
          end if;
          seen_first := true;
          in_gap := false;
        elsif seen_first then
          in_gap := true;
          idle := idle + 1;
        end if;
      end if;
    end loop;
    report "idle byte times between frames: " & integer'image(idle);
    assert idle >= ipg_bytes_c
      report "inter-frame gap " & integer'image(idle)
      & " byte times is below the required " & integer'image(ipg_bytes_c)
      severity failure;
    done_s(0) <= '1';
    wait;
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
