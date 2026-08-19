library ieee;
use ieee.std_logic_1164.all;

library nsl_data, nsl_simulation, nsl_line_coding;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_line_coding.ibm_8b10b.all;
use nsl_line_coding.ibm_8b10b_stream.all;

entity tb is
end tb;

architecture arch of tb is

  constant ctxt: log_context := "Idle filter";

  constant cfg_c: config_t := config(2, strobe => true, last => true);

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 0);

  signal input_s, output_s: bus_t;

  -- Mixes idles to strip, data words, and a D28.5 sharing the K28.5
  -- data byte with control cleared, which must not be stripped.
  constant a_c: data_vector(0 to 5) := (
    data(1, 0), K28_5, data(28, 5), data(3, 0), K28_5, data(4, 0));

  -- Idle on a lane that is already not strobed at input.
  constant b_c: data_vector(0 to 1) := (data(5, 0), K28_5);

  -- Idles only.
  constant c_c: data_vector(0 to 1) := (K28_5, K28_5);

begin

  sender: process
  begin
    input_s.m <= transfer_defaults(cfg_c);

    wait for 40 ns;

    packet_send(cfg_c, clock_s, input_s.s, input_s.m, packet => a_c);
    packet_send(cfg_c, clock_s, input_s.s, input_s.m, packet => b_c, strobe => "10");
    packet_send(cfg_c, clock_s, input_s.s, input_s.m, packet => c_c);

    wait;
  end process;

  receiver: process
    variable a_v: data_vector(0 to 5);
    variable a_strobe_v: std_ulogic_vector(0 to 5);
    variable bc_v: data_vector(0 to 1);
    variable bc_strobe_v: std_ulogic_vector(0 to 1);
  begin
    done_s(0) <= '0';
    output_s.s <= accept(cfg_c, false);

    wait for 40 ns;

    packet_receive(cfg_c, clock_s, output_s.m, output_s.s, a_v, a_strobe_v);

    assert_equal(ctxt, "a strobe", a_strobe_v, "101101", FAILURE);
    for i in a_c'range
    loop
      assert_equal(ctxt, "a word "&to_string(i), to_string(a_v(i)), to_string(a_c(i)), FAILURE);
    end loop;

    packet_receive(cfg_c, clock_s, output_s.m, output_s.s, bc_v, bc_strobe_v);

    assert_equal(ctxt, "b strobe", bc_strobe_v, "10", FAILURE);
    for i in b_c'range
    loop
      assert_equal(ctxt, "b word "&to_string(i), to_string(bc_v(i)), to_string(b_c(i)), FAILURE);
    end loop;

    packet_receive(cfg_c, clock_s, output_s.m, output_s.s, bc_v, bc_strobe_v);

    assert_equal(ctxt, "c strobe", bc_strobe_v, "00", FAILURE);
    for i in c_c'range
    loop
      assert_equal(ctxt, "c word "&to_string(i), to_string(bc_v(i)), to_string(c_c(i)), FAILURE);
    end loop;

    log_info(ctxt, "done");
    done_s(0) <= '1';
    wait;
  end process;

  filter: nsl_line_coding.ibm_8b10b_stream.ibm_8b10b_stream_idle_filter
    generic map(
      config_c => cfg_c,
      idle_c => K28_5
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => input_s.m,
      in_o => input_s.s,

      out_o => output_s.m,
      out_i => output_s.s
      );

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
