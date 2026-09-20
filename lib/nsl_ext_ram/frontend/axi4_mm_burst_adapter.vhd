library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_math, nsl_logic, nsl_ext_ram;
use nsl_math.arith.all;
use nsl_logic.bool.all;
use nsl_amba.axi4_mm.all;
use nsl_data.bytestream.all;
use nsl_ext_ram.burst.all;

-- Turns AXI transactions into whole-burst memory accesses.
--
-- The core only ever moves a full burst, so a transaction that starts
-- or ends inside one is padded with fully masked beats on writes and
-- has the surplus beats dropped on reads.  Nothing is buffered here:
-- padding is generated on the fly and the beats a transaction does
-- want pass straight through.
--
-- Only incrementing bursts at the full bus width are served.  A
-- wrapping or fixed burst, or a narrow one, is answered with a slave
-- error: reordering their beats would need a buffer this adapter does
-- not have.
--
-- The commands of a transaction run ahead of its payload rather than
-- taking a cycle each between bursts.  How far ahead is the core's
-- business: it stops taking commands when it has as many as it can
-- hold, and it matches payload cycles to commands by order.  This is
-- what keeps a core that answers a read several cycles later from
-- having to wait for the next address afterwards, and it is why the
-- last burst of a transaction is worked out when its address arrives.
--
-- The first burst is commanded from the address beat itself, on the
-- cycle it is taken.  That is one burst of head start over the first
-- payload cycle, and it is what a core that decodes its queue head a
-- cycle before it schedules it needs to schedule the first burst as
-- early as it schedules the rest.  Nothing waits on it: an address
-- beat is taken whether or not the core had room for its command, and
-- the cursor starts on the burst the core did not take.
entity axi4_mm_burst_adapter is
  generic(
    axi_config_c: config_t;
    cycle_byte_count_c: natural;
    burst_cycle_count_c: natural
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    axi_i: in master_t;
    axi_o: out slave_t;

    cmd_o: out cmd_t;
    cmd_i: in cmd_ack_t;
    wdata_o: out wdata_t;
    wdata_i: in wdata_ack_t;
    rdata_i: in rdata_t;
    rdata_o: out rdata_ack_t;

    ready_i: in std_ulogic
    );
end entity;

