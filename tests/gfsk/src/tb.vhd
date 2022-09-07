library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb is
end tb;

library nsl_sdr, nsl_math, nsl_simulation, nsl_signal_generator, nsl_bnoc, nsl_data, nsl_ble, nsl_serdes, nsl_logic;
use nsl_simulation.logging.all;
use nsl_data.text.all;
use nsl_data.crc.all;
use nsl_math.fixed.all;
use nsl_data.bytestream.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.testing.all;
use nsl_ble.ble.all;

architecture arch of tb is

  constant symbol_per_s : integer := 1e6;
  constant chan0_freq_c : real := 98.0e6;
  constant chan_sep_c : real := -2.0e6;
  constant fd0_c : real := -250.0e3;
  constant fd_sep_c : real := 500.0e3;
  
  constant fs : integer := 240e6;
  constant internal_clock_freq : integer := 240e6;

  signal s_clock : std_ulogic;
  signal s_reset_n : std_ulogic;

  signal s_channel: unsigned(5 downto 0);
  signal s_mi: unsigned(0 downto 0);
  signal s_mi_opp: unsigned(0 downto 0);
  signal s_box_freq, s_rc_freq, s_fsk_freq : ufixed(-1 downto -16);
  signal s_box_freq_r, s_rc_freq_r, s_fsk_freq_r : real;
  signal s_done : std_ulogic_vector(0 to 0);
  signal s_box_v, s_rc_v, s_modem_running : std_ulogic;
  signal s_modulated : sfixed(1 downto -10);

  function pre return byte_string is
  begin
    if symbol_per_s = 2e6 then
      return preamble_c & preamble_c;
    else
      return preamble_c;
    end if;
  end function;

  type framed_io is
  record
    cmd, rsp : nsl_bnoc.framed.framed_bus;
  end record;

  signal comm_modem : framed_io;

begin

  box_conv: process(s_box_freq) is
  begin
    s_box_freq_r <= to_real(s_box_freq) * real(fs);
  end process;

  rc_conv: process(s_rc_freq) is
  begin
    s_rc_freq_r <= to_real(s_rc_freq) * real(fs);
  end process;

  fsk_conv: process(s_fsk_freq) is
  begin
    s_fsk_freq_r <= to_real(s_fsk_freq) * real(fs);
  end process;

  s_box_v <= '1' when abs(s_box_freq_r - s_fsk_freq_r) <= 400.0e3 and abs(s_box_freq_r - s_fsk_freq_r) >= 185.0e3 else '0';
  s_rc_v <= '1' when abs(s_rc_freq_r - s_fsk_freq_r) <= 400.0e3 and abs(s_rc_freq_r - s_fsk_freq_r) >= 185.0e3 else '0';
  
  st: process
    constant pdu: byte_string := from_hex("4225"
                                          &"3B6FB4EC02E5"
                                          &"1EFFFFFF0102030405060708090A0B0C0D0E0F101112131415161718191A1B");
    constant pkt: byte_string := pdu & crc_spill(crc_params_c, crc_update(crc_params_c, crc_init(crc_params_c), pdu));
    constant frame: byte_string := pre & advertising_access_address_c & whitened(pkt, "1100101");
  begin
    comm_modem.cmd.req <= framed_req_idle_c;
    comm_modem.rsp.ack <= framed_ack_blackhole_c;
    s_done <= "0";
    s_channel <= to_unsigned(0, 6);

    wait for 40 us;

    framed_put(comm_modem.cmd.req, comm_modem.cmd.ack, s_clock, frame);
    
    wait for 40 us;
      
    s_done <= "1";
    wait;
  end process;

  modem: nsl_serdes.framed.framed_serializer
    generic map(
      clock_i_hz_c => internal_clock_freq,
      bit_rate_c => integer(symbol_per_s)
      )
    port map(
      clock_i  => s_clock,
      reset_n_i => s_reset_n,
      
      cmd_i => comm_modem.cmd.req,
      cmd_o => comm_modem.cmd.ack,
      rsp_o => comm_modem.rsp.req,
      rsp_i => comm_modem.rsp.ack,

      running_o => s_modem_running,
      serial_o => s_mi(0)
      );

  s_mi_opp <= not s_mi;
  
  fgrc: nsl_sdr.gfsk.gfsk_frequency_plan
    generic map(
      fs_c => real(fs),
      clock_i_hz_c => internal_clock_freq,
      channel_count_c => 40,
      channel_0_center_hz_c => chan0_freq_c,
      channel_separation_hz_c => chan_sep_c,
      symbol_rate_c => real(symbol_per_s),
      bt_c => 0.5,
      gfsk_method_c => "rc"
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      channel_i => s_channel,
      symbol_i => s_mi_opp,
      phase_increment_o => s_rc_freq
      );

  fgbox: nsl_sdr.gfsk.gfsk_frequency_plan
    generic map(
      fs_c => real(fs),
      clock_i_hz_c => internal_clock_freq,
      channel_count_c => 40,
      channel_0_center_hz_c => chan0_freq_c,
      channel_separation_hz_c => chan_sep_c,
      symbol_rate_c => real(symbol_per_s),
      bt_c => 0.5,
      gfsk_method_c => "box"
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      channel_i => s_channel,
      symbol_i => s_mi_opp,
      phase_increment_o => s_box_freq
      );

  cf: nsl_sdr.fsk.fsk_frequency_plan
    generic map(
      fs_c => real(fs),
      channel_count_c => 40,
      channel_0_center_hz_c => chan0_freq_c,
      channel_separation_hz_c => chan_sep_c,
      fd_0_hz_c => fd0_c,
      fd_separation_hz_c => fd_sep_c
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,

      channel_i => s_channel,
      symbol_i => s_mi_opp,
      phase_increment_o => s_fsk_freq
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => s_done'length
      )
    port map(
      clock_period(0) => 1000000 ps / (internal_clock_freq / 1000000),
      reset_duration(0) => 1 us,
      reset_n_o(0) => s_reset_n,
      clock_o(0) => s_clock,
      done_i => s_done
      );

  nco: nsl_signal_generator.nco.nco_sinus
    generic map(
      implementation_c => "cordic",
      trim_bits_c => 0
      )
    port map(
      clock_i => s_clock,
      reset_n_i => s_reset_n,
      angle_increment_i => s_rc_freq,
      value_o => s_modulated
      );

  output: process is
    variable v: integer;
    type int_file is file of integer;
    variable sd: signed(31 downto 0);
    file fd : int_file;
  begin
    file_open(fd, "modulation.bin", WRITE_MODE);
    while true
    loop
      wait until rising_edge(s_clock);
      sd(15 downto 0) := resize(signed(to_unsigned(s_modulated)), 16);
      wait until rising_edge(s_clock);
      sd(31 downto 16) := resize(signed(to_unsigned(s_modulated)), 16);
      v := to_integer(sd);
      write(fd, v);
    end loop;
  end process;
  
end;
