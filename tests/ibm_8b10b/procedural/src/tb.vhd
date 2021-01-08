library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_line_coding, nsl_simulation, nsl_logic, nsl_data;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_data.text.all;
use nsl_logic.logic.all;
use nsl_logic.bool.all;
use nsl_line_coding.ibm_8b10b.all;

entity tb is
end tb;

architecture arch of tb is

  function code_pprint(d: data_word; k: std_ulogic) return string
  is
    variable prefix:string(1 to 1);
  begin
    if k = '1' then
      prefix := "K";
    else
      prefix := "D";
    end if;

    return prefix
      & to_string(to_integer(unsigned(d(4 downto 0))))
      & "."
      & to_string(to_integer(unsigned(d(7 downto 5))));
  end function;

  procedure encode_check(
    disp      : in std_ulogic;
    data      : in data_word;
    k         : in std_ulogic)
  is
    variable context : line;
    variable dut_word, ref_word : code_word;
    variable dut_disp, ref_disp : std_ulogic;
  begin
    write(context, "Encoder for " & code_pprint(data, k) & ", d=" & to_string(disp));

    nsl_line_coding.ibm_8b10b_table.encode(
      data, disp, k,
      ref_word, ref_disp);

    nsl_line_coding.ibm_8b10b_logic.encode(
      data, disp, k,
      dut_word, dut_disp);

    assert_equal(context.all, "ref data", dut_word, ref_word, FAILURE);
    assert_equal(context.all, "ref disp", dut_disp, ref_disp, FAILURE);
  end procedure;

  procedure decode_check(
    disp      : in std_ulogic;
    word      : in code_word)
  is
    variable context : line;
    variable dut_data, ref_data : data_word;
    variable dut_k, ref_k : std_ulogic;
    variable dut_disp, ref_disp : std_ulogic;
    variable dut_err, ref_err : std_ulogic;
    variable dut_derr, ref_derr : std_ulogic;
  begin
    write(context, "Decode " & to_string(word) & ", rd=" & to_string(disp));

    nsl_line_coding.ibm_8b10b_table.decode(
      word, disp,
      ref_data, ref_disp, ref_k, ref_err, ref_derr);

    write(context, ", ref DispErr=" & to_string(ref_derr) & ", Err=" & to_string(ref_err));

    if ref_derr = '0' and ref_err = '0' then
      write(context, ", code=" & code_pprint(ref_data, ref_k));
    end if;

    nsl_line_coding.ibm_8b10b_logic.decode(
      word, disp,
      dut_data, dut_disp, dut_k, dut_err, dut_derr);

    if ref_derr = '1' and dut_derr = '0' then
      log_warning(context.all, "Not reporting disparity error");
    elsif ref_derr = '0' and dut_derr = '1' and ref_err = '0' then
      log_error(context.all, "Reporting disparity error for a valid word");
    elsif ref_derr = '0' and dut_derr = '1' and ref_err = '1' then
      log_warning(context.all, "Reporting disparity error for an invalid word with no disparity error");
    else
      assert_equal(context.all, "Disp err", ref_derr, dut_derr, FAILURE);
    end if;
    if ref_derr = '0' then
      if dut_err = '1' then
        assert_equal(context.all, "Dec err", ref_err, dut_err, FAILURE);
      elsif ref_err = '1' then
        log_warning(context.all, "Accepting invalid input");
      else
        assert_equal(context.all, "Dec err", ref_err, dut_err, FAILURE);
        assert_equal(context.all, "Data", ref_data, dut_data, FAILURE);
        assert_equal(context.all, "Control", ref_k, dut_k, FAILURE);
        assert_equal(context.all, "Disp", ref_disp, dut_disp, FAILURE);
      end if;
    end if;
 end procedure;

begin

  codec_check: process
    variable w : data_word;
    variable c : code_word;
  begin
    log_info("Testing encoder...");

    -- Check all data words with both running disparities
    for i in 0 to 255 loop
      w := std_ulogic_vector(to_unsigned(i, w'length));

      encode_check('0', w, '0');
      encode_check('1', w, '0');
    end loop;

    -- Check all control words, assert failure for non-existing ones
    for a in 0 to 31 loop
      for b in 0 to 7 loop
        if not control_exists(a, b) then
          next;
        end if;
        w := control(a, b);

        encode_check('0', w, '1');
        encode_check('1', w, '1');
      end loop;
    end loop;
    log_info("Testing encoder done");

    log_info("Testing decoder...");
    for i in 0 to 1023 loop
      for din in 0 to 1 loop
        c := std_ulogic_vector(to_unsigned(i, c'length));
        decode_check(to_logic(din = 1), c);
      end loop;
    end loop;
    log_info("Testing decoder done");

    wait;
  end process;

  process
  begin
    wait for 10 us;
    nsl_simulation.control.terminate(0);
  end process;

end;
