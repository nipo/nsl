library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.sram_io.all;

-- Pin logic of a synchronous SRAM controller.
--
-- Everything here is portable: an SDR bus at the rates a fabric
-- reaches needs no vendor primitive beyond the one that forwards a
-- clock to a pin, and nsl_io.clock already owns that.  A DRAM lane is
-- the opposite case, which is why its PHYs are per backend.
--
-- The forwarded clock is half a period behind the controller's, so
-- the part samples the pins in the middle of the window they are held
-- for.  That is half a period of setup and half of hold, which is all
-- the margin there is to hand out without a phase shifter.  It is why
-- the clock comes off a double rate output driven with the pattern
-- inverted rather than off nsl_io.clock, which forwards a clock in
-- phase and would hand the part no setup at all.
--
-- Output enable is tied asserted.  The part tri-states its bus for
-- every cycle that is not a read -- writes, write aborts, deselects
-- alike, and writes regardless of what output enable says -- so
-- gating it would buy nothing and put its own access time in the read
-- path.
--
-- Every pin this drives is the Q of a register and nothing else, and
-- a pad only takes a register in when three things hold at once:
--
--  * the register drives that pad alone, which is why the tri-state
--    control is carried one copy per pin rather than shared,
--
--  * nothing stands between the register and the pad, which is why
--    the tri-state control is held in the sense the pad's own control
--    takes rather than as an enable -- an inversion on the way out is
--    a lookup table, and a pin behind a lookup table is a pin left in
--    the fabric,
--
--  * the value register and the tri-state register beside it answer
--    to the same reset, because a pad's pair of output registers
--    share one reset input between them.  That is why the payload
--    pipeline is reset at all: it has no state that needs clearing,
--    only a neighbour whose reset it has to match.
--
-- Miss any of the three and the bus leaves its pins a nanosecond and
-- a half behind the command pins, which on a source synchronous bus
-- is the margin.
entity sram_phy is
  generic(
    part_c: sram_part_t;
    timing_c: sram_timing_t;
    read_delay_ck_c: natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    io_i: in master_t;
    io_o: out slave_t;

    clock_o: out std_ulogic;
    cs_n_o: out std_ulogic;
    cen_n_o: out std_ulogic;
    we_n_o: out std_ulogic;
    bw_n_o: out std_ulogic_vector;
    oe_n_o: out std_ulogic;
    a_o: out unsigned;
    dq_o: out nsl_io.io.tristated_vector;
    dq_i: in std_ulogic_vector;
    dqp_o: out nsl_io.io.tristated_vector;
    dqp_i: in std_ulogic_vector
    );
end entity;

