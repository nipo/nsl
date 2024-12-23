
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is

  procedure assert_equal(context: string;
                         prefix: string;
                         params: crc_params_t;
                         a, b : crc_state_t;
                         sev: severity_level)
  is
    constant as: std_ulogic_vector := crc_spill_vector(params, a);
    constant bs: std_ulogic_vector := crc_spill_vector(params, b);
  begin
    if as /= bs then
      log_info(context&" "&to_string(params, a));
      log_info(context&" "&to_string(params, b));
    end if;
    assert_equal(context, prefix, as, bs, sev);
  end procedure;

begin

      test_ethernet_fcs: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"104c11db7",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "ethernet_fcs";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("2639f4cb")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_zlib: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"104c11db7",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "zlib";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("2639f4cb")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_bluetooth_crc24: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"100065b",
          init => x"555555",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "bluetooth_crc24";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("565ac2")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_hdlc: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "hdlc";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("6e90")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_iso14443a: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"c6c6",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "iso14443a";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("05bf")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_iso14443b: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "iso14443b";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("6e90")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_one_wire: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"131",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "one_wire";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("a1")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_AUTOSAR: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"12f",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/AUTOSAR";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("df")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_BLUETOOTH: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1a7",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/BLUETOOTH";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("26")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_CDMA2000: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"19b",
          init => x"ff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/CDMA2000";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("da")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_DARC: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"139",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/DARC";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("15")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_DVB_S2: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1d5",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/DVB-S2";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("bc")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_GSM_A: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11d",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/GSM-A";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("37")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_GSM_B: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"149",
          init => x"ff",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/GSM-B";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("94")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_HITAG: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11d",
          init => x"ff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/HITAG";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("b4")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_I_CODE: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11d",
          init => x"fd",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/I-CODE";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("7e")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_LTE: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"19b",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/LTE";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("ea")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_MAXIM_DOW: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"131",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/MAXIM-DOW";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("a1")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_MIFARE_MAD: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11d",
          init => x"c7",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/MIFARE-MAD";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("99")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_NRSC_5: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"131",
          init => x"ff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/NRSC-5";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("f7")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_OPENSAFETY: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"12f",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/OPENSAFETY";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("3e")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_ROHC: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"107",
          init => x"ff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/ROHC";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("d0")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_SAE_J1850: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11d",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/SAE-J1850";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("4b")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_SMBUS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"107",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/SMBUS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("f4")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_TECH_3250: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11d",
          init => x"ff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/TECH-3250";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("97")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_8_WCDMA: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"19b",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-8/WCDMA";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("25")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_ARC: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18005",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/ARC";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("3dbb")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_CDMA2000: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1c867",
          init => x"ffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/CDMA2000";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("064c")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_CMS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18005",
          init => x"ffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/CMS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("e7ae")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_DDS_110: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18005",
          init => x"800d",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/DDS-110";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("cf9e")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_DECT_X: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"10589",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/DECT-X";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("7f00")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_DNP: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"13d65",
          init => x"ffff",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/DNP";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("82ea")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_EN_13757: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"13d65",
          init => x"ffff",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/EN-13757";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("b7c2")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_GENIBUS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/GENIBUS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("4ed6")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_GSM: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"ffff",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/GSM";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("3cce")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_IBM_3740: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"ffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/IBM-3740";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("b129")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_IBM_SDLC: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/IBM-SDLC";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("6e90")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_ISO_IEC_14443_3_A: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"c6c6",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/ISO-IEC-14443-3-A";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("05bf")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_KERMIT: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/KERMIT";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("8921")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_LJ1200: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"16f63",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/LJ1200";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("f4bd")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_M17: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"15935",
          init => x"ffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/M17";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("2b77")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_MAXIM_DOW: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18005",
          init => x"ffff",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/MAXIM-DOW";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("c244")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_MCRF4XX: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"ffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/MCRF4XX";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("916f")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_MODBUS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18005",
          init => x"ffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/MODBUS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("374b")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_NRSC_5: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1080b",
          init => x"ffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/NRSC-5";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("66a0")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_OPENSAFETY_A: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"15935",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/OPENSAFETY-A";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("385d")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_OPENSAFETY_B: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1755b",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/OPENSAFETY-B";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("fe20")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_PROFIBUS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11dcf",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/PROFIBUS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("19a8")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_RIELLO: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"b2aa",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/RIELLO";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("d063")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_SPI_FUJITSU: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"1d0f",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/SPI-FUJITSU";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("cce5")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_T10_DIF: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18bb7",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/T10-DIF";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("dbd0")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_TELEDISK: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1a097",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/TELEDISK";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("b30f")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_TMS37157: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"89ec",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/TMS37157";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("b126")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_UMTS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18005",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/UMTS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("e8fe")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_USB: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18005",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/USB";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("c8b4")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_16_XMODEM: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11021",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-16/XMODEM";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("c331")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_BLE: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"100065b",
          init => x"555555",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/BLE";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("565ac2")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_FLEXRAY_A: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"15d6dcb",
          init => x"fedcba",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/FLEXRAY-A";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("bd7979")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_FLEXRAY_B: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"15d6dcb",
          init => x"abcdef",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/FLEXRAY-B";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("b8231f")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_INTERLAKEN: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1328b63",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/INTERLAKEN";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("e6f3b4")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_LTE_A: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1864cfb",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/LTE-A";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("03e7cd")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_LTE_B: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1800063",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/LTE-B";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("52ef23")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_OPENPGP: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1864cfb",
          init => x"b704ce",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/OPENPGP";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("02cf21")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_24_OS_9: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1800063",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-24/OS-9";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("a50f20")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_AIXM: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1814141ab",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/AIXM";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("7fbf1030")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_AUTOSAR: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1f4acfb13",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/AUTOSAR";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("6ad09716")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_BASE91_D: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1a833982b",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/BASE91-D";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("76553187")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_BZIP2: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"104c11db7",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/BZIP2";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("181989fc")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_CD_ROM_EDC: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"18001801b",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/CD-ROM-EDC";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("c4edc26e")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_CKSUM: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"104c11db7",
          init => x"ffffffff",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/CKSUM";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("80765e76")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_ISCSI: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"11edc6f41",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/ISCSI";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("839206e3")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_ISO_HDLC: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"104c11db7",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/ISO-HDLC";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("2639f4cb")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_JAMCRC: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"104c11db7",
          init => x"ffffffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/JAMCRC";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("d9c60b34")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_MEF: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1741b8cd7",
          init => x"ffffffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/MEF";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("512fc2d2")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_MPEG_2: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"104c11db7",
          init => x"ffffffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/MPEG-2";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("e7e67603")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_32_XFER: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1000000af",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-32/XFER";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("38e30bbd")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_40_GSM: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"10004820009",
          init => x"ffffffffff",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-40/GSM";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("46c64f16d4")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_64_ECMA_182: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"142f0e1eba9ea3693",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-64/ECMA-182";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("4773490b5fdf406c")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_64_GO_ISO: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1000000000000001b",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-64/GO-ISO";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("0110a475c75609b9")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_64_MS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1259c84cba6426349",
          init => x"ffffffffffffffff",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-64/MS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("eace4e024fb7d475")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_64_REDIS: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"1ad93d23594c935a9",
          init => x"0",
          complement_input => false,
          complement_state => false,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-64/REDIS";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("cad9b8c414d9c6e9")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_64_WE: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"142f0e1eba9ea3693",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_DESCENDING,
          spill_order => EXP_ORDER_ASCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-64/WE";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("0af0a4f1e359ec62")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;

      test_CRC_64_XZ: process is
        constant cfg_c : crc_params_t := crc_params(
          poly => x"142f0e1eba9ea3693",
          init => x"0",
          complement_input => false,
          complement_state => true,
          byte_bit_order => BIT_ORDER_ASCENDING,
          spill_order => EXP_ORDER_DESCENDING,
          byte_order => BYTE_ORDER_INCREASING
        );
        constant context: string := "CRC-64/XZ";
      begin
        assert_equal(context, "123..",
                     cfg_c,
                     crc_update(cfg_c, crc_init(cfg_c), from_hex("313233343536373839")),
                     crc_load(cfg_c, from_hex("fa3919dfbbc95d99")),
                     failure
                     );
        assert_equal(context, "has_check",
                     crc_has_constant_check(cfg_c),
                     true,
                     failure
                     );
        assert_equal(context, "pre_00",
                     crc_is_pre_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "pre_ff",
                     crc_is_pre_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_00",
                     crc_is_post_zero_transparent(cfg_c),
                     false,
                     failure
                     );
        assert_equal(context, "post_ff",
                     crc_is_post_ones_transparent(cfg_c),
                     false,
                     failure
                     );
        log_info(context, "OK");
        wait;
      end process;


end;

