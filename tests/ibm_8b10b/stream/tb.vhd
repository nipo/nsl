library ieee;
use ieee.std_logic_1164.all;

library nsl_data, nsl_simulation, nsl_line_coding, nsl_amba;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_line_coding.ibm_8b10b.all;
use nsl_line_coding.ibm_8b10b_stream.all;

entity tb is
end tb;

architecture arch of tb is
begin

  c: process
    constant ctxt: log_context := "Config";

    constant cfg: config_t := config(4, id => 4, dest => 2,
                                     keep => true, strobe => true,
                                     last => true);
    constant scfg: nsl_amba.axi4_stream.config_t := as_stream_config(cfg);
  begin
    assert_equal(ctxt, "data width", scfg.data_width, 4, FAILURE);
    assert_equal(ctxt, "user width", scfg.user_width, 4, FAILURE);
    assert_equal(ctxt, "id width", scfg.id_width, 4, FAILURE);
    assert_equal(ctxt, "dest width", scfg.dest_width, 2, FAILURE);
    assert_equal(ctxt, "keep", scfg.has_keep, true, FAILURE);
    assert_equal(ctxt, "strobe", scfg.has_strobe, true, FAILURE);
    assert_equal(ctxt, "ready", scfg.has_ready, true, FAILURE);
    assert_equal(ctxt, "last", scfg.has_last, true, FAILURE);

    log_info(ctxt, "done");
    wait;
  end process;

  s: process
    constant ctxt: log_context := "Single word";

    constant cfg: config_t := config(1, last => true);
    variable m: master_t;
  begin
    m := transfer(cfg, K28_5, last => true);

    assert_equal(ctxt, "valid", is_valid(cfg, m), true, FAILURE);
    assert_equal(ctxt, "last", is_last(cfg, m), true, FAILURE);
    assert_equal(ctxt, "user", user(cfg, m), "1", FAILURE);
    assert_equal(ctxt, "word", to_string(word(cfg, m)), to_string(K28_5), FAILURE);

    m := transfer(cfg, data(1, 0));

    assert_equal(ctxt, "data valid", is_valid(cfg, m), true, FAILURE);
    assert_equal(ctxt, "data last", is_last(cfg, m), false, FAILURE);
    assert_equal(ctxt, "data user", user(cfg, m), "0", FAILURE);
    assert_equal(ctxt, "data word", to_string(word(cfg, m)), to_string(data(1, 0)), FAILURE);

    log_info(ctxt, "done");
    wait;
  end process;

  v: process
    constant ctxt: log_context := "Word vector";

    constant cfg: config_t := config(4);
    constant w: data_vector(0 to 3) := (K28_5, data(1, 0), data(2, 0), K28_1);
    variable m: master_t;
    variable rd: data_vector(0 to 3);
  begin
    m := transfer(cfg, w);

    assert_equal(ctxt, "user", user(cfg, m), "1001", FAILURE);

    rd := words(cfg, m);
    for i in w'range
    loop
      assert_equal(ctxt, "words "&to_string(i), to_string(rd(i)), to_string(w(i)), FAILURE);
      assert_equal(ctxt, "word "&to_string(i), to_string(word(cfg, m, i)), to_string(w(i)), FAILURE);
    end loop;

    log_info(ctxt, "done");
    wait;
  end process;

  o: process
    constant ctxt: log_context := "Byte order";

    constant cfg: config_t := config(4);
    constant w: data_vector(0 to 3) := (K28_5, data(1, 0), data(2, 0), K28_1);
    variable m, m2: master_t;
    variable rd: data_vector(3 downto 0);
  begin
    m := transfer(cfg, w);
    rd := words(cfg, m, BYTE_ORDER_DECREASING);

    for i in w'range
    loop
      assert_equal(ctxt, "words "&to_string(i), to_string(rd(i)), to_string(w(i)), FAILURE);
      assert_equal(ctxt, "word "&to_string(i),
                   to_string(word(cfg, m, i, BYTE_ORDER_DECREASING)),
                   to_string(w(i)), FAILURE);
    end loop;

    m2 := transfer(cfg, rd, order => BYTE_ORDER_DECREASING);

    assert_equal(ctxt, "user", user(cfg, m2), user(cfg, m), FAILURE);
    for i in w'range
    loop
      assert_equal(ctxt, "round trip "&to_string(i),
                   to_string(word(cfg, m2, i)), to_string(w(i)), FAILURE);
    end loop;

    log_info(ctxt, "done");
    wait;
  end process;

  x: process
    constant ctxt: log_context := "Sideband";

    constant cfg: config_t := config(2, id => 4, dest => 2,
                                     keep => true, strobe => true,
                                     last => true);
    constant w: data_vector(0 to 1) := (K28_5, data(3, 2));
    variable m: master_t;
  begin
    m := transfer(cfg, w,
                  strobe => "01",
                  keep => "11",
                  id => "0101",
                  dest => "10",
                  last => true);

    -- TUSER bit index matches byte index, literal reads bit 1 down to 0
    assert_equal(ctxt, "user", user(cfg, m), "01", FAILURE);
    assert_equal(ctxt, "strobe", strobe(cfg, m), "01", FAILURE);
    assert_equal(ctxt, "keep", keep(cfg, m), "11", FAILURE);
    assert_equal(ctxt, "id", id(cfg, m), "0101", FAILURE);
    assert_equal(ctxt, "dest", dest(cfg, m), "10", FAILURE);
    assert_equal(ctxt, "last", is_last(cfg, m), true, FAILURE);
    assert_equal(ctxt, "word 0", to_string(word(cfg, m, 0)), to_string(w(0)), FAILURE);
    assert_equal(ctxt, "word 1", to_string(word(cfg, m, 1)), to_string(w(1)), FAILURE);

    log_info(ctxt, "done");
    wait;
  end process;

end;
