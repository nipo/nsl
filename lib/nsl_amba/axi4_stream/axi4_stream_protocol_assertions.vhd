library ieee;
use ieee.std_logic_1164.all;

library work, nsl_data, nsl_logic;
use work.axi4_stream.all;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_logic.logic.all;

entity axi4_stream_protocol_assertions is
  generic(
    config_c : config_t;
    prefix_c : string := "AXIS";
    MAXWAITS : integer := 16
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    bus_i : in bus_t
    );
end entity;

architecture beh of axi4_stream_protocol_assertions is

  function has_x_in(v: std_ulogic) return boolean
  is
  begin
    return v = 'X';
  end function;

  function has_x_in(v: std_ulogic_vector) return boolean
  is
  begin
    for i in v'range
    loop
      if has_x_in(v(i)) then
        return true;
      end if;
    end loop;
    return false;
  end function;

  function has_x_in(v: byte_string) return boolean
  is
  begin
    for i in v'range
    loop
      if has_x_in(v(i)) then
        return true;
      end if;
    end loop;
    return false;
  end function;
  
begin

  tvalid_reset: process is
    variable reset_was_low : boolean := false;
    variable cycle_after_reset : boolean := false;
  begin
    wait until rising_edge(clock_i);
    cycle_after_reset := reset_was_low and reset_n_i = '1';

    if config_c.has_ready and cycle_after_reset then
      assert not is_ready(config_c, bus_i.s)
        report prefix_c & " assertion AXI4STREAM_ERRM_TVALID_RESET failed"
        severity error;
    end if;

    reset_was_low := reset_n_i = '0';
  end process;

  stable: process is
    variable last_ready : boolean := false;
    variable last_beat : master_t;
  begin
    wait until rising_edge(clock_i);

    if reset_n_i = '0' then
      last_ready := false;
      last_beat := transfer_defaults(config_c);
    else
      if not last_ready and is_valid(config_c, last_beat) then
        assert id(config_c, last_beat) = id(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TID_STABLE failed"
          severity error;
        assert dest(config_c, last_beat) = dest(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TDEST_STABLE failed"
          severity error;
        assert bytes(config_c, last_beat) = bytes(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TDATA_STABLE failed"
          severity error;
        assert strobe(config_c, last_beat) = strobe(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TSTRB_STABLE failed"
          severity error;
        assert is_last(config_c, last_beat) = is_last(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TLAST_STABLE failed"
          severity error;
        assert keep(config_c, last_beat) = keep(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TKEEP_STABLE failed"
          severity error;
        assert user(config_c, last_beat) = user(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TUSER_STABLE failed"
          severity error;
        assert is_valid(config_c, last_beat) = is_valid(config_c, bus_i.m)
          report prefix_c & " assertion AXI4STREAM_ERRM_TVALID_STABLE failed"
          severity error;
      end if;

      last_beat := bus_i.m;
      last_ready := is_ready(config_c, bus_i.s);
    end if;

  end process;

  max_wait: process is
    variable waiting_for: integer range 0 to MAXWAITS := MAXWAITS;
  begin
    wait until rising_edge(clock_i);

    if reset_n_i = '0' or not is_valid(config_c, bus_i.m) or is_ready(config_c, bus_i.s) then
      waiting_for := 0;
    elsif waiting_for < MAXWAITS then
      waiting_for := waiting_for + 1;
    elsif waiting_for = MAXWAITS then
      report prefix_c & " assertion AXI4STREAM_RECS_TREADY_MAX_WAIT failed"
        severity warning;
    end if;
  end process;

  nox: process is
  begin
    wait until rising_edge(clock_i);

    if reset_n_i = '1' then
      if is_valid(config_c, bus_i.m) then
        assert not has_x_in(id(config_c, bus_i.m))
          report prefix_c & " assertion AXI4STREAM_ERRM_TID_X failed"
          severity error;
        assert not has_x_in(dest(config_c, bus_i.m))
          report prefix_c & " assertion AXI4STREAM_ERRM_TDEST_X failed"
          severity error;
        assert not has_x_in(bytes(config_c, bus_i.m))
          report prefix_c & " assertion AXI4STREAM_ERRM_TDATA_X failed"
          severity error;
        assert not has_x_in(strobe(config_c, bus_i.m))
          report prefix_c & " assertion AXI4STREAM_ERRM_TSTRB_X failed"
          severity error;
        assert not has_x_in(bus_i.m.last)
          report prefix_c & " assertion AXI4STREAM_ERRM_TLAST_X failed"
          severity error;
        assert not has_x_in(keep(config_c, bus_i.m))
          report prefix_c & " assertion AXI4STREAM_ERRM_TKEEP_X failed"
          severity error;
      end if;

      assert not has_x_in(bus_i.m.valid)
        report prefix_c & " assertion AXI4STREAM_ERRM_TVALID_X failed"
        severity error;
      assert not has_x_in(bus_i.s.ready)
        report prefix_c & " assertion AXI4STREAM_ERRM_TREADY_X failed"
        severity error;
      assert not has_x_in(user(config_c, bus_i.m))
        report prefix_c & " assertion AXI4STREAM_ERRM_TUSER_X failed"
        severity error;
    end if;
  end process;

  -- Unchecked: AXI4STREAM_ERRM_STREAM_ALL_DONE_EOS

  tkeep_tstrb: process is
  begin
    wait until rising_edge(clock_i);

    if reset_n_i = '1' and is_valid(config_c, bus_i.m) then
      assert not any_set((not keep(config_c, bus_i.m)) and strobe(config_c, bus_i.m))
        report prefix_c & " assertion AXI4STREAM_ERRM_TKEEP_TSTRB failed"
        severity error;
    end if;
  end process;
  
  -- Unchecked: AXI4STREAM_ERRM_TDATA_TIEOFF
  -- Unchecked: AXI4STREAM_ERRM_TKEEP_TIEOFF
  -- Unchecked: AXI4STREAM_ERRM_TSTRB_TIEOFF
  -- Unchecked: AXI4STREAM_ERRM_TID_TIEOFF
  -- Unchecked: AXI4STREAM_ERRM_TDEST_TIEOFF
  -- Unchecked: AXI4STREAM_ERRM_TUSER_TIEOFF
  
end architecture;
