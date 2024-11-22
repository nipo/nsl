library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_axi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is
begin

  b: process
    use nsl_axi.axi4_mm.all;
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
    use nsl_axi.axi4_mm.all;
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
    use nsl_axi.axi4_mm.all;
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
    use nsl_axi.axi4_mm.all;
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
    use nsl_axi.axi4_mm.all;
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
  
end;
