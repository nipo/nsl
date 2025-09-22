library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_data, nsl_memory, nsl_amba, nsl_logic, nsl_amba;
use nsl_amba.axi4_stream.all;
use nsl_data.text.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_data.prbs.all;
use nsl_amba.axi4_stream.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 1);

  constant cfg_c: config_t := config(1, last => false);
  signal input_s, input_paced_s, output_paced_s, output_s: bus_t;

  constant state_c : prbs_state(30 downto 0) := x"deadbee"&"111";
  constant test_vector_c: byte_string := prbs_byte_string(state_c, prbs31, 1024);

begin
  
  tx: process
  begin
    done_s(0) <= '0';

    input_s.m <= transfer_defaults(cfg_c);

    wait for 100 ns;

    wait until falling_edge(clock_s);

    packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                packet => test_vector_c);

    wait for 500 ns;

    done_s(0) <= '1';
    wait;
  end process;

  rx: process
    variable rx_data : byte_string(test_vector_c'range);
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
                 rx_data,
                 test_vector_c,
                 failure);

    wait for 500 ns;

    done_s(1) <= '1';
    wait;
  end process;
  
  input_pacer: nsl_amba.axi4_stream.axi4_stream_pacer
    generic map(
      config_c => cfg_c,
      probability_c => 0.95
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => input_s.m,
      in_o => input_s.s,

      out_o => input_paced_s.m,
      out_i => input_paced_s.s
      );

  output_pacer: nsl_amba.axi4_stream.axi4_stream_pacer
    generic map(
      config_c => cfg_c,
      probability_c => 0.5
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      in_i => output_paced_s.m,
      in_o => output_paced_s.s,

      out_o => output_s.m,
      out_i => output_s.s
      );
  
  dut: block is
    signal rom_data_s: byte;
    signal rom_addr_s: unsigned(7 downto 0);
    signal out_data_neg_s, out_sideband_s: byte;
    signal rom_enable_s: std_ulogic;
    signal in_data_s, out_data_s: byte;
    signal in_valid_s, in_ready_s, out_valid_s, out_ready_s: std_ulogic;

    function rom_init return byte_string is
      variable ret: byte_string(0 to 255);
    begin
      for i in ret'range
      loop
        ret(i) := to_byte(255-i);
      end loop;
      
      return ret;
    end function;
  begin
    in_data_s <= bytes(cfg_c, input_paced_s.m)(0);
    in_valid_s <= to_logic(is_valid(cfg_c, input_paced_s.m));
    input_paced_s.s <= accept(cfg_c, in_ready_s = '1');
    
    streamer: nsl_memory.streamer.memory_streamer
      generic map(
        addr_width_c => rom_addr_s'length,
        data_width_c => rom_data_s'length,
        memory_latency_c => 1,
        sideband_width_c => rom_data_s'length
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        addr_valid_i => in_valid_s,
        addr_ready_o => in_ready_s,
        addr_i => unsigned(in_data_s),
        sideband_i => in_data_s,

        data_valid_o => out_valid_s,
        data_ready_i => out_ready_s,
        data_o => out_data_neg_s,
        sideband_o => out_sideband_s,

        mem_enable_o => rom_enable_s,
        mem_address_o => rom_addr_s,
        mem_data_i => rom_data_s
        );

    out_data_s <= not out_data_neg_s;

    checker: process(clock_s) is
    begin
      if rising_edge(clock_s) and out_valid_s = '1' then
        assert_equal("sideband", out_data_s, out_sideband_s, failure);
      end if;
    end process;
    
    rom: nsl_memory.rom.rom_bytes
      generic map(
        word_addr_size_c => rom_addr_s'length,
        word_byte_count_c => rom_data_s'length / 8,
        contents_c => rom_init,
        little_endian_c => true
        )
      port map(
        clock_i => clock_s,
        read_i => rom_enable_s,
        address_i => rom_addr_s,
        data_o => rom_data_s
        );

    output_paced_s.m <= transfer(cfg_c,
                                 value => unsigned(out_data_s),
                                 valid => out_valid_s = '1');
    out_ready_s <= to_logic(is_ready(cfg_c, output_paced_s.s));
  end block;  

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
