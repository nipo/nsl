library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_line_coding, nsl_simulation, nsl_logic, nsl_data, nsl_clocking;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_logic.logic.all;
use nsl_logic.bool.all;
use nsl_line_coding.ibm_8b10b.all;

entity tb is
end tb;

architecture arch of tb is

  constant enc_impl : string := "logic";
  constant dec_impl : string := "logic";
  constant inject_errors : boolean := true;
  
  function latency(e, d: string) return integer
  is
    variable ret : integer := 0;
  begin
    if e = "logic" then
      ret := ret + 2;
    elsif e = "rom" then
      ret := ret + 1;
    elsif e = "spec" then
      ret := ret + 1;
    else
      report "Unknown implementation: " & e
        severity failure;
    end if;
    
    if d = "logic" then
      ret := ret + 2;
    elsif d = "rom" then
      ret := ret + 2;
    elsif d = "spec" then
      ret := ret + 1;
    else
      report "Unknown implementation: " & d
        severity failure;
    end if;

    return ret;
  end function;

  constant latency_c : natural := latency(enc_impl, dec_impl);
  signal done : std_ulogic_vector(0 to 0);
  signal reset_n, reset_n_async, clock : std_ulogic;
  signal coded_tx, coded_err, coded_rx : code_word_t;
  signal input_data, delayed_data, output_data : data_t;
  signal ok, dec_err, disp_err, err_inj : std_ulogic;
  signal err_permitted : natural range 0 to latency_c+4;
  signal stim_gen: prbs_state(30 downto 0);
  signal err_gen: prbs_state(22 downto 0);

begin

  runner: process
  begin
    done <= "0";
    wait for 1 ms;
    done <= "1";
    wait;
  end process;

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_async,
      data_o => reset_n,
      clock_i => clock
      );

  stim: process(reset_n, clock)
  begin
    if reset_n = '0' then
      coded_err <= (others => '0');
      err_inj <= '0';
      stim_gen <= (others => '1');
      err_gen <= (others => '1');
    elsif rising_edge(clock) then
      if err_permitted /= 0 then
        err_permitted <= err_permitted - 1;
      end if;

      coded_err <= (others => '0');
      err_inj <= '0';
      stim_gen <= prbs_forward(stim_gen, prbs31, 15);
      err_gen <= prbs_forward(err_gen, prbs23, 10);
      input_data.data <= std_ulogic_vector(stim_gen(7 downto 0));
      input_data.control <= to_logic(stim_gen(10 downto 8) = "000"
                                     and control_exists(to_integer(unsigned(stim_gen(4 downto 0))),
                                                        to_integer(unsigned(stim_gen(7 downto 5)))));

      if err_gen(7 downto 0) = x"00" and inject_errors then
        err_inj <= '1';
        coded_err(to_integer(unsigned(err_gen(13 downto 8))) mod 10) <= '1';
        err_permitted <= latency_c+4;
      end if;
    end if;
  end process;

  checker: process(clock)
    variable since_reset: integer;
  begin
    if falling_edge(clock) then
      ok <= '1';
      if reset_n = '0' then
        since_reset := 0;
      elsif since_reset > 10 then
        ok <= to_logic(((delayed_data = output_data)
                       and dec_err = '0'
                       and disp_err = '0')
                       or err_permitted /= 0);

        if ok = '0' then
          nsl_simulation.assertions.assert_equal(
            "data",
            to_string(delayed_data), to_string(output_data),
            failure);
        end if;
      else
        since_reset := since_reset + 1;
      end if;
    end if;
  end process;

  pipe: nsl_clocking.intradomain.intradomain_multi_reg
    generic map(
      cycle_count_c => latency_c,
      data_width_c => delayed_data.data'length+1
      )
    port map(
      clock_i => clock,
      data_i(input_data.data'length-1 downto 0) => input_data.data,
      data_i(input_data.data'length) => input_data.control,
      data_o(delayed_data.data'length-1 downto 0) => delayed_data.data,
      data_o(delayed_data.data'length) => delayed_data.control
      );

  encoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_encoder
    generic map(
      implementation_c => enc_impl
      )
    port map(
      clock_i => clock,
      reset_n_i => reset_n,

      data_i => input_data,
      data_o => coded_tx
      );

  coded_rx <= coded_tx xor coded_err;
  
  decoder: nsl_line_coding.ibm_8b10b.ibm_8b10b_decoder
    generic map(
      implementation_c => dec_impl
      )
    port map(
      clock_i => clock,
      reset_n_i => reset_n,

      data_i => coded_rx,

      data_o => output_data,
      code_error_o => dec_err,
      disparity_error_o => disp_err
      );
  
  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done'length
      )
    port map(
      clock_period(0) => 100 ns,
      reset_duration(0) => 100 ns,
      reset_n_o(0) => reset_n_async,
      clock_o(0) => clock,
      done_i => done
      );

end;
