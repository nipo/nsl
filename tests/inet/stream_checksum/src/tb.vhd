library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_inet.stream.all;
use nsl_inet.checksum.all;

entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 2);

  -- Zeroes the 2-byte checksum field at chk_offset, then fills it so
  -- that the checksum over pseudo & packet verifies.
  function patched(pkt: byte_string;
                   chk_offset: integer;
                   pseudo: byte_string := null_byte_string) return byte_string
  is
    variable ret: byte_string(0 to pkt'length-1) := pkt;
    variable acc: checksum_state_t := checksum_init(checksum_byte_config_c);
  begin
    ret(chk_offset to chk_offset+1) := from_hex("0000");
    acc := checksum_update(checksum_byte_config_c, acc, pseudo & ret);
    -- An odd count of covered bytes leaves the accumulated value
    -- scaled by 256, one zero byte takes the scaling back.
    if (pseudo'length + ret'length) mod 2 = 1 then
      acc := checksum_update(checksum_byte_config_c, acc,
                             byte_string'(0 => x"00"));
    end if;
    ret(chk_offset to chk_offset+1)
      := checksum_spill(checksum_byte_config_c, acc);

    assert checksum_is_valid(pseudo & ret)
      report "Bad test vector"
      severity failure;
    return ret;
  end function;

  constant vec_even_c: byte_string
    := patched(prbs_byte_string(x"deadbee"&"111", prbs31, 20), 10);
  constant vec_odd_c: byte_string
    := patched(prbs_byte_string(x"1234567"&"000", prbs31, 27), 8);
  constant vec_bad_c: byte_string
    := prbs_byte_string(x"5555555"&"010", prbs31, 20);

  constant pseudo_c: byte_string
    := prbs_byte_string(x"cafe011"&"001", prbs31, 12);
  constant vec_pseudo_c: byte_string
    := patched(prbs_byte_string(x"0abcdef"&"110", prbs31, 24), 6, pseudo_c);

begin

  assert not checksum_is_valid(vec_bad_c)
    report "Corrupted test vector happens to verify"
    severity failure;

  w_gen: for wl2 in 0 to 2 generate
    constant cfg_c: config_t := stream_config(2 ** wl2);
    constant checksum_c: checksum_config_t := checksum_config(cfg_c);
    signal input_s, output_s: bus_t;
    signal init_s: checksum_state_t;
  begin

    stim: process is
    begin
      input_s.m <= transfer_defaults(cfg_c);
      init_s <= checksum_init(checksum_c);
      wait for 40 ns;

      packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                  packet => vec_even_c, user => "0");
      packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                  packet => vec_odd_c, user => "0");
      packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                  packet => vec_bad_c, user => "0");

      init_s <= checksum_update(checksum_c, checksum_init(checksum_c),
                                pseudo_c);
      packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                  packet => vec_pseudo_c, user => "0");
      init_s <= checksum_init(checksum_c);

      -- Valid checksum, but reject flag already set upstream
      packet_send(cfg_c, clock_s, input_s.s, input_s.m,
                  packet => vec_even_c, user => "1");
      wait;
    end process;

    check: process is
      procedure rx_check(constant expected: byte_string;
                         constant rejected: boolean;
                         constant what: string)
      is
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
      wait for 40 ns;

      rx_check(vec_even_c, false, "even length");
      rx_check(vec_odd_c, false, "odd length");
      rx_check(vec_bad_c, true, "corrupted");
      rx_check(vec_pseudo_c, false, "pseudo header");
      rx_check(vec_even_c, true, "upstream reject");

      log_info(to_string(cfg_c) & " checksum validator OK");
      done_s(wl2) <= '1';
      wait;
    end process;

    dut: nsl_inet.checksum.checksum_stream_validator
      generic map(
        config_c => cfg_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => reset_n_s,

        init_i => init_s,

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
