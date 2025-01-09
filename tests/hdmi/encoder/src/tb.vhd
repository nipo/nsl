library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spdif, nsl_simulation, nsl_line_coding, nsl_clocking, nsl_hdmi, nsl_color, nsl_data, nsl_dvi, nsl_math;
use nsl_spdif.serdes.all;
use nsl_spdif.blocker.all;
use nsl_simulation.assertions.all;
use nsl_color.rgb.all;
use nsl_data.bytestream.all;
use nsl_line_coding.tmds.all;
use nsl_dvi.dvi.all;
use nsl_hdmi.hdmi.all;
use nsl_hdmi.encoder.all;
use nsl_math.fixed.all;

entity tb is
end tb;

architecture arch of tb is

  signal di_s: data_island_t;
  signal di_ready_s, di_valid_s: std_ulogic;
  signal sof_s, sol_s, pixel_ready_s: std_ulogic;
  signal pixel_s : byte_string(0 to 2);
  signal tmds_s : symbol_vector_t;
  
  signal reset_n, reset_n_async, clock: std_ulogic;
  signal done: std_ulogic_vector(0 to 0);
  signal ok : std_ulogic;
  signal s_transmitter_tick : std_ulogic;

  constant c_period: ufixed(4 downto -5) := to_ufixed(7.89, 4, -5);
  signal s_period: nsl_math.fixed.ufixed(5 downto -8);

  type data_t is
  record
    a, b: channel_data_t;
  end record;    

  signal s_tx_ready : std_ulogic;
  signal s_tx_block_ready : std_ulogic;
  signal s_tx_user, s_tx_channel_status : std_ulogic_vector(0 to 191);
  signal s_tx_data : data_t;

  constant v_fp_m1_c : unsigned(3-1 downto 0) := to_unsigned(5, 3);
  constant v_sync_m1_c : unsigned(3-1 downto 0) := to_unsigned(5, 3);
  constant v_bp_m1_c : unsigned(5-1 downto 0) := to_unsigned(20, 5);
  constant v_act_m1_c : unsigned(10-1 downto 0) := to_unsigned(720, 10);
  constant h_fp_m1_c : unsigned(9-1 downto 0) := to_unsigned(440, 9);
  constant h_sync_m1_c : unsigned(6-1 downto 0) := to_unsigned(40, 6);
  constant h_bp_m1_c : unsigned(8-1 downto 0) := to_unsigned(220, 8);
  constant h_act_m1_c : unsigned(11-1 downto 0) := to_unsigned(1280, 11);

  procedure spdif_frame_put(signal io_clk, io_spdif_ready : in std_ulogic;
                            signal io_data : out data_t;
                            constant audio_a, audio_b: unsigned(19 downto 0);
                            constant aux_a, aux_b: unsigned(3 downto 0)) is
  begin
    io_data.a.valid <= '1';
    io_data.a.audio <= audio_a;
    io_data.a.aux <= aux_a;
    io_data.b.valid <= '1';
    io_data.b.audio <= audio_b;
    io_data.b.aux <= aux_b;

    to_accepted: while true
    loop
      wait until rising_edge(io_clk);
      if io_spdif_ready = '1' then
        exit to_accepted;
      end if;
    end loop;
    wait until falling_edge(io_clk);
  end procedure;
  
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
        when 0 => pixel_s <= (x"ff", x"00", x"00");
        when 1 => pixel_s <= (x"00", x"ff", x"00");
        when 2 => pixel_s <= (x"00", x"00", x"ff");
        when others => pixel_s <= (x"00", x"00", x"00");
      end case;

      wait until rising_edge(clock);
    end loop;

    done(0) <= '1';

    wait;
  end process;
  
--  stim: process
--  begin
--    while true
--    loop
--      wait until rising_edge(clock);
--      if reset_n = '1' then
--        exit;
--      end if;
--    end loop;
--
--    s_tx_user <= (others => '0');
--    s_tx_channel_status <= (others => '0');
--
--    for i in 0 to 3
--    loop
--      s_tx_channel_status(8 to 15) <= std_ulogic_vector(to_unsigned(i, 8));
--      
--      for frame in 0 to 191
--      loop
--        spdif_frame_put(clock, s_tx_ready, s_tx_data,
--                        to_unsigned(frame, 20),
--                        to_unsigned(16#da000# + frame, 20),
--                        x"a", x"b");
--        wait for 4 ns;
--      end loop;
--    end loop;
--
--    wait;
--  end process;

  stim: process
   begin
    di_valid_s <= '0';

    wait for 5000 ns;

     while true
     loop
      
       wait until rising_edge(clock);
 
      di_valid_s <= '1';
      di_s.packet_type <= x"82";
      di_s.hb(1) <= x"02";
      di_s.hb(2) <= x"0d";
      di_s.pb <= from_hex("985d6800120000000000000000000000000000000000000000000000");
 
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

--  freq_gen: nsl_clocking.generator.tick_generator
--    port map(
--      reset_n_i => reset_n,
--      clock_i => clock,
--      period_i => c_period,
--      tick_o => s_transmitter_tick
--      );
--  
--  spdif_encoder: nsl_hdmi.audio.hdmi_spdif_di_encoder
--    port map(
--      reset_n_i => reset_n,
--      clock_i => clock,
--
--      spdif_tick_i => s_transmitter_tick,
--
--      block_ready_o => s_tx_block_ready,
--      block_user_i => s_tx_user,
--      block_channel_status_i => s_tx_channel_status,
--
--      ready_o => s_tx_ready,
--      a_i => s_tx_data.a,
--      b_i => s_tx_data.b,
--
--      sof_i => sof_s,
--
--      di_valid_o => di_valid_s,
--      di_ready_i => di_ready_s,
--      di_o => di_s
--      );
  
  enc: nsl_hdmi.encoder.hdmi_13_encoder
    port map(
      pixel_clock_i => clock,
      reset_n_i => reset_n,

      v_fp_m1_i => v_fp_m1_c,
      v_sync_m1_i => v_sync_m1_c,
      v_bp_m1_i => v_bp_m1_c,
      v_act_m1_i => v_act_m1_c,

      h_fp_m1_i => h_fp_m1_c,
      h_sync_m1_i => h_sync_m1_c,
      h_bp_m1_i => h_bp_m1_c,
      h_act_m1_i => h_act_m1_c,

      sof_o => sof_s,
      sol_o => sol_s,
      pixel_ready_o => pixel_ready_s,
      pixel_i => pixel_s,

      di_valid_i => di_valid_s,
      di_ready_o => di_ready_s,
      di_i => di_s,

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