architecture beh of sram_phy is

  constant lane_count_c: natural := part_c.dq_byte_count;

  -- A write's payload reaches the pins its write latency after its
  -- command does, so it walks one more register than the command on
  -- its way out.
  constant write_pipe_c: natural := timing_c.write_latency;

  constant dq_bit_c: natural := lane_count_c * 8;

  type payload_t is
  record
    -- Whether the bus is left to the part this cycle, one copy per
    -- pin and asserted high, which is the sense a pad's tri-state
    -- control takes.  Held that way round so that the register's Q is
    -- the pad's control with nothing in between; an enable would have
    -- to be inverted on its way there and the inverter is what keeps
    -- the pin out of its pad.
    dq_hiz: std_ulogic_vector(dq_bit_c - 1 downto 0);
    dqp_hiz: std_ulogic_vector(lane_count_c - 1 downto 0);
    data: dq_t;
    parity: lane_bits_t;
  end record;

  type payload_vector is array (natural range <>) of payload_t;

  type regs_t is
  record
    -- Command registers, driving the pins
    cs_n: std_ulogic;
    we_n: std_ulogic;
    -- One per byte lane, so each has a pad to itself.  A master that
    -- never masks a byte makes them all the same function and the
    -- tools keep one copy, which then has two pads to reach and stays
    -- in the fabric; that is a property of the traffic rather than of
    -- this, and there is nothing here that can prevent it.
    bw_n: lane_bits_t;
    address: unsigned(max_address_width_c - 1 downto 0);

    -- Write payload on its way to the pins; the last stage drives them
    payload: payload_vector(0 to write_pipe_c);

    -- Cycles a read is away from its data being on io_o; the last
    -- stage is loaded by the same edge that captures the bus
    expected: std_ulogic_vector(0 to read_delay_ck_c - 1);
    capture: std_ulogic_vector(dq_i'length - 1 downto 0);
    capture_parity: std_ulogic_vector(dqp_i'length - 1 downto 0);
  end record;

  signal r, rin: regs_t;

  signal forward_s: nsl_io.diff.diff_pair;

begin

  assert read_delay_ck_c >= 1
    report "sram_phy: a read takes at least the capture register"
    severity failure;

  assert dq_i'length = lane_count_c * 8
    report "sram_phy: data bus is not the part's width"
    severity failure;

  forward_s.p <= clock_i;
  forward_s.n <= not clock_i;

  forward: nsl_io.ddr.ddr_output
    port map(
      clock_i => forward_s,
      d_i => "10",
      dd_o => clock_o
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cs_n <= '1';
      -- The payload itself has nothing to clear, and is cleared
      -- anyway: a pad's value register and its tri-state register
      -- answer to one reset input between them, so a payload left
      -- without one keeps the pins it drives out of their pads.
      for i in 0 to write_pipe_c
      loop
        r.payload(i).dq_hiz <= (others => '1');
        r.payload(i).dqp_hiz <= (others => '1');
        r.payload(i).data <= (others => (others => '0'));
        r.payload(i).parity <= (others => '0');
      end loop;
      r.expected <= (others => '0');
    end if;
  end process;

  transition: process(r, io_i, dq_i, dqp_i) is
  begin
    rin <= r;

    rin.cs_n <= not io_i.valid;
    rin.we_n <= not io_i.write;
    rin.address <= io_i.address;
    rin.bw_n <= (others => '1');
    if io_i.valid = '1' and io_i.write = '1' then
      rin.bw_n <= io_i.wmask;
    end if;

    rin.payload(0).dq_hiz <= (others => not (io_i.valid and io_i.write));
    rin.payload(0).dqp_hiz <= (others => not (io_i.valid and io_i.write));
    rin.payload(0).data <= io_i.wdata;
    rin.payload(0).parity <= io_i.wparity;
    for i in 1 to write_pipe_c
    loop
      rin.payload(i) <= r.payload(i - 1);
    end loop;

    rin.expected(0) <= io_i.valid and not io_i.write;
    for i in 1 to read_delay_ck_c - 1
    loop
      rin.expected(i) <= r.expected(i - 1);
    end loop;

    rin.capture <= dq_i;
    rin.capture_parity <= dqp_i;
  end process;

  moore: process(r) is
    variable word: byte_string(0 to lane_count_c - 1);
    variable parity: std_ulogic_vector(0 to lane_count_c - 1);
    variable payload: payload_t;
  begin
    cs_n_o <= r.cs_n;
    we_n_o <= r.we_n;
    a_o <= resize(r.address, a_o'length);
    for i in 0 to lane_count_c - 1
    loop
      bw_n_o(bw_n_o'low + i) <= r.bw_n(i);
    end loop;

    -- Clock enable is never used to stall: a core buffers a whole
    -- burst before it starts one, so the pipeline runs at a constant
    -- rate and select carries what an idle cycle needs.
    cen_n_o <= '0';
    oe_n_o <= '0';

    -- A constant index: the beat that goes to the pins is chosen by
    -- which register holds it, not by a multiplexer reading a counter.
    payload := r.payload(write_pipe_c);
    -- The tri-state control is inverted back into an enable here
    -- because that is what the pad driver takes, and a pad driver
    -- inverts it again on its way to the silicon.  The two cancel, so
    -- what reaches the pad is the register.
    for i in 0 to lane_count_c - 1
    loop
      dqp_o(dqp_o'low + i)
        <= nsl_io.io.to_tristated(payload.parity(i),
                                  not payload.dqp_hiz(i));
      for b in 0 to 7
      loop
        dq_o(dq_o'low + i * 8 + b)
          <= nsl_io.io.to_tristated(payload.data(i)(b),
                                    not payload.dq_hiz(i * 8 + b));
      end loop;
    end loop;

    for i in 0 to lane_count_c - 1
    loop
      word(i) := r.capture(r.capture'low + i * 8 + 7
                           downto r.capture'low + i * 8);
      parity(i) := r.capture_parity(r.capture_parity'low + i);
    end loop;

    io_o <= rdata_beat(part_c, word, parity);
    io_o.rdata_valid <= r.expected(read_delay_ck_c - 1);
  end process;

end architecture;
