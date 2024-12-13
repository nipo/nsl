library ieee;
use ieee.std_logic_1164.all;

library nsl_line_coding, nsl_simulation, nsl_logic, nsl_data, nsl_clocking, nsl_io;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_logic.logic.all;
use nsl_logic.bool.all;
use nsl_line_coding.ibm_8b10b.all;
use nsl_io.serdes.all;

entity tb is
end tb;

architecture arch of tb is

  signal done_s : std_ulogic_vector(0 to 0);
  signal tx_reset_n_s, rx_reset_n_s, rx_resync_n_s, clock_s, bit_clock_s : std_ulogic;

  signal tx_data_s, rx_data_s: data_t;
  signal tx_10b_s, rx_10b_s: code_word_t;
  signal rx_code_err_s, rx_disp_err_s,
    rx_serial_delayed_s, rx_delay_shift_s, rx_delay_mark_s,
    rx_serdes_shift_s, rx_serdes_mark_s, rx_valid_s, rx_ready_s: std_ulogic;
  
  signal tx_serial_s, rx_serial_s : std_ulogic;

begin

  tx_stim: process
  begin
    wait for 1 ns;
    while done_s(0) /= '1'
    loop
      wait until rising_edge(clock_s);
      tx_data_s <= K28_1;
    end loop;
    wait;
  end process;
  
  tx: nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
    generic map(
      implementation_c => "lut"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => tx_reset_n_s,

      data_i => tx_data_s,
      data_o => tx_10b_s
      );

  serializer: nsl_io.serdes.serdes_ddr10_output
    port map(
      word_clock_i => clock_s,
      bit_clock_i => bit_clock_s,
      reset_n_i => tx_reset_n_s,
      parallel_i => tx_10b_s,
      serial_o => tx_serial_s
      );

  propagate: process
  begin
    while true
    loop
      wait until tx_serial_s'event;
      rx_serial_s <= 'X' after 500 ps;
      wait for 800 ps;
      rx_serial_s <= tx_serial_s after 500 ps;
    end loop;
  end process;

  aligner: nsl_io.delay.input_delay_aligner
    port map(
      clock_i => clock_s,
      reset_n_i => rx_resync_n_s,

      delay_shift_o => rx_delay_shift_s,
      delay_mark_i => rx_delay_mark_s,
      serdes_shift_o => rx_serdes_shift_s,
      serdes_mark_i => rx_serdes_mark_s,

      valid_i => rx_valid_s,
      ready_o => rx_ready_s
      );

  delayer: nsl_io.delay.input_delay_variable
    port map(
      clock_i => clock_s,
      reset_n_i => rx_reset_n_s,
      mark_o => rx_delay_mark_s,
      shift_i => rx_delay_shift_s,
      data_i => rx_serial_s,
      data_o => rx_serial_delayed_s
      );
  
  deserializer: nsl_io.serdes.serdes_ddr10_input
    port map(
      word_clock_i => clock_s,
      bit_clock_i => bit_clock_s,
      reset_n_i => rx_reset_n_s,
      parallel_o => rx_10b_s,
      serial_i => rx_serial_delayed_s,
      bitslip_i => rx_serdes_shift_s,
      mark_o => rx_serdes_mark_s
      );

  rx_valid_s <= to_logic(rx_code_err_s = '0'
                         and rx_disp_err_s = '0'
                         and rx_data_s = K28_1);
  
  rx: nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
    generic map(
      implementation_c => "logic"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => rx_reset_n_s,

      data_i => rx_10b_s,
      data_o => rx_data_s,
      code_error_o => rx_code_err_s,
      disparity_error_o => rx_disp_err_s
      );

  rx_stim: process
  begin
    done_s(0) <= '0';
    rx_resync_n_s <= '0';
    rx_reset_n_s <= '0';
    wait for 40 ns;
    rx_reset_n_s <= '1';

    for retr in 0 to 3
    loop
      rx_resync_n_s <= '0';
      wait for 3 ns;
      rx_resync_n_s <= '1';

      wait for 10 ns;
      wait until rx_ready_s = '1';
      wait for 100 ns;
    end loop;

    wait for 50 ns;
    done_s(0) <= '1';
    wait;
  end process;
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 2,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      clock_period(1) => 2 ns,
      reset_duration(0) => 13 ns,
      reset_n_o(0) => tx_reset_n_s,
      clock_o(0) => clock_s,
      clock_o(1) => bit_clock_s,
      done_i => done_s
      );

end;
