library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;

entity tb is
end tb;

architecture arch of tb is
  constant udp_stack_c: integer_vector(0 to 2) := (5, 8, 5);
begin

  checker: process
    variable cfg: config_t;
    variable beat: master_t;
    variable keep_v: std_ulogic_vector(0 to 3);
  begin
    for w in 0 to 2
    loop
      cfg := stream_config(2 ** w);

      assert_equal("data width", cfg.data_width, 2 ** w, failure);
      assert_equal("user width", cfg.user_width, 1, failure);
      assert cfg.has_keep and cfg.has_last
        report "Stream config must have keep and last"
        severity failure;

      assert_equal("null vector transported size",
                   context_byte_count(cfg, null_integer_vector), 0, failure);

      case w is
        when 0 =>
          assert_equal("single block", context_byte_count(cfg, (0 => 5)),
                       5, failure);
          assert_equal("udp stack blocks", context_byte_count(cfg, udp_stack_c),
                       18, failure);
        when 1 =>
          assert_equal("single block", context_byte_count(cfg, (0 => 5)),
                       6, failure);
          assert_equal("udp stack blocks", context_byte_count(cfg, udp_stack_c),
                       20, failure);
        when others =>
          assert_equal("single block", context_byte_count(cfg, (0 => 5)),
                       8, failure);
          assert_equal("udp stack blocks", context_byte_count(cfg, udp_stack_c),
                       24, failure);
      end case;

      assert_equal("beat count",
                   context_beat_count(cfg, udp_stack_c) * cfg.data_width,
                   context_byte_count(cfg, udp_stack_c), failure);

      assert_equal("padded block",
                   context_pad(cfg, from_hex("0102030405")),
                   from_hex("0102030405")
                   & byte_string'(5 to context_byte_count(cfg, (0 => 5))-1
                                  => x"00"),
                   failure);

      beat := transfer(cfg, bytes => (0 to cfg.data_width-1 => x"a5"),
                       last => true);
      beat := reject_set(cfg, beat, true);
      assert is_rejected(cfg, beat)
        report "Reject flag should be seen on last beat"
        severity failure;
      beat := reject_set(cfg, beat, false);
      assert not is_rejected(cfg, beat)
        report "Reject flag should be cleared"
        severity failure;

      beat := transfer(cfg, bytes => (0 to cfg.data_width-1 => x"a5"),
                       last => false);
      beat := reject_set(cfg, beat, true);
      assert not is_rejected(cfg, beat)
        report "Reject flag should be ignored on non-last beat"
        severity failure;

      assert is_packed(cfg, beat)
        report "Full beat should be packed"
        severity failure;

      if cfg.data_width > 1 then
        keep_v := (others => '0');
        keep_v(0) := '1';
        beat := transfer(cfg, bytes => (0 to cfg.data_width-1 => x"a5"),
                         keep => keep_v(0 to cfg.data_width-1),
                         last => false);
        assert not is_packed(cfg, beat)
          report "Partial keep needs last"
          severity failure;

        beat := transfer(cfg, bytes => (0 to cfg.data_width-1 => x"a5"),
                         keep => keep_v(0 to cfg.data_width-1),
                         last => true);
        assert is_packed(cfg, beat)
          report "Kept prefix on last beat should be packed"
          severity failure;

        keep_v := (others => '0');
        keep_v(cfg.data_width-1) := '1';
        beat := transfer(cfg, bytes => (0 to cfg.data_width-1 => x"a5"),
                         keep => keep_v(0 to cfg.data_width-1),
                         last => true);
        assert not is_packed(cfg, beat)
          report "Sparse keep should not be packed"
          severity failure;
      end if;

      log_info(to_string(cfg) & " conventions OK");
    end loop;

    terminate(0);
  end process;

end;
