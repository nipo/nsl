library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_line_coding, nsl_clocking, nsl_hdmi, nsl_color, nsl_data, nsl_dvi;
use nsl_simulation.assertions.all;
use nsl_color.rgb.all;
use nsl_data.bytestream.all;
use nsl_line_coding.tmds.all;
use nsl_dvi.dvi.all;
use nsl_hdmi.hdmi.all;
use nsl_hdmi.encoder.all;

entity tb is
end tb;

architecture arch of tb is

  signal di_s: data_island_t;
  signal di_ready_s, di_valid_s: std_ulogic;
  signal sof_s, sol_s, pixel_ready_s: std_ulogic;
  signal pixel_s : nsl_color.rgb.rgb24;
  signal tmds_s : symbol_vector_t;
  
  signal reset_n, reset_n_async, clock: std_ulogic;
  signal done: std_ulogic_vector(0 to 0);
  signal ok : std_ulogic;
  
begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_async,
      data_o => reset_n,
      clock_i => clock
      );

  pixels: process
    variable r : integer;
  begin
    done(0) <= '0';

    while true
    loop
      wait until falling_edge(clock);
      if sol_s = '1' then
        r := 0;
      end if;

      if pixel_ready_s = '1' then
        r := r + 1 mod 4;
      end if;

      case r is
        when 0 => pixel_s <= rgb24_red;
        when 1 => pixel_s <= rgb24_green;
        when 2 => pixel_s <= rgb24_blue;
        when others => pixel_s <= rgb24_black;
      end case;

      wait until rising_edge(clock);
    end loop;

    done(0) <= '1';

    wait;
  end process;

  stim: process
  begin
    di_valid_s <= '0';

    wait for 5000 ns;

    while true
    loop
      
      wait until rising_edge(clock);

      di_valid_s <= '1';
      di_s.packet_type <= x"01";
      di_s.hb(1) <= x"de";
      di_s.hb(2) <= x"ad";
      di_s.pb <= from_hex("deadbeefdecafbaddeadbeefdecafbaddeadbeefdecafbad12345678");

      while true
      loop
        wait until falling_edge(clock);
        if di_ready_s = '1' then
          wait until rising_edge(clock);
          wait until falling_edge(clock);
          di_valid_s <= '0';
          exit;
        end if;
      end loop;
    end loop;
    
    wait;
  end process;
  
  enc: nsl_hdmi.encoder.hdmi_13_encoder
    port map(
      pixel_clock_i => clock,
      reset_n_i => reset_n,

      v_fp_m1_i => to_unsigned(5, 3),
      v_sync_m1_i => to_unsigned(5, 3),
      v_bp_m1_i => to_unsigned(20, 5),
      v_act_m1_i => to_unsigned(720, 10),

      h_fp_m1_i => to_unsigned(440, 9),
      h_sync_m1_i => to_unsigned(40, 6),
      h_bp_m1_i => to_unsigned(220, 8),
      h_act_m1_i => to_unsigned(1280, 11),

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_i => pixel_s,

--      di_valid_i => di_valid_s,
--      di_ready_o => di_ready_s,
--      di_i => di_s,

      tmds_o => tmds_s);

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 800 ns,
      reset_n_o(0) => reset_n_async,
      clock_o(0) => clock,
      done_i => done
      );
  
end;
