library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_ext_ram;
use nsl_math.arith.all;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.burst.all;
use nsl_ext_ram.sram_io.all;

-- Turns whole-burst accesses into single word accesses on a
-- synchronous SRAM.
--
-- The part has no banks, no rows and nothing to refresh, so there is
-- no scheduling to do: a burst is a run of consecutive addresses
-- issued one per cycle.  What the core does own is the buffering that
-- keeps that run unbroken.  A write burst is collected in full before
-- the first address goes out and a read burst is collected in full
-- before the first beat comes back, so neither the user side nor the
-- memory bus can stall the other half way through.  On a part whose
-- reads and writes have the same latency, an unbroken run is the whole
-- of the performance argument.
--
-- The power-up wait is the entire init sequence: the part needs its
-- supply stable for a while and then answers.
entity sram_core is
  generic(
    part_c: sram_part_t;
    timing_c: sram_timing_t;
    -- Words one access transfers
    burst_cycle_count_c: natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    cmd_i: in cmd_t;
    cmd_o: out cmd_ack_t;
    wdata_i: in wdata_t;
    wdata_o: out wdata_ack_t;
    rdata_o: out rdata_t;
    rdata_i: in rdata_ack_t;

    -- Deasserted until the part is ready to be accessed
    ready_o: out std_ulogic;

    -- One cycle per read beat whose parity does not answer for its
    -- data.  A location that was never written has no parity to speak
    -- of and will report here.
    parity_error_o: out std_ulogic;

    io_o: out master_t;
    io_i: in slave_t
    );
end entity;

architecture beh of sram_core is

  constant lane_count_c: natural := part_c.dq_byte_count;
  constant lane_l2_c: natural := log2(lane_count_c);

  subtype word_t is byte_string(0 to lane_count_c - 1);
  subtype word_mask_t is std_ulogic_vector(0 to lane_count_c - 1);

  type word_vector is array (natural range <>) of word_t;
  type word_mask_vector is array (natural range <>) of word_mask_t;

  type state_t is (
    ST_RESET,
    ST_POWER_UP,
    ST_IDLE,
    ST_FILL,
    ST_ISSUE,
    ST_COLLECT,
    ST_DRAIN
    );

  type regs_t is
  record
    state: state_t;
    -- Ticks left before the part may be accessed
    power_left: natural range 0 to timing_c.power_up;

    write: std_ulogic;
    -- Word address of the first word of the access
    address: unsigned(part_c.address_width - 1 downto 0);

    data: word_vector(0 to burst_cycle_count_c - 1);
    mask: word_mask_vector(0 to burst_cycle_count_c - 1);

    -- Words taken from the user before the run starts
    filled: natural range 0 to burst_cycle_count_c;
    -- Words handed to the part so far
    issued: natural range 0 to burst_cycle_count_c;
    -- Words the part has answered so far
    collected: natural range 0 to burst_cycle_count_c;
    -- Words handed back to the user so far
    drained: natural range 0 to burst_cycle_count_c;

    parity_error: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  assert burst_cycle_count_c <= max_burst_cycle_count_c
    report "sram_core: burst is longer than the core supports"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.parity_error <= '0';
    end if;
  end process;

  transition: process(r, cmd_i, wdata_i, rdata_i, io_i) is
  begin
    rin <= r;

    rin.parity_error <= '0';

    -- A read's answer arrives on its own schedule, which may be while
    -- the rest of the burst is still going out.
    if io_i.rdata_valid = '1' and r.collected < burst_cycle_count_c then
      rin.data(r.collected) <= value(part_c, io_i.rdata);
      rin.collected <= r.collected + 1;

      if part_c.has_parity
        and lanes(part_c, io_i.rparity)
        /= lane_parity(value(part_c, io_i.rdata)) then
        rin.parity_error <= '1';
      end if;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_POWER_UP;
        rin.power_left <= timing_c.power_up;

      when ST_POWER_UP =>
        if r.power_left = 0 then
          rin.state <= ST_IDLE;
        else
          rin.power_left <= r.power_left - 1;
        end if;

      when ST_IDLE =>
        if cmd_i.valid = '1' then
          rin.write <= cmd_i.write;
          rin.address <= resize(cmd_i.address(cmd_i.address'left
                                              downto lane_l2_c),
                                part_c.address_width);
          rin.filled <= 0;
          rin.issued <= 0;
          rin.collected <= 0;
          rin.drained <= 0;

          if cmd_i.write = '1' then
            rin.state <= ST_FILL;
          else
            rin.state <= ST_ISSUE;
          end if;
        end if;

      when ST_FILL =>
        if wdata_i.valid = '1' then
          rin.data(r.filled) <= wdata_i.data(0 to lane_count_c - 1);
          rin.mask(r.filled) <= wdata_i.mask(0 to lane_count_c - 1);
          if r.filled = burst_cycle_count_c - 1 then
            rin.state <= ST_ISSUE;
          else
            rin.filled <= r.filled + 1;
          end if;
        end if;

      when ST_ISSUE =>
        if r.issued = burst_cycle_count_c - 1 then
          if r.write = '1' then
            rin.state <= ST_IDLE;
          else
            rin.state <= ST_COLLECT;
          end if;
        else
          rin.issued <= r.issued + 1;
        end if;

      when ST_COLLECT =>
        if r.collected = burst_cycle_count_c then
          rin.state <= ST_DRAIN;
        end if;

      when ST_DRAIN =>
        if rdata_i.ready = '1' then
          if r.drained = burst_cycle_count_c - 1 then
            rin.state <= ST_IDLE;
          else
            rin.drained <= r.drained + 1;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
    variable word_address: unsigned(part_c.address_width - 1 downto 0);
  begin
    cmd_o <= accept(false);
    wdata_o <= accept(false);
    rdata_o <= rdata_idle;
    ready_o <= '1';
    parity_error_o <= r.parity_error;
    io_o <= master_idle(part_c);

    word_address := r.address + r.issued;

    case r.state is
      when ST_RESET | ST_POWER_UP =>
        ready_o <= '0';

      when ST_IDLE =>
        cmd_o <= accept(true);

      when ST_FILL =>
        wdata_o <= accept(true);

      when ST_ISSUE =>
        if r.write = '1' then
          io_o <= write_command(part_c, word_address,
                                r.data(r.issued), r.mask(r.issued));
        else
          io_o <= read_command(part_c, word_address);
        end if;

      when ST_COLLECT =>
        null;

      when ST_DRAIN =>
        rdata_o <= rdata_beat(r.data(r.drained));
    end case;
  end process;

end architecture;
