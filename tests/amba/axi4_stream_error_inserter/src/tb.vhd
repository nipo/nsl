library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_memory, nsl_logic, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_data.prbs.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_amba.stream_traffic.all;
use nsl_logic.bool.all;

entity tb is
  generic(
    insert_error_c : boolean := false;
    scenario_c : natural := 0
  );
end tb;

architecture arch of tb is

  constant config_c : config_t := (config(1, keep => true, last => true));
  constant mtu_c : integer := 1500;
  constant probability_c : real := 0.1;
  constant probability_denom_l2_c : integer range 1 to 31 := 31;
  constant nbr_pkt_to_test : integer := 10000;
  constant nbr_scenario : integer := 2;
  constant max_errors_per_scenario_c : natural := 250;

  constant default_error_feedback : error_feedback_t := (
    error         => '0',
    pkt_index_ko  => (others => '0')
  );

  type stream_cfg_array_t is array (natural range <>) of config_t;
  type error_feedback_array_t is array (natural range <>) of error_feedback_t;
  type error_feedback_array_array_t is array (0 to nbr_scenario-1) of error_feedback_array_t(0 to max_errors_per_scenario_c-1);
  type frame_queue_root_array_t is array (natural range <>) of frame_queue_root_t;
  type integer_vector is array (natural range <>) of integer;
  
  -- Define per-scenario mode string
  type mode_array_t is array (0 to nbr_scenario-1) of string(1 to 6);
  constant mode_array_c : mode_array_t := ("MANUAL", "RANDOM");

  signal clock_i_s : std_ulogic;
  signal reset_n_i_s : std_ulogic;

  signal insert_error_s : boolean := false;
  signal byte_index_s : integer range 0 to config_c.data_width := 0;
  signal fifo_feed_back_valid_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to nbr_scenario-1);

  signal in_s, out_s  : bus_vector(0 to nbr_scenario-1);
  signal feed_back_s : error_feedback_array_t(0 to nbr_scenario-1);

  shared variable err_cnt_sh_v, global_frm_cnt_sh_v : integer_vector(0 to nbr_scenario-1) := (others => 0);
  shared variable master_q, slave_q, check_q : frame_queue_root_array_t(0 to nbr_scenario-1);
  shared variable error_feedback_array_all : error_feedback_array_array_t :=
      (others => (others => default_error_feedback));

  procedure frame_queue_assert_equal_error(constant cfg: config_t;
                                           variable a, b: in frame_queue_root_t;
                                           variable feed_back_array : in error_feedback_array_t;
                                           constant scenario : integer;
                                           constant mode : string;
                                           sev: severity_level := failure) 
  is
      variable a_frm, b_frm: frame_t;
      variable data_ko_ref : byte_string(0 to cfg.data_width - 1);
      variable beat_index_ko : integer := 0;
      variable index, index_ko, frm_cnt : natural := 0;
    begin
      while a.head /= null
      loop
        frame_queue_get(a, a_frm);
        assert b.head /= null
          report "Right queue is shorter than left one"
          severity sev;

        frame_queue_get(b, b_frm);
        global_frm_cnt_sh_v(scenario) := global_frm_cnt_sh_v(scenario) + 1;

        while index < a_frm.data'length
        loop
          if a_frm.data(index to index + cfg.data_width-1) /= b_frm.data(index to index + cfg.data_width-1) then
            data_ko_ref := b_frm.data(index to index + cfg.data_width-1);
            for byte_idx in 0 to cfg.data_width-1 loop
              if a_frm.data(index + byte_idx) /= b_frm.data(index + byte_idx) then
                index_ko := index + byte_idx;
                data_ko_ref(byte_idx)(0) := not data_ko_ref(byte_idx)(0);
                exit;
              end if;
            end loop;
            --
            if not(to_boolean(feed_back_array(err_cnt_sh_v(scenario)).error) and 
                   feed_back_array(err_cnt_sh_v(scenario)).pkt_index_ko = index_ko and 
                   a_frm.data(index to index + cfg.data_width-1) = data_ko_ref) then
                    assert false
                      report "Mismatch detected!" & LF &
                              "  Mode             : " & mode & LF &
                              "  Frame count      : " & integer'image(global_frm_cnt_sh_v(scenario)) & LF &
                              "  Byte index       : " & integer'image(index_ko) & LF &
                              "  Expected KO idx  : " & integer'image(to_integer(feed_back_array(err_cnt_sh_v(scenario)).pkt_index_ko)) & LF &
                              "  Error flag       : " & boolean'image(to_boolean(feed_back_array(err_cnt_sh_v(scenario)).error)) & LF &
                              "  Expected KO byte : " & to_string(data_ko_ref) & LF &
                              "  Actual byte      : " & to_string(a_frm.data(index to index + cfg.data_width-1))
                      severity sev;                    
            end if;
            err_cnt_sh_v(scenario) := (err_cnt_sh_v(scenario) + 1) mod feed_back_array'length;
          end if;

          index := index + cfg.data_width;
        end loop;

        index := 0;        
        
        deallocate(a_frm.data);
        deallocate(b_frm.data);
      end loop;

      assert b.head = null
        report "Left queue is shorter than right one pkt nbr : " & integer'image(global_frm_cnt_sh_v(scenario))
        severity sev;
    end procedure;

  function to_string(feedback : error_feedback_t) return string is
    constant line_sep : string := "+----------------------------+";
  begin

    return LF &
           "+----------------------------+" & LF &
           "|      ERROR FEEDBACK        |" & LF &
           line_sep & LF &
           "| Error Inserted : " & to_string(feedback.error) & LF &
           "| Packet Index KO: " & integer'image(to_integer(feedback.pkt_index_ko)) & LF &
           "+----------------------------+";
  end function;
