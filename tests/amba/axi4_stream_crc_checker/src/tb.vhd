library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_logic, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_logic.bool.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;

entity tb is
end tb;

architecture arch of tb is

  function packet_data_with_crc(crc_param : crc_params_t; data : byte_string; crc_error : boolean := false) return byte_string
  is
    constant s : crc_state_t := crc_update(crc_param,
                                           crc_init(crc_param),
                                           data);
  begin
    if crc_error then
      return data & crc_spill(crc_param, crc_init(crc_param));
    else
      return data & crc_spill(crc_param, s);
    end if;
  end function;

  procedure frame_queue_check(
    variable root: in frame_queue_root_t;
    variable frm: in frame_t;
    variable in_error : boolean;
    constant crc_c : crc_params_t;
    signal crc_valid : in std_ulogic;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable rx_frm: frame_t;
    variable ref_frm: frame_t := frm;
    variable crc_is_valid_v : boolean; 
  begin
    frame_queue_get(root, rx_frm, dt, timeout, sev);
    assert rx_frm.data.all = ref_frm.data.all
      and rx_frm.id = ref_frm.id
      and rx_frm.user = ref_frm.user
      and rx_frm.dest = ref_frm.dest
      report "Bad frame received, expected "&to_string(ref_frm.data.all)&", received "&to_string(rx_frm.data.all)
      severity sev;
    assert (crc_valid = to_logic(crc_is_valid(crc_c, rx_frm.data.all) and (not in_error)))
      report "Bad crc received, expected "&to_string(ref_frm.data.all)&", received "&to_string(rx_frm.data.all)
      severity sev;
    deallocate(rx_frm.data);
    deallocate(ref_frm.data);
  end procedure;

  procedure frame_queue_check_io(
    variable root_master: in frame_queue_root_t;
    variable root_slave: in frame_queue_root_t;
    variable frm: in frame_t;
    variable in_error : boolean;
    constant crc_c : crc_params_t;
    signal crc_valid : in std_ulogic;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable c : frame_t;
  begin
    frame_clone(c, frm);
    frame_queue_put(root_master, c);
    frame_queue_check(root_slave, frm, in_error, crc_c, crc_valid, dt, timeout, sev);
  end procedure;

  procedure frame_queue_check_io(
    variable root_master: in frame_queue_root_t;
    variable root_slave: in frame_queue_root_t;
    variable in_error : boolean;
    constant crc_c : crc_params_t;
    constant data: byte_string := null_byte_string;
    constant dest: std_ulogic_vector := na_suv;
    constant id:   std_ulogic_vector := na_suv;
    constant user: std_ulogic_vector := na_suv;
    signal crc_valid : in std_ulogic;
    dt : in time := 10 ns;
    timeout : in time := 100 us;
    sev: severity_level := failure)
  is
    variable frm: frame_t := frame(data, dest, id, user);
  begin
    frame_queue_check_io(root_master, root_slave, frm, in_error, crc_c, crc_valid, dt, timeout, sev);
  end procedure;
     
  constant crc_c : crc_params_t := crc_params(
    init             => "",
    poly             => x"104c11db7",
    complement_input => false,
    complement_state => true,
    byte_bit_order   => BIT_ORDER_ASCENDING,
    spill_order      => EXP_ORDER_DESCENDING,
    byte_order       => BYTE_ORDER_INCREASING
    );

  constant nbr_scenario : integer := 3;
  constant config_c : stream_cfg_array_t :=
    (0 => config(1, last => true),
     1 => config(2, last => true),
     2 => config(4, last => true));

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario - 1);

begin

  gen_scenarios : for i in 0 to nbr_scenario-1 generate
    signal crc_valid_s : std_ulogic;
    signal crc_valid_r_s : std_ulogic := '0';
    shared variable master_q, slave_q : frame_queue_root_t;
    signal input_s, output_s, output_paced_s:  bus_t;
    signal in_error_s : std_ulogic;
    shared variable in_error_v : boolean := false;
  begin 
    tx: process
      variable frame_byte_count : integer := 0;
      variable state_v : prbs_state(30 downto 0) := x"deadbee" & "111";
      variable crc_error_v : boolean;
      variable number_of_ko_pkt_v, number_of_ok_pkt_v, number_of_in_error_v : integer := 0;
    begin
      done_s(i) <= '0';
      frame_queue_init(master_q);
      frame_queue_init(slave_q);

      wait for 100 ns;

      log_info("INFO: Playing...");

      for stream_beat_count in 1 to 100
      loop
        crc_error_v := (stream_beat_count mod 5) = 0;
        in_error_v := (stream_beat_count mod 7) = 0;
 
        frame_byte_count := stream_beat_count * config_c(i).data_width;
        frame_queue_check_io(root_master => master_q, 
                            root_slave  => slave_q, 
                            in_error => in_error_v,
                            crc_valid => crc_valid_r_s,
                            crc_c => crc_c,
                            data => packet_data_with_crc(crc_c, prbs_byte_string(state_v, prbs31, frame_byte_count), crc_error_v));

        if crc_error_v then
          number_of_ko_pkt_v := number_of_ko_pkt_v + 1;
        else
          number_of_ok_pkt_v := number_of_ok_pkt_v + 1;
        end if;

        if in_error_v then
          number_of_in_error_v := number_of_in_error_v + 1;
        end if;

        state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
      end loop;

      log_info("INFO: Number of inserted error : " & to_string(number_of_ko_pkt_v));
      log_info("INFO: Number of ok packets : " & to_string(number_of_ok_pkt_v));
      log_info("INFO: Number of in error packets : " & to_string(number_of_in_error_v));

      wait for 500 ns;

      done_s(i) <= '1';
      wait;
    end process;

    crc_valid_catcher_fixed: process(clock_s) is
    begin 
      if rising_edge(clock_s) then
        -- Capture crc_valid when we have a valid last beat
        if is_valid(config_c(i), output_s.m) and is_ready(config_c(i), output_s.s) 
          and is_last(config_c(i), output_s.m) then
          crc_valid_r_s <= crc_valid_s;
        end if;
      end if;
    end process;

    master_proc: process is
    begin
      input_s.m <= transfer_defaults(config_c(i));
      wait for 40 ns;
      frame_queue_master(config_c(i), master_q, clock_s, input_s.s, input_s.m);
    end process;

    in_error_proc: process is
    begin
      in_error_s <= to_logic(in_error_v);
      wait until rising_edge(clock_s);
    end process;

    slave_proc: process is
    begin
      output_paced_s.s <= accept(config_c(i), false);
      wait for 40 ns;
      frame_queue_slave(config_c(i), slave_q, clock_s, output_paced_s.m, output_paced_s.s);
    end process;

    -- dumper_in: nsl_amba.axi4_stream.axi4_stream_dumper
    --   generic map(
    --     config_c => config_c(i),
    --     prefix_c => "IN"
    --     )
    --   port map(
    --     clock_i => clock_s,
    --     reset_n_i => reset_n_s,

    --     bus_i => input_s
    --     );

    -- dumper_out: nsl_amba.axi4_stream.axi4_stream_dumper
    --   generic map(
    --     config_c => config_c(i),
    --     prefix_c => "OUT"
    --     )
    --   port map(
    --     clock_i => clock_s,
    --     reset_n_i => reset_n_s,

    --     bus_i => output_paced_s
    --     );
    
    dut: nsl_amba.stream_crc.axi4_stream_crc_checker
      generic map(
        config_c => config_c(i),
        crc_c => crc_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => input_s.m,
        in_o => input_s.s,
        in_error_i => in_error_s,

        out_o => output_s.m,
        out_i => output_s.s,
        crc_valid_o => crc_valid_s
        );
    
    pkt_pacer : nsl_amba.stream_traffic.axi4_stream_pacer
      generic map(
          config_c               => config_c(i),
          probability_denom_l2_c => 30,
          probability_c          => 0.2
      )
      port map(
          reset_n_i => reset_n_s,
          clock_i   => clock_s,

          in_i => output_s.m,
          in_o => output_s.s,

          out_o => output_paced_s.m,
          out_i => output_paced_s.s
          );

  end generate;

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
