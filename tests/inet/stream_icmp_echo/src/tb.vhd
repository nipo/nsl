library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_inet, nsl_math;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;
use nsl_inet.checksum.all;
use nsl_inet.stream_ipv4.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

  -- An L1 block, the layer-2 context, the IPv4 context.  Only their
  -- lengths matter to the responder, contents are echoed verbatim.
  constant header_length_c : integer_vector(0 to 2) := (0 => 5, 1 => 7, 2 => 7);

  function pattern(length: natural; tag: natural) return byte_string
  is
    variable ret: byte_string(0 to length-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_byte((16#31# + tag * 16#17# + i * 3) mod 256);
    end loop;
    return ret;
  end function;

  -- Fills the checksum field of an ICMP message so that it verifies.
  function icmp_message(pdu: byte_string) return byte_string
  is
    variable ret: byte_string(0 to pdu'length-1) := pdu;
    variable acc: checksum_acc_t := checksum_acc_init_c;
  begin
    ret(2 to 3) := from_hex("0000");
    acc := checksum_update(acc, ret);
    if ret'length mod 2 = 1 then
      acc := checksum_update(acc, to_byte(0));
    end if;
    ret(2 to 3) := checksum_spill(acc);

    assert checksum_is_valid(ret)
      report "Bad ICMP test vector"
      severity failure;
    return ret;
  end function;

  -- Expected answer to an echo request: type cleared, stored checksum
  -- raised by the one's complement weight of the type byte.
  function echo_answer(request: byte_string) return byte_string
  is
    alias xr: byte_string(0 to request'length-1) is request;
    variable ret: byte_string(0 to request'length-1) := xr;
    variable adjusted: unsigned(16 downto 0);
  begin
    ret(0) := to_byte(0);
    adjusted := ("0" & from_be(xr(2 to 3))) + to_unsigned(16#0800#, 17);
    if adjusted(16) = '1' then
      ret(2 to 3) := to_be(adjusted(15 downto 0) + 1);
    else
      ret(2 to 3) := to_be(adjusted(15 downto 0));
    end if;
    return ret;
  end function;

  -- Echo requests, 16 and 15 bytes of PDU
  constant req_even_c: byte_string
    := icmp_message(from_hex("08000000") & pattern(12, 1));
  constant req_odd_c: byte_string
    := icmp_message(from_hex("08000000") & pattern(11, 2));
  -- Header only, the shortest echo request a host emits
  constant req_min_c: byte_string
    := icmp_message(from_hex("08000000") & from_hex("abcd0001"));
  -- Stored checksum of 0xffff, the negative zero of the one's
  -- complement sum: the type rewrite wraps the field around.
  constant req_carry_c: byte_string := from_hex("0800fffff7ff");
  -- Echo request whose checksum field got a bit flipped
  constant req_corrupt_c: byte_string
    := req_even_c(0 to 2) & (req_even_c(3) xor x"01")
    & req_even_c(4 to req_even_c'right);

  -- Messages this endpoint does not answer
  constant msg_reply_c: byte_string
    := icmp_message(from_hex("00000000") & pattern(12, 3));
  constant msg_unreach_c: byte_string
    := icmp_message(from_hex("03000000") & pattern(12, 4));
  constant msg_bad_code_c: byte_string
    := icmp_message(from_hex("08010000") & pattern(12, 5));
  -- PDU with no complete checksum field
  constant pdu_short_c: byte_string := from_hex("080008");

  constant ans_even_c: byte_string := echo_answer(req_even_c);
  constant ans_odd_c: byte_string := echo_answer(req_odd_c);
  constant ans_min_c: byte_string := echo_answer(req_min_c);
  constant ans_carry_c: byte_string := echo_answer(req_carry_c);
  constant ans_corrupt_c: byte_string := echo_answer(req_corrupt_c);

begin

  assert checksum_is_valid(req_carry_c)
    report "Carry test vector does not verify"
    severity failure;
  assert req_carry_c(2 to 3) = from_hex("ffff")
    report "Carry test vector does not carry the expected checksum"
    severity failure;
  assert not checksum_is_valid(req_corrupt_c)
    report "Corrupted test vector happens to verify"
    severity failure;

  assert checksum_is_valid(ans_even_c)
    and checksum_is_valid(ans_odd_c)
    and checksum_is_valid(ans_min_c)
    and checksum_is_valid(ans_carry_c)
    report "Expected answer does not verify"
    severity failure;
  assert ans_carry_c(2 to 3) = from_hex("0800")
    report "Carry answer checksum is not the wrapped around value"
    severity failure;

  w_gen: for wl2 in 0 to 2 generate
    constant cfg_c: config_t := stream_config(2 ** wl2);
    constant prefix_c: byte_string
      := pattern(context_byte_count(cfg_c, header_length_c), wl2);
    signal input_s, output_s: bus_t;
    signal armed_s, backpressure_check_s: std_ulogic;
  begin

    stim: process is
      procedure request_send(constant pdu: byte_string;
                             constant rejected: boolean := false)
      is
      begin
        if rejected then
          packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                      packet => prefix_c & pdu, user => "1");
        else
          packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                      packet => prefix_c & pdu, user => "0");
        end if;
      end procedure;
    begin
      input_s.m <= transfer_defaults(cfg_c);
      backpressure_check_s <= '0';
      wait for 40 ns;

      request_send(req_even_c);
      request_send(req_odd_c);
      request_send(req_carry_c);
      request_send(req_corrupt_c);
      request_send(req_even_c, rejected => true);

      -- Consumed silently, the following request tells them apart
      request_send(msg_reply_c);
      request_send(msg_unreach_c);
      request_send(msg_bad_code_c);
      request_send(req_min_c);

      request_send(pdu_short_c);
      request_send(req_odd_c);

      -- Sink is draining as fast as the source feeds: the responder
      -- may not stall its input.
      wait until armed_s = '1';
      backpressure_check_s <= '1';
      for i in 0 to 3
      loop
        request_send(req_even_c);
        request_send(req_odd_c);
      end loop;
      backpressure_check_s <= '0';

      wait;
    end process;

    check: process is
      procedure answer_check(constant pdu: byte_string;
                             constant rejected: boolean;
                             constant what: string)
      is
        constant expected: byte_string := prefix_c & pdu;
        variable beat: master_t;
        variable rx: byte_stream;
        variable d: byte_string(0 to cfg_c.data_width-1);
      begin
        clear(rx);
        loop
          receive(cfg_c, clock_s, output_s.m, output_s.s, beat);
          assert is_packed(cfg_c, beat)
            report "Sparse keep pattern on output"
            severity failure;
          d := bytes(cfg_c, beat);
          for i in 0 to byte_count(cfg_c, beat) - 1
          loop
            write(rx, d(i));
          end loop;

          if is_last(cfg_c, beat) then
            assert is_rejected(cfg_c, beat) = rejected
              report to_string(cfg_c) & " " & what
              & ": unexpected reject flag state"
              severity failure;
            exit;
          end if;
        end loop;

        assert_equal(to_string(cfg_c) & " " & what, rx.all, expected, failure);
        deallocate(rx);
      end procedure;
    begin
      output_s.s <= accept(cfg_c, false);
      armed_s <= '0';
      wait for 40 ns;

      answer_check(ans_even_c, false, "even payload");
      answer_check(ans_odd_c, false, "odd payload");
      answer_check(ans_carry_c, false, "checksum carry");
      answer_check(ans_corrupt_c, true, "corrupted checksum");
      answer_check(ans_even_c, true, "request rejected upstream");
      answer_check(ans_min_c, false, "header-only request");
      answer_check(ans_odd_c, false, "request after a short pdu");

      armed_s <= '1';
      for i in 0 to 3
      loop
        answer_check(ans_even_c, false, "back to back even payload");
        answer_check(ans_odd_c, false, "back to back odd payload");
      end loop;

      log_info(to_string(cfg_c) & " ICMP echo responder OK");
      done_s(wl2) <= '1';
      wait;
    end process;

    input_check: nsl_amba.axi4_stream.axi4_stream_backpressure_assertions
      generic map(
        config_c => cfg_c,
        prefix_c => "ICMP echo input"
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        enable_i => backpressure_check_s,
        bus_i => input_s
        );

    dut: nsl_inet.stream_ipv4.stream_ipv4_icmp_echo
      generic map(
        config_c => cfg_c,
        header_length_c => header_length_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        in_i => input_s.m,
        in_o => input_s.s,

        out_o => output_s.m,
        out_i => output_s.s
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