begin

  gen_scenarios : for i in 0 to nbr_scenario-1 generate

    trx: process
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
      variable frame_byte_count: integer := 0;
      variable pkt_byte_size_v : integer := 0;
    begin
      frame_queue_init(master_q(i));
      frame_queue_init(slave_q(i));
      frame_queue_init(check_q(i));

      wait for 40 ns;

      for stream_beat_count in 1 to nbr_pkt_to_test
      loop

        pkt_byte_size_v := pkt_byte_size_v + 1;
        frame_byte_count := pkt_byte_size_v * config_c.data_width;

        if frame_byte_count > mtu_c then
          pkt_byte_size_v := 1;
          frame_byte_count := config_c.data_width;
        end if;
        
        frame_queue_put2(master_q(i), check_q(i), prbs_byte_string(state_v, prbs31, frame_byte_count));
        state_v := prbs_forward(state_v, prbs31, frame_byte_count * 8);
        frame_queue_drain(config_c, master_q(i), timeout => 1 ms);
        wait for 15 us;
        frame_queue_assert_equal_error(config_c, slave_q(i), check_q(i), error_feedback_array_all(i), i,  mode_array_c(i));
      end loop;
      wait;
    end process;

    error_inserter : nsl_amba.stream_traffic.stream_error_inserter
      generic map (
        config_c => config_c,
        probability_denom_l2_c => probability_denom_l2_c,
        probability_c => probability_c,
        mode_c => mode_array_c(i),
        mtu_c => mtu_c
        )
      port map(
        clock_i => clock_i_s,
        reset_n_i => reset_n_i_s,

        insert_error_i => insert_error_s,
        byte_index_i => byte_index_s,

        in_i => in_s(i).m,
        in_o => in_s(i).s,

        out_o => out_s(i).m,
        out_i => out_s(i).s,

        feed_back_o => feed_back_s(i)
        );

    master_proc: process is
    begin
      in_s(i).m <= transfer_defaults(config_c);
      wait for 40 ns;
      frame_queue_master(config_c, master_q(i), clock_i_s, in_s(i).s, in_s(i).m);
    end process;

    gen_manual_error_insertion : if mode_array_c(i) = "MANUAL" generate
      manual_error_insertion_proc : process(clock_i_s, reset_n_i_s)
      is
        variable state : prbs_state(30 downto 0) := x"deadbee"&"111";
        variable probability_v: unsigned(probability_denom_l2_c-1 downto 0);
        constant probability_threshold_c : unsigned(probability_denom_l2_c-1 downto 0) := to_unsigned(integer(probability_c * 2.0 ** probability_denom_l2_c), probability_v'length);
      begin
        if reset_n_i_s = '0' then
        elsif rising_edge(clock_i_s) then
          insert_error_s <= false;
          if is_ready(config_c, in_s(i).s) and is_valid(config_c, in_s(i).m) then
            probability_v := unsigned(prbs_bit_string(state, prbs31, probability_v'length));
            state := prbs_forward(state, prbs31, probability_v'length);
            if probability_v <= probability_threshold_c then
              if not is_last(config_c, in_s(i).m) then
                insert_error_s <= true;
                byte_index_s <= to_integer(probability_v(nsl_math.arith.log2(config_c.data_width)-1 downto 0));
              end if;
            end if;
          end if;
        end if;
      end process;
    end generate;

    slave_proc: process is
    begin
      out_s(i).s <= accept(config_c, false);
      wait for 40 ns;
      frame_queue_slave(config_c, slave_q(i), clock_i_s, out_s(i).m, out_s(i).s);
    end process;

    slave_error_proc: process(clock_i_s)
    is
      variable error_cnt_v : integer := 0;
    begin
      if rising_edge(clock_i_s) then
        if is_ready(config_c, out_s(i).s) then
          if is_valid(config_c, out_s(i).m) then
            if to_boolean(feed_back_s(i).error) then
              error_feedback_array_all(i)(error_cnt_v) := feed_back_s(i);
              error_cnt_v := (error_cnt_v + 1) mod error_feedback_array_all(i)'length;
          end if;
          end if;
        end if;
      end if;
    end process;

    stats_dump_proc : process(clock_i_s, reset_n_i_s)
      variable tested_pkts : integer := 0;
      variable inserted_error : integer := 0;
      variable error_ratio   : real := 0.0;
    begin 
      if reset_n_i_s = '0' then
        tested_pkts := 0;
        inserted_error := 0;
        error_ratio := 0.0;
        done_s(i) <= '0';
      elsif rising_edge(clock_i_s) then
        if to_boolean(feed_back_s(i).error) then
          inserted_error := inserted_error + 1;
        end if;

        if is_ready(config_c, out_s(i).s) and is_valid(config_c, out_s(i).m) and is_last(config_c, out_s(i).m) then
          tested_pkts := tested_pkts + 1;

          if tested_pkts > 0 then
            error_ratio := real(inserted_error) / real(tested_pkts);
          end if;

          if tested_pkts = nbr_pkt_to_test then
            done_s(i) <= '1';
          end if;

          if tested_pkts mod 1000 = 0 then
            log_info("INFO: for scenario : " & mode_array_c(i) &
                    " | Nbr of sent pkts : " & to_string(tested_pkts) &
                    " | Nbr of inserted error : " & to_string(inserted_error) &
                    " | Error ratio : " & to_string(error_ratio));
          end if;
        end if;
      end if;
    end process;
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
      clock_o(0) => clock_i_s,
      reset_n_o(0) => reset_n_i_s,
      done_i => done_s
      );
  
end;
