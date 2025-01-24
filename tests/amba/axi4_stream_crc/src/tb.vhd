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
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 1);

  signal input_s, output_s: bus_t;

  constant cfg_c: config_t := config(4, last => true);

  constant crc_c: crc_params_t := crc_params(
    poly => x"104c11db7",
    init => x"0",
    complement_input => false,
    complement_state => true,
    byte_bit_order => BIT_ORDER_ASCENDING,
    spill_order => EXP_ORDER_DESCENDING,
    byte_order => BYTE_ORDER_INCREASING
    );

  constant test_vector_c : byte_string := from_hex(""
    & "0180c2000001000f" & "5d30415088080001"
    & "ffff000000000000" & "0000000000000000"
    & "0000000000000000" & "0000000000000000"
    & "0000000000000000" & "00000000");
  
begin

  tx: process
  begin
    done_s(0) <= '0';

    input_s.m <= transfer_defaults(cfg_c);

    wait for 100 ns;

    packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                packet => test_vector_c);

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  rx: process
    variable rx_data : byte_stream;
    variable id, user, dest : std_ulogic_vector(1 to 0);
  begin
    done_s(1) <= '0';

    output_s.s <= accept(cfg_c, false);

    wait for 100 ns;

    packet_receive(cfg_c, clock_s, output_s.m, output_s.s,
                   packet => rx_data,
                   id => id,
                   user => user,
                   dest => dest);

    assert_equal("data",
                 rx_data.all(0 to test_vector_c'length-1),
                 test_vector_c,
                 failure);

    assert_equal("crc valid",
                 crc_is_valid(crc_c, rx_data.all),
                 true,
                 failure);

    wait for 500 ns;

    done_s(1) <= '1';
    wait;
  end process;

  dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "IN"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => input_s
      );

  dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    generic map(
      config_c => cfg_c,
      prefix_c => "OUT"
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      bus_i => output_s
      );
  
  dut: nsl_amba.stream_crc.axi4_stream_crc_adder
    generic map(
      config_c => cfg_c,
      crc_c => crc_c
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