architecture beh of axi4_mm_burst_adapter is

  constant burst_byte_l2_c: natural := log2(burst_cycle_count_c
                                                 * cycle_byte_count_c);
  constant cycle_byte_l2_c: natural := log2(cycle_byte_count_c);
  constant address_width_c: natural := axi_config_c.address_width;

  subtype addr_t is unsigned(address_width_c - 1 downto 0);

  constant burst_step_c: addr_t
    := to_unsigned(2 ** burst_byte_l2_c, address_width_c);

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WRITE,
    ST_WRITE_RESPONSE,
    ST_READ,
    ST_ERROR_READ,
    ST_ERROR_WRITE_DATA,
    ST_ERROR_WRITE_RESPONSE
    );

  type regs_t is
  record
    state: state_t;
    txn: transaction_t;
    -- Beat index inside the burst the payload is at
    position: natural range 0 to 2 ** 5 - 1;
    -- Burst the payload is at
    line: addr_t;
    -- Burst to command next, and the last one the transaction touches
    cmd_line: addr_t;
    last_line: addr_t;
    -- Every burst of the transaction has been commanded
    cmd_done: std_ulogic;
    -- Every payload cycle of the transaction has been moved
    data_done: std_ulogic;
    -- Last beat of the transaction has gone through
    finished: std_ulogic;
  end record;

  signal r, rin: regs_t;

  -- Burst a byte address belongs to, and the beat it sits at inside it.
  function line_of(address: unsigned) return addr_t
  is
    variable ret: addr_t;
  begin
    ret := resize(address, address_width_c);
    ret(burst_byte_l2_c - 1 downto 0) := (others => '0');

    return ret;
  end function;

  function position_of(address: unsigned) return natural
  is
    alias a: unsigned(address'length - 1 downto 0) is address;
  begin
    if burst_byte_l2_c = cycle_byte_l2_c then
      return 0;
    end if;

    return to_integer(a(burst_byte_l2_c - 1 downto cycle_byte_l2_c));
  end function;

  -- Burst the first beat of a transaction falls in, taken from its
  -- address beat: the first command goes out on the cycle that beat
  -- is taken, a cycle before there is a state to hold it in.
  function first_line_of(addr: address_t) return addr_t
  is
  begin
    return line_of(resize(address(axi_config_c, addr), address_width_c));
  end function;

  -- Only an incrementing burst at the full bus width can be padded
  -- and trimmed without reordering anything.
  function serviceable(addr: address_t) return boolean
  is
  begin
    return burst(axi_config_c, addr) = BURST_INCR
      and size_l2(axi_config_c, addr) = to_unsigned(cycle_byte_l2_c, 3);
  end function;

  -- Burst the last beat of a transaction falls in, taken from its
  -- address beat: the commands have to know where to stop without
  -- waiting for the payload to tell them.
  function last_line_of(addr: address_t) return addr_t
  is
    variable beats_m1: addr_t;
  begin
    beats_m1 := resize(length_m1(axi_config_c, addr, address_width_c),
                       address_width_c);

    return line_of(resize(address(axi_config_c, addr), address_width_c)
                   + shift_left(beats_m1, cycle_byte_l2_c));
  end function;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, axi_i, cmd_i, wdata_i, rdata_i, ready_i) is
    variable beat_address: addr_t;
    variable wanted: boolean;
    variable transferred: boolean;
    variable last_burst: boolean;
    variable commands_over: boolean;
    variable payload_over: boolean;
    variable done_now: boolean;
  begin
    rin <= r;

    beat_address := resize(address(axi_config_c, r.txn), address_width_c);
    -- A beat is wanted at this position only while the transaction is
    -- still inside the burst the core is filling or draining.
    wanted := is_valid(axi_config_c, r.txn)
              and line_of(beat_address) = r.line
              and position_of(beat_address) = r.position;

    -- The command side of a transaction is behind us once the burst
    -- its last beat falls in has been taken.
    last_burst := r.cmd_line = r.last_line;
    commands_over := r.cmd_done = '1'
                     or (cmd_i.ready = '1' and last_burst);

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if ready_i = '1' then
          if is_valid(axi_config_c, axi_i.aw) then
            rin.txn <= transaction(axi_config_c, axi_i.aw);
            if serviceable(axi_i.aw) then
              -- The first command of the transaction is offered on the
              -- cycle its address beat is taken, so the core has the
              -- access a cycle before a state could have held it out.
              -- The cursor starts on the burst after it when the core
              -- took it, and on it when it did not.
              rin.line <= first_line_of(axi_i.aw);
              rin.last_line <= last_line_of(axi_i.aw);
              rin.position <= 0;
              rin.data_done <= '0';
              rin.finished <= '0';
              rin.cmd_done <= '0';
              if cmd_i.ready = '1' then
                rin.cmd_line <= first_line_of(axi_i.aw) + burst_step_c;
                rin.cmd_done <= to_logic(first_line_of(axi_i.aw)
                                         = last_line_of(axi_i.aw));
              else
                rin.cmd_line <= first_line_of(axi_i.aw);
              end if;
              rin.state <= ST_WRITE;
            else
              rin.state <= ST_ERROR_WRITE_DATA;
            end if;
          elsif is_valid(axi_config_c, axi_i.ar) then
            rin.txn <= transaction(axi_config_c, axi_i.ar);
            if serviceable(axi_i.ar) then
              rin.line <= first_line_of(axi_i.ar);
              rin.last_line <= last_line_of(axi_i.ar);
              rin.position <= 0;
              rin.data_done <= '0';
              rin.finished <= '0';
              rin.cmd_done <= '0';
              if cmd_i.ready = '1' then
                rin.cmd_line <= first_line_of(axi_i.ar) + burst_step_c;
                rin.cmd_done <= to_logic(first_line_of(axi_i.ar)
                                         = last_line_of(axi_i.ar));
              else
                rin.cmd_line <= first_line_of(axi_i.ar);
              end if;
              rin.state <= ST_READ;
            else
              rin.state <= ST_ERROR_READ;
            end if;
          end if;
        end if;

      when ST_WRITE =>
        if r.cmd_done = '0' and cmd_i.ready = '1' then
          if last_burst then
            rin.cmd_done <= '1';
          else
            rin.cmd_line <= r.cmd_line + burst_step_c;
          end if;
        end if;

        -- A beat the transaction owns only moves when the master has
        -- one to give; a padding beat only needs the core.
        transferred := false;
        if r.data_done = '0' then
          if wanted then
            if wdata_i.ready = '1' and is_valid(axi_config_c, axi_i.w) then
              transferred := true;
              rin.txn <= step(axi_config_c, r.txn);
              if is_last(axi_config_c, r.txn) then
                rin.finished <= '1';
              end if;
            end if;
          elsif wdata_i.ready = '1' then
            transferred := true;
          end if;
        end if;

        done_now := r.finished = '1'
                    or (transferred and wanted
                        and is_last(axi_config_c, r.txn));

        payload_over := r.data_done = '1'
                        or (transferred
                            and r.position = burst_cycle_count_c - 1
                            and done_now);

        if transferred then
          if r.position = burst_cycle_count_c - 1 then
            rin.position <= 0;
            if done_now then
              rin.data_done <= '1';
            else
              rin.line <= r.line + burst_step_c;
            end if;
          else
            rin.position <= r.position + 1;
          end if;
        end if;

        -- The response waits for the commands as well as the payload:
        -- a command still held here has not reached the array.
        if payload_over and commands_over then
          rin.state <= ST_WRITE_RESPONSE;
        end if;

      when ST_WRITE_RESPONSE =>
        if is_ready(axi_config_c, axi_i.b) then
          rin.state <= ST_IDLE;
        end if;

      when ST_READ =>
        if r.cmd_done = '0' and cmd_i.ready = '1' then
          if last_burst then
            rin.cmd_done <= '1';
          else
            rin.cmd_line <= r.cmd_line + burst_step_c;
          end if;
        end if;

        transferred := false;
        if r.data_done = '0' then
          if wanted then
            if rdata_i.valid = '1' and is_ready(axi_config_c, axi_i.r) then
              transferred := true;
              rin.txn <= step(axi_config_c, r.txn);
              if is_last(axi_config_c, r.txn) then
                rin.finished <= '1';
              end if;
            end if;
          elsif rdata_i.valid = '1' then
            transferred := true;
          end if;
        end if;

        done_now := r.finished = '1'
                    or (transferred and wanted
                        and is_last(axi_config_c, r.txn));

        payload_over := r.data_done = '1'
                        or (transferred
                            and r.position = burst_cycle_count_c - 1
                            and done_now);

        if transferred then
          if r.position = burst_cycle_count_c - 1 then
            rin.position <= 0;
            if done_now then
              rin.data_done <= '1';
            else
              rin.line <= r.line + burst_step_c;
            end if;
          else
            rin.position <= r.position + 1;
          end if;
        end if;

        if payload_over and commands_over then
          rin.state <= ST_IDLE;
        end if;

      when ST_ERROR_WRITE_DATA =>
        if is_valid(axi_config_c, axi_i.w) then
          if is_last(axi_config_c, axi_i.w) then
            rin.state <= ST_ERROR_WRITE_RESPONSE;
          end if;
        end if;

      when ST_ERROR_WRITE_RESPONSE =>
        if is_ready(axi_config_c, axi_i.b) then
          rin.state <= ST_IDLE;
        end if;

      when ST_ERROR_READ =>
        if is_ready(axi_config_c, axi_i.r) then
          if is_last(axi_config_c, r.txn) then
            rin.state <= ST_IDLE;
          else
            rin.txn <= step(axi_config_c, r.txn);
          end if;
        end if;
    end case;
  end process;

  mealy: process(r, axi_i, cmd_i, wdata_i, rdata_i, ready_i) is
    variable beat_address: addr_t;
    variable wanted: boolean;
    variable pad: std_ulogic_vector(0 to cycle_byte_count_c - 1);
  begin
    axi_o <= slave_t'(aw => accept(axi_config_c, false),
                      w => accept(axi_config_c, false),
                      b => write_response_defaults(axi_config_c),
                      ar => accept(axi_config_c, false),
                      r => read_data_defaults(axi_config_c));
    cmd_o <= cmd_idle;
    wdata_o <= wdata_idle;
    rdata_o <= accept(false);

    beat_address := resize(address(axi_config_c, r.txn), address_width_c);
    wanted := is_valid(axi_config_c, r.txn)
              and line_of(beat_address) = r.line
              and position_of(beat_address) = r.position;
    pad := (others => '1');

    case r.state is
      when ST_IDLE =>
        -- Nothing is taken in before the controller has finished its
        -- power-up sequence, or the transaction would be dropped.
        -- The first command of a transaction the core can serve is
        -- offered beside its address beat.  Nothing waits on it: the
        -- address goes through either way and the cursor picks up
        -- where the core left it.
        if ready_i = '1' then
          axi_o.aw <= accept(axi_config_c, true);
          axi_o.ar <= accept(axi_config_c,
                             not is_valid(axi_config_c, axi_i.aw));

          if is_valid(axi_config_c, axi_i.aw) then
            if serviceable(axi_i.aw) then
              cmd_o <= cmd_request(first_line_of(axi_i.aw), true);
            end if;
          elsif is_valid(axi_config_c, axi_i.ar) then
            if serviceable(axi_i.ar) then
              cmd_o <= cmd_request(first_line_of(axi_i.ar), false);
            end if;
          end if;
        end if;

      when ST_WRITE =>
        if r.cmd_done = '0' then
          cmd_o <= cmd_request(r.cmd_line, true);
        end if;

        if r.data_done = '0' then
          if wanted then
            wdata_o <= wdata_beat(
              bytes(axi_config_c, axi_i.w)(0 to cycle_byte_count_c - 1),
              not strb(axi_config_c, axi_i.w)(0 to cycle_byte_count_c - 1));
            wdata_o.valid <= to_logic(is_valid(axi_config_c, axi_i.w));
            axi_o.w <= accept(axi_config_c, wdata_i.ready = '1');
          else
            -- Nothing from the transaction lands here, so the burst
            -- gets a beat the array will ignore.
            wdata_o <= wdata_beat(
              (0 to cycle_byte_count_c - 1 => dontcare_byte_c), pad);
          end if;
        end if;

      when ST_WRITE_RESPONSE =>
        axi_o.b <= write_response(axi_config_c,
                                  id => id(axi_config_c, r.txn),
                                  resp => RESP_OKAY);

      when ST_READ =>
        if r.cmd_done = '0' then
          cmd_o <= cmd_request(r.cmd_line, false);
        end if;

        if r.data_done = '0' then
          if wanted then
            axi_o.r <= read_data(axi_config_c,
                                 id => id(axi_config_c, r.txn),
                                 bytes => rdata_i.data(0 to cycle_byte_count_c - 1),
                                 last => is_last(axi_config_c, r.txn),
                                 valid => rdata_i.valid = '1');
            rdata_o <= accept(is_ready(axi_config_c, axi_i.r));
          else
            rdata_o <= accept(true);
          end if;
        end if;

      when ST_ERROR_WRITE_DATA =>
        axi_o.w <= accept(axi_config_c, true);

      when ST_ERROR_WRITE_RESPONSE =>
        axi_o.b <= write_response(axi_config_c,
                                  id => id(axi_config_c, r.txn),
                                  resp => RESP_SLVERR);

      when ST_ERROR_READ =>
        axi_o.r <= read_data(axi_config_c,
                             id => id(axi_config_c, r.txn),
                             bytes => (0 to cycle_byte_count_c - 1
                                       => dontcare_byte_c),
                             resp => RESP_SLVERR,
                             last => is_last(axi_config_c, r.txn));

      when others =>
        null;
    end case;
  end process;

end architecture;
