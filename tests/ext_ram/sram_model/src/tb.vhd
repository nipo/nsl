library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_io, nsl_data, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;

-- Drives a synchronous SRAM model pin by pin, one command per clock,
-- and reads back what the datasheet says should come out.
--
-- The part's own pipeline is the thing under test: a command's write
-- data is taken two rises after the command and its read data appears
-- one rise after it, so the bench keeps three commands in flight and
-- looks at a different one of them on each of the three counts.  That
-- is also what proves a read may follow a write with nothing in
-- between.
entity tb is
end entity;

architecture beh of tb is

  constant part_c: sram_part_t := cy7c1462av25_c;
  constant tck_c: time := 10 ns;

  -- Clock to output of the bench's own drivers.  Without one the
  -- model's hold checks would see every pin move on the edge that
  -- samples it, which no device does.
  constant tco_c: time := 1 ns;

  constant lane_c: natural := part_c.dq_byte_count;

  subtype word_t is byte_string(0 to lane_c - 1);
  subtype lanes_t is std_ulogic_vector(0 to lane_c - 1);

  type op_t is (OP_NOP, OP_READ, OP_WRITE);

  type step_t is
  record
    op: op_t;
    address: natural;
    lane_n: lanes_t;
    data: word_t;
    expect: word_t;
  end record;

  type step_vector is array (natural range <>) of step_t;

  function nop return step_t
  is
  begin
    return (op => OP_NOP,
            address => 0,
            lane_n => (others => '1'),
            data => (others => dontcare_byte_c),
            expect => (others => dontcare_byte_c));
  end function;

  function wr(address: natural;
              data: byte_string;
              lane_n: std_ulogic_vector := "00") return step_t
  is
    alias data_v: byte_string(0 to lane_c - 1) is data;
    alias lane_v: lanes_t is lane_n;
  begin
    return (op => OP_WRITE,
            address => address,
            lane_n => lane_v,
            data => data_v,
            expect => (others => dontcare_byte_c));
  end function;

  function rd(address: natural; expect: byte_string) return step_t
  is
    alias expect_v: byte_string(0 to lane_c - 1) is expect;
  begin
    return (op => OP_READ,
            address => address,
            lane_n => (others => '1'),
            data => (others => dontcare_byte_c),
            expect => expect_v);
  end function;

  constant unwritten_c: word_t := (others => (others => 'U'));

  -- Byte lane 0 is the low half of the bus, lane 1 the high half.
  constant script_c: step_vector := (
    -- A whole word written, then read back.
    wr(16#100#, (x"34", x"12")),
    nop,
    nop,
    rd(16#100#, (x"34", x"12")),
    nop,
    nop,

    -- One lane written; the other keeps what it had.
    wr(16#100#, (x"bb", x"aa"), lane_n => "01"),
    nop,
    nop,
    rd(16#100#, (x"bb", x"12")),
    nop,
    nop,

    -- Write with no lane selected leaves the array alone, so the
    -- location still reads as never written.
    wr(16#200#, (x"ff", x"ff"), lane_n => "11"),
    nop,
    nop,
    rd(16#200#, unwritten_c),
    nop,
    nop,

    -- Nothing between a write and a read, either way round, which is
    -- the whole of what "no bus latency" buys.
    wr(16#300#, (x"aa", x"bb")),
    rd(16#100#, (x"bb", x"12")),
    wr(16#301#, (x"cc", x"dd")),
    rd(16#300#, (x"aa", x"bb")),
    rd(16#301#, (x"cc", x"dd")),
    wr(16#302#, (x"ee", x"ff")),
    rd(16#302#, (x"ee", x"ff")),
    nop,
    nop,
    nop
    );

  signal clock_s: std_ulogic := '0';
  signal stopped_s: boolean := false;

  signal cs_n_s: std_ulogic := '1';
  signal cen_n_s: std_ulogic := '0';
  signal we_n_s: std_ulogic := '1';
  signal bw_n_s: lanes_t := (others => '1');
  signal oe_n_s: std_ulogic := '0';
  signal a_s: unsigned(part_c.address_width - 1 downto 0) := (others => '0');

  signal dq_bench_s: nsl_io.io.tristated_vector(lane_c * 8 - 1 downto 0)
    := (others => nsl_io.io.tristated_z);
  signal dqp_bench_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0)
    := (others => nsl_io.io.tristated_z);
  signal dq_model_s: nsl_io.io.tristated_vector(lane_c * 8 - 1 downto 0);
  signal dqp_model_s: nsl_io.io.tristated_vector(lane_c - 1 downto 0);
  signal dq_wire_s: std_logic_vector(lane_c * 8 - 1 downto 0);
  signal dqp_wire_s: std_logic_vector(lane_c - 1 downto 0);
  signal dq_value_s: std_ulogic_vector(lane_c * 8 - 1 downto 0);
  signal dqp_value_s: std_ulogic_vector(lane_c - 1 downto 0);
  signal violation_count_s: natural;

begin

  clock_s <= (not clock_s) after tck_c / 2 when not stopped_s else '0';

  dq_wiring: for i in dq_wire_s'range
  generate
    dq_wire_s(i) <= nsl_io.io.to_logic(dq_bench_s(i));
    dq_wire_s(i) <= nsl_io.io.to_logic(dq_model_s(i));
  end generate;

  dqp_wiring: for i in dqp_wire_s'range
  generate
    dqp_wire_s(i) <= nsl_io.io.to_logic(dqp_bench_s(i));
    dqp_wire_s(i) <= nsl_io.io.to_logic(dqp_model_s(i));
  end generate;

  dq_value_s <= std_ulogic_vector(dq_wire_s);
  dqp_value_s <= std_ulogic_vector(dqp_wire_s);

  model: nsl_ext_ram.simulation.sram_model
    generic map(
      part_c => part_c
      )
    port map(
      clock_i => clock_s,
      cs_n_i => cs_n_s,
      cen_n_i => cen_n_s,
      we_n_i => we_n_s,
      bw_n_i => bw_n_s,
      oe_n_i => oe_n_s,
      a_i => a_s,
      dq_i => dq_value_s,
      dq_o => dq_model_s,
      dqp_i => dqp_value_s,
      dqp_o => dqp_model_s,
      violation_count_o => violation_count_s
      );

  watchdog: process is
  begin
    wait for 10 ms;
    assert stopped_s
      report "watchdog fired, the bench is stuck"
      severity failure;
    wait;
  end process;

  -- One rise carries three commands at once: the one going out, the
  -- one whose payload the part is about to take, and the one whose
  -- answer is on the bus already.
  stim: process is
    -- Stage 0 is the command going out this rise, stage 2 the one
    -- whose payload the part takes next rise, stage 3 the one whose
    -- answer has been on the bus since the last rise.
    variable stage: step_vector(0 to 3);
    variable seen: word_t;
    variable errors: natural := 0;

    procedure drive(step: in step_t) is
    begin
      case step.op is
        when OP_NOP =>
          cs_n_s <= '1' after tco_c;
          we_n_s <= '1' after tco_c;
          bw_n_s <= (others => '1') after tco_c;
          a_s <= (others => '0') after tco_c;

        when OP_READ =>
          cs_n_s <= '0' after tco_c;
          we_n_s <= '1' after tco_c;
          bw_n_s <= (others => '1') after tco_c;
          a_s <= to_unsigned(step.address, a_s'length) after tco_c;

        when OP_WRITE =>
          cs_n_s <= '0' after tco_c;
          we_n_s <= '0' after tco_c;
          bw_n_s <= step.lane_n after tco_c;
          a_s <= to_unsigned(step.address, a_s'length) after tco_c;
      end case;
    end procedure;

    procedure release is
    begin
      for i in dq_bench_s'range
      loop
        dq_bench_s(i) <= nsl_io.io.tristated_z after tco_c;
      end loop;
      for i in dqp_bench_s'range
      loop
        dqp_bench_s(i) <= nsl_io.io.tristated_z after tco_c;
      end loop;
    end procedure;

    procedure present(step: in step_t) is
    begin
      for i in 0 to lane_c - 1
      loop
        dqp_bench_s(dqp_bench_s'low + i)
          <= nsl_io.io.to_tristated('0') after tco_c;
        for b in 0 to 7
        loop
          dq_bench_s(dq_bench_s'low + i * 8 + b)
            <= nsl_io.io.to_tristated(step.data(i)(b)) after tco_c;
        end loop;
      end loop;
    end procedure;
  begin
    stage := (others => nop);

    -- The part wants its supply settled before anything is asked of
    -- it, and says so in its model.
    wait for part_c.power_ps * 1 ps;

    for i in 0 to script_c'length + 3
    loop
      wait until rising_edge(clock_s);

      stage(1 to 3) := stage(0 to 2);
      if i < script_c'length then
        stage(0) := script_c(i);
      else
        stage(0) := nop;
      end if;

      if stage(3).op = OP_READ then
        for lane in 0 to lane_c - 1
        loop
          seen(lane) := dq_value_s(dq_value_s'low + lane * 8 + 7
                                   downto dq_value_s'low + lane * 8);
        end loop;

        if seen /= stage(3).expect then
          errors := errors + 1;
          report "read of " & to_string(stage(3).address)
            & " answered " & to_string(seen)
            & ", expected " & to_string(stage(3).expect)
            severity error;
        end if;
      end if;

      drive(stage(0));

      if stage(2).op = OP_WRITE then
        present(stage(2));
      else
        release;
      end if;
    end loop;

    report "model bench done at " & time'image(now) & ", "
      & to_string(errors) & " mismatches, "
      & to_string(violation_count_s) & " datasheet violations";

    assert violation_count_s = 0
      report integer'image(violation_count_s)
      & " datasheet constraints were broken on the part's pins"
      severity failure;

    stopped_s <= true;
    -- The count itself is in the report above; the exit status only
    -- has to be non-zero, and a count that is a multiple of 256 would
    -- not be.
    if errors + violation_count_s = 0 then
      nsl_simulation.control.terminate(0);
    else
      nsl_simulation.control.terminate(1);
    end if;
    wait;
  end process;

end architecture;
