library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.prbs.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is
begin

  b: process
    use nsl_amba.axi4_mm.all;
    constant context: log_context := "AXI4 MM 4 burst";

    constant c: config_t := config(32, 32, max_length => 16);
    constant a: address_t := address(c, addr => x"00000000", len_m1 => x"3");
    variable t: transaction_t;
  begin
    log_info(context, to_string(c));

    t := transaction(c, a);

    log_info(context, to_string(c, t));

    assert_equal(context, "A0", address(c, t), x"00000000", FAILURE);
    assert_equal(context, "V0", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L0", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A1", address(c, t), x"00000004", FAILURE);
    assert_equal(context, "V1", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L1", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A2", address(c, t), x"00000008", FAILURE);
    assert_equal(context, "V2", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L2", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A3", address(c, t), x"0000000c", FAILURE);
    assert_equal(context, "V3", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L3", is_last(c, t), true, FAILURE);

    t := step(c, t);

    log_info(context, to_string(c, t));

    assert_equal(context, "End", is_valid(c, t), false, FAILURE);

    log_info(context, "done");
    wait;
  end process;

  w: process
    use nsl_amba.axi4_mm.all;
    constant context: log_context := "AXI4 MM 4 wrap burst";

    constant c: config_t := config(32, 32, max_length => 16, burst => true);
    constant a: address_t := address(c, addr => x"00000004", len_m1 => x"3", burst => BURST_WRAP);
    variable t: transaction_t;
  begin
    log_info(context, to_string(c));

    t := transaction(c, a);

    log_info(context, to_string(c, t));

    assert_equal(context, "A0", address(c, t), x"00000004", FAILURE);
    assert_equal(context, "V0", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L0", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A1", address(c, t), x"00000008", FAILURE);
    assert_equal(context, "V1", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L1", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A2", address(c, t), x"0000000c", FAILURE);
    assert_equal(context, "V2", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L2", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A3", address(c, t), x"00000000", FAILURE);
    assert_equal(context, "V3", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L3", is_last(c, t), true, FAILURE);

    t := step(c, t);

    log_info(context, to_string(c, t));

    assert_equal(context, "End", is_valid(c, t), false, FAILURE);

    log_info(context, "done");
    wait;
  end process;

  w32: process
    use nsl_amba.axi4_mm.all;
    constant context: log_context := "AXI4 MM 4 wrap32 burst";

    constant c: config_t := config(32, 64, max_length => 16, burst => true, size => true);
    constant a: address_t := address(c, addr => x"deadbee8", len_m1 => x"f", burst => BURST_WRAP, size_l2 => "010");
    variable t: transaction_t;
  begin
    log_info(context, to_string(c));

    t := transaction(c, a);

    log_info(context, to_string(c, t));

    assert_equal(context, "A0", address(c, t), x"deadbee8", FAILURE);
    assert_equal(context, "V0", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L0", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A1", address(c, t), x"deadbeec", FAILURE);
    assert_equal(context, "V1", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L1", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A2", address(c, t), x"deadbef0", FAILURE);
    assert_equal(context, "V2", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L2", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A3", address(c, t), x"deadbef4", FAILURE);
    assert_equal(context, "V3", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L3", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A4", address(c, t), x"deadbef8", FAILURE);
    assert_equal(context, "V4", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L4", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A5", address(c, t), x"deadbefc", FAILURE);
    assert_equal(context, "V5", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L5", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A6", address(c, t), x"deadbec0", FAILURE);
    assert_equal(context, "V6", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L6", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A7", address(c, t), x"deadbec4", FAILURE);
    assert_equal(context, "V7", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L7", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A8", address(c, t), x"deadbec8", FAILURE);
    assert_equal(context, "V8", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L8", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A9", address(c, t), x"deadbecc", FAILURE);
    assert_equal(context, "V9", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L9", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A10", address(c, t), x"deadbed0", FAILURE);
    assert_equal(context, "V10", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L10", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A11", address(c, t), x"deadbed4", FAILURE);
    assert_equal(context, "V11", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L11", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A12", address(c, t), x"deadbed8", FAILURE);
    assert_equal(context, "V12", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L12", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A13", address(c, t), x"deadbedc", FAILURE);
    assert_equal(context, "V13", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L13", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A14", address(c, t), x"deadbee0", FAILURE);
    assert_equal(context, "V14", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L14", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A15", address(c, t), x"deadbee4", FAILURE);
    assert_equal(context, "V15", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L15", is_last(c, t), true, FAILURE);

    t := step(c, t);

    log_info(context, to_string(c, t));

    assert_equal(context, "End", is_valid(c, t), false, FAILURE);

    log_info(context, "done");
    wait;
  end process;

  w16: process
    use nsl_amba.axi4_mm.all;
    constant context: log_context := "AXI4 MM 2 wrap32 burst";

    constant c: config_t := config(32, 64, max_length => 16, burst => true, size => true);
    constant a: address_t := address(c, addr => x"deadbee8", len_m1 => x"f", burst => BURST_WRAP, size_l2 => "001");
    variable t: transaction_t;
  begin
    log_info(context, to_string(c));

    t := transaction(c, a);

    log_info(context, to_string(c, t));

    assert_equal(context, "A0", address(c, t), x"deadbee8", FAILURE);
    assert_equal(context, "V0", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L0", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A1", address(c, t), x"deadbeea", FAILURE);
    assert_equal(context, "V1", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L1", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A2", address(c, t), x"deadbeec", FAILURE);
    assert_equal(context, "V2", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L2", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A3", address(c, t), x"deadbeee", FAILURE);
    assert_equal(context, "V3", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L3", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A4", address(c, t), x"deadbef0", FAILURE);
    assert_equal(context, "V4", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L4", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A5", address(c, t), x"deadbef2", FAILURE);
    assert_equal(context, "V5", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L5", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A6", address(c, t), x"deadbef4", FAILURE);
    assert_equal(context, "V6", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L6", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A7", address(c, t), x"deadbef6", FAILURE);
    assert_equal(context, "V7", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L7", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A8", address(c, t), x"deadbef8", FAILURE);
    assert_equal(context, "V8", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L8", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A9", address(c, t), x"deadbefa", FAILURE);
    assert_equal(context, "V9", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L9", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A10", address(c, t), x"deadbefc", FAILURE);
    assert_equal(context, "V10", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L10", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A11", address(c, t), x"deadbefe", FAILURE);
    assert_equal(context, "V11", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L11", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A12", address(c, t), x"deadbee0", FAILURE);
    assert_equal(context, "V12", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L12", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A13", address(c, t), x"deadbee2", FAILURE);
    assert_equal(context, "V13", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L13", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A14", address(c, t), x"deadbee4", FAILURE);
    assert_equal(context, "V14", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L14", is_last(c, t), false, FAILURE);

    t := step(c, t);
    
    log_info(context, to_string(c, t));

    assert_equal(context, "A15", address(c, t), x"deadbee6", FAILURE);
    assert_equal(context, "V15", is_valid(c, t), true, FAILURE);
    assert_equal(context, "L15", is_last(c, t), true, FAILURE);

    t := step(c, t);

    log_info(context, to_string(c, t));

    assert_equal(context, "End", is_valid(c, t), false, FAILURE);

    log_info(context, "done");
    wait;
  end process;

  addr: process
    use nsl_amba.axi4_mm.all;
    constant context: log_context := "AXI4 Addr Parsing";

    constant c: config_t := config(32, 32, max_length => 16);

    procedure check_addr(a: string; value: unsigned)
    is
    begin
      assert_equal(context & " " & a, address_parse(c, a), value, FAILURE);
    end procedure;

  begin
    log_info(context, to_string(c));

    check_addr("x/0",          "--------------------------------"&"--------------------------------");
    check_addr("0/1",          "--------------------------------"&"0-------------------------------");
    check_addr("xe7777777/3",  "--------------------------------"&"111-----------------------------");
    check_addr("xdeadbeef/8",  "--------------------------------"&x"de"&"------------------------");
    check_addr("xde------",    "--------------------------------"&x"de"&"------------------------");
    check_addr("xdeadbeef/32", "--------------------------------"&x"deadbeef");
    check_addr(x"deadbeef",    "--------------------------------"&x"deadbeef");
    check_addr("xdead_0000",   "--------------------------------"&x"dead0000");
    check_addr(x"dead_0000",   "--------------------------------"&x"dead0000");
    check_addr("x--ad_0000/16",   "----------------------------------------"&x"ad"&"----------------");
    wait;
  end process;

  address_serializer: process
    use nsl_amba.axi4_mm.all;
    procedure address_serializer_torture(cfg: config_t; loops: integer)
    is
      variable serin_v, serout_v, ser_incr_v, ser_wrap_v, ser_inval_v: std_ulogic_vector(address_vector_length(cfg)-1 downto 0);
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
      variable incr_pos, wrap_pos : integer := -1;
      variable has_burst: boolean := false;
    begin
      -- Serialize all-zero vectors where burst is incr and wrap, this
      -- should expose the position of these two bits in encoded vector,
      -- in a way we can skip when the PRBS gives us an invalid value
      -- where burst = "11".
      ser_incr_v := vector_pack(cfg, address(cfg, burst => BURST_INCR, valid => false, size_l2 => "000"));
      ser_wrap_v := vector_pack(cfg, address(cfg, burst => BURST_WRAP, valid => false, size_l2 => "000"));

      for i in ser_incr_v'range
      loop
        if ser_incr_v(i) = '1' then incr_pos := i; has_burst := true; end if;
        if ser_wrap_v(i) = '1' then wrap_pos := i; end if;
      end loop;

      if has_burst then
        ser_inval_v := (others => '-');
        ser_inval_v(incr_pos) := '1';
        ser_inval_v(wrap_pos) := '1';
      else
        ser_inval_v := (others => '0');
      end if;

--      log_info(to_string(cfg), "Inval vector: " & to_string(ser_inval_v));

      for i in 0 to loops-1
      loop
        serin_v := prbs_bit_string(state_v, prbs31, serin_v'length);

        if std_match(serin_v, ser_inval_v) then
          -- Ensure invalid burst value is not used.
          serin_v(incr_pos) := '0';
        end if;

        serout_v := vector_pack(cfg, address_vector_unpack(cfg, serin_v));
        if serin_v /= serout_v then
          log_info("Hint: "&to_string(serin_v xor serout_v)&" "&to_string(cfg, address_vector_unpack(cfg, serin_v xor serout_v)));
        end if;
        assert_equal(to_string(cfg)&" A", serin_v, serout_v, failure);

        state_v := prbs_forward(state_v, prbs31, serin_v'length);
      end loop;

      log_info(to_string(cfg) & " address torture OK");
    end procedure;

    procedure write_data_serializer_torture(cfg: config_t; loops: integer)
    is
      variable serin_v, serout_v: std_ulogic_vector(write_data_vector_length(cfg)-1 downto 0);
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    begin
      for i in 0 to loops-1
      loop
        serin_v := prbs_bit_string(state_v, prbs31, serin_v'length);
        serout_v := vector_pack(cfg, write_data_vector_unpack(cfg, serin_v));
        if serin_v /= serout_v then
          log_info("Hint: "&to_string(serin_v xor serout_v)&" "&to_string(cfg, write_data_vector_unpack(cfg, serin_v xor serout_v)));
        end if;
        assert_equal(to_string(cfg)&" W", serin_v, serout_v, failure);

        state_v := prbs_forward(state_v, prbs31, serin_v'length);
      end loop;

      log_info(to_string(cfg) & " write data torture OK");
    end procedure;

    procedure write_response_serializer_torture(cfg: config_t; loops: integer)
    is
      variable serin_v, serout_v: std_ulogic_vector(write_response_vector_length(cfg)-1 downto 0);
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    begin
      for i in 0 to loops-1
      loop
        serin_v := prbs_bit_string(state_v, prbs31, serin_v'length);
        serout_v := vector_pack(cfg, write_response_vector_unpack(cfg, serin_v));
        if serin_v /= serout_v then
          log_info("Hint: "&to_string(serin_v xor serout_v)&" "&to_string(cfg, write_response_vector_unpack(cfg, serin_v xor serout_v)));
        end if;
        assert_equal(to_string(cfg)&" B", serin_v, serout_v, failure);

        state_v := prbs_forward(state_v, prbs31, serin_v'length);
      end loop;

      log_info(to_string(cfg) & " write response torture OK");
    end procedure;

    procedure read_data_serializer_torture(cfg: config_t; loops: integer)
    is
      variable serin_v, serout_v: std_ulogic_vector(read_data_vector_length(cfg)-1 downto 0);
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    begin
      for i in 0 to loops-1
      loop
        serin_v := prbs_bit_string(state_v, prbs31, serin_v'length);
        serout_v := vector_pack(cfg, read_data_vector_unpack(cfg, serin_v));
        if serin_v /= serout_v then
          log_info("Hint: "&to_string(serin_v xor serout_v)&" "&to_string(cfg, read_data_vector_unpack(cfg, serin_v xor serout_v)));
        end if;
        assert_equal(to_string(cfg)&" R", serin_v, serout_v, failure);

        state_v := prbs_forward(state_v, prbs31, serin_v'length);
      end loop;

      log_info(to_string(cfg) & " read data torture OK");
    end procedure;

    procedure serializer_torture(cfg: config_t; loops: integer)
    is
    begin
      address_serializer_torture(cfg, loops);
      write_data_serializer_torture(cfg, loops);
      write_response_serializer_torture(cfg, loops);
      read_data_serializer_torture(cfg, loops);
    end procedure;
  begin
    serializer_torture(config(40, 32, max_length => 16, cache => true), 128);
    serializer_torture(config(16, 32, max_length => 16, id_width => 2, user_width => 3, burst => true), 128);
    serializer_torture(config(16, 32, max_length => 16, region => true, user_width => 3), 128);
    serializer_torture(config(16, 32, qos => true, lock => true, user_width => 3, burst => true), 128);
    serializer_torture(config(16, 64, size => true, max_length => 128, user_width => 3, burst => true), 128);

    wait;
  end process;
  
end;
