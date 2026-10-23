library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_math, nsl_amba;
use nsl_data.bytestream.all;
use nsl_math.arith.all;
use nsl_amba.axi4_mm.all;
use nsl_amba.mm_traffic.all;

entity axi4_mm_memory_tester is
  generic(
    config_c: config_t;
    base_address_c: natural := 0;
    region_byte_l2_c: natural;
    burst_length_c: natural := 8;
    seed_c: natural := 1;
    scramble_c: boolean := false;
    outstanding_c: positive := 1
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    start_i: in std_ulogic;

    axi_o: out master_t;
    axi_i: in slave_t;

    busy_o: out std_ulogic;
    writing_o: out std_ulogic;
    done_o: out std_ulogic;
    error_count_o: out unsigned(31 downto 0);
    first_error_address_o: out unsigned(config_c.address_width - 1 downto 0)
    );
end entity;

architecture beh of axi4_mm_memory_tester is

  constant beat_byte_c: natural := 2 ** config_c.data_bus_width_l2;
  constant beat_byte_l2_c: natural := config_c.data_bus_width_l2;
  constant burst_byte_l2_c: natural := beat_byte_l2_c + log2(burst_length_c);
  constant index_width_c: natural := region_byte_l2_c - burst_byte_l2_c;
  constant seed_c_u: unsigned(31 downto 0) := to_unsigned(seed_c, 32);

  subtype index_t is unsigned(index_width_c - 1 downto 0);
  -- One more bit than an index, set once every transaction of the
  -- region has gone past.
  subtype count_t is unsigned(index_width_c downto 0);

  constant group_count_c: natural := group_count(beat_byte_c);

  -- A stage per round of the payload hash.  It costs a phase as many
  -- cycles to fill the pipe and nothing at all per beat: a beat is
  -- hashed while its predecessors are on the bus, and the hashing runs
  -- on across burst boundaries, so back to back beats stay back to
  -- back from one burst to the next, which for a part whose whole
  -- argument is that reads and writes need no turnaround is the point.
  constant pipe_depth_c: natural := mix_round_count_c;

  type stage_vector is array (natural range <>)
    of hash_vector(0 to group_count_c - 1);

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WRITE,
    ST_READ,
    ST_DONE
    );

  subtype credit_t is natural range 0 to outstanding_c;

  type regs_t is
  record
    state: state_t;
    -- Next transaction whose address goes out
    issue: count_t;
    -- Transaction and beat on the data channel
    data: count_t;
    beat: natural range 0 to 2 ** 8 - 1;
    -- Transactions that may still be started on the address channel,
    -- and, while writing, on the write data channel.  Both come back
    -- on the write response, or on the last read beat.
    --
    -- Write data does not wait for its address: a master must not
    -- make WVALID depend on AWREADY, and a slave is allowed to hold
    -- AWREADY until it sees write data.  Each channel then has its
    -- own budget, so neither waits on the other.
    issue_credit: credit_t;
    data_credit: credit_t;
    -- The beat whose hash is entering the pipe, which runs ahead of
    -- the one on the bus by the pipe's depth
    hash_index: index_t;
    hash_beat: natural range 0 to 2 ** 8 - 1;
    filling: natural range 0 to pipe_depth_c;
    stirred: stage_vector(0 to mix_round_count_c - 1);
    error_count: unsigned(31 downto 0);
    first_error: unsigned(config_c.address_width - 1 downto 0);
    had_error: std_ulogic;
  end record;

  signal r, rin: regs_t;

  -- Transactions are visited in index order, or in bit reversed index
  -- order, which is still a permutation of the region but lands
  -- somewhere else every time.
  function visit(index: index_t) return unsigned
  is
    variable ret: index_t;
  begin
    if not scramble_c then
      return index;
    end if;

    for i in ret'range
    loop
      ret(i) := index(index_width_c - 1 - i);
    end loop;

    return ret;
  end function;

  function transaction_address(index: index_t) return unsigned
  is
  begin
    return resize(to_unsigned(base_address_c, config_c.address_width)
                  + (resize(visit(index), config_c.address_width)
                     sll burst_byte_l2_c),
                  config_c.address_width);
  end function;

  function beat_address(index: index_t; beat: natural) return unsigned
  is
  begin
    return transaction_address(index)
      + to_unsigned(beat * beat_byte_c, config_c.address_width);
  end function;

  function index(count: count_t) return index_t
  is
  begin
    return count(index_width_c - 1 downto 0);
  end function;

  function is_over(count: count_t) return boolean
  is
  begin
    return count(index_width_c) = '1';
  end function;

  -- The payload of the beat on the bus, out of the far end of the pipe.
  function hashed_pattern(scaled: hash_vector) return byte_string
  is
    variable ret: hash_vector(0 to group_count_c - 1);
  begin
    for g in ret'range
    loop
      ret(g) := mix_fold(scaled(g));
    end loop;

    return group_bytes(ret, beat_byte_c);
  end function;

  function transaction_command(index: index_t) return address_t
  is
  begin
    return address(config_c,
                   addr => transaction_address(index),
                   id => (config_c.id_width - 1 downto 0 => '0'),
                   len_m1 => to_unsigned(burst_length_c - 1, config_c.len_width),
                   size_l2 => to_unsigned(beat_byte_l2_c, 3),
                   burst => BURST_INCR,
                   valid => true);
  end function;

begin

  assert region_byte_l2_c > burst_byte_l2_c
    report "memory_tester: region is not bigger than one transaction"
    severity failure;

  assert burst_length_c >= 1 and burst_length_c <= 2 ** config_c.len_width
    report "memory_tester: unsupported burst length"
    severity failure;

  -- Every register of the walker is cleared by the reset itself, and
  -- not by the state the reset leads to.  A held reset then means a
  -- walker that drives nothing and counts nothing, on any backend: a
  -- record whose state alone is reset is a record whose remaining
  -- registers a synthesiser is free to leave running, and what the
  -- outputs say while the reset is held is then whatever those
  -- registers wandered to.
  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.issue <= (others => '0');
      r.data <= (others => '0');
      r.beat <= 0;
      r.issue_credit <= 0;
      r.data_credit <= 0;
      r.hash_index <= (others => '0');
      r.hash_beat <= 0;
      r.filling <= 0;
      r.stirred <= (others => (others => (others => '0')));
      r.error_count <= (others => '0');
      r.first_error <= (others => '0');
      r.had_error <= '0';
    end if;
  end process;

  transition: process(r, start_i, axi_i) is
    variable writing, reading: boolean;
    variable owed, issued, sent, data_done, completed, advance: boolean;
  begin
    rin <= r;

    -- What changes hands this cycle, as the moore process below
    -- presents it.  Responses are only taken while one is owed: a
    -- slave has none to give otherwise, and the credits stay in range
    -- across the deltas where the slave has not yet caught up with a
    -- new r.
    writing := r.state = ST_WRITE;
    reading := r.state = ST_READ;
    owed := r.issue_credit /= outstanding_c
            and (reading or r.data_credit /= outstanding_c);
    issued := r.issue_credit /= 0 and not is_over(r.issue)
              and ((writing and is_ready(config_c, axi_i.aw))
                   or (reading and is_ready(config_c, axi_i.ar)));
    sent := r.filling = pipe_depth_c
            and ((writing and r.data_credit /= 0 and not is_over(r.data)
                  and is_ready(config_c, axi_i.w))
                 or (reading and owed and is_valid(config_c, axi_i.r)));
    data_done := sent and r.beat = burst_length_c - 1;
    completed := (writing and owed and is_valid(config_c, axi_i.b))
                 or (reading and data_done);
    advance := sent or ((writing or reading) and r.filling /= pipe_depth_c);

    if issued then
      rin.issue <= r.issue + 1;
    end if;

    if issued and not completed then
      rin.issue_credit <= r.issue_credit - 1;
    elsif completed and not issued then
      rin.issue_credit <= r.issue_credit + 1;
    end if;

    if data_done and not completed then
      rin.data_credit <= r.data_credit - 1;
    elsif completed and not data_done then
      rin.data_credit <= r.data_credit + 1;
    end if;

    if sent then
      if data_done then
        rin.beat <= 0;
        rin.data <= r.data + 1;
      else
        rin.beat <= r.beat + 1;
      end if;
    end if;

    if reading and sent then
      if bytes(config_c, axi_i.r)(0 to beat_byte_c - 1)
        /= hashed_pattern(r.stirred(mix_round_count_c - 1))
        or to_resp(config_c, axi_i.r.resp) /= RESP_OKAY then
        rin.error_count <= r.error_count + 1;
        if r.had_error = '0' then
          rin.had_error <= '1';
          rin.first_error <= beat_address(index(r.data), r.beat);
        end if;
      end if;
    end if;

    if advance then
      for g in 0 to group_count_c - 1
      loop
        rin.stirred(0)(g) <= mix_round(group_value(seed_c_u,
                                                   beat_address(r.hash_index,
                                                                r.hash_beat),
                                                   g),
                                       0);
        for i in 1 to mix_round_count_c - 1
        loop
          rin.stirred(i)(g) <= mix_round(r.stirred(i - 1)(g), i);
        end loop;
      end loop;

      -- Past the last beat of the region, the pipe goes on hashing
      -- beats that are never put on the bus.
      if r.hash_beat = burst_length_c - 1 then
        rin.hash_beat <= 0;
        rin.hash_index <= r.hash_index + 1;
      else
        rin.hash_beat <= r.hash_beat + 1;
      end if;

      if r.filling /= pipe_depth_c then
        rin.filling <= r.filling + 1;
      end if;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if start_i = '1' then
          rin.state <= ST_WRITE;
          rin.issue_credit <= outstanding_c;
          rin.data_credit <= outstanding_c;
        end if;

      -- Every write data credit back, with every beat sent, is every
      -- write response received.
      when ST_WRITE =>
        if is_over(r.data) and r.data_credit = outstanding_c then
          rin.state <= ST_READ;
          rin.issue <= (others => '0');
          rin.data <= (others => '0');
          rin.beat <= 0;
          rin.issue_credit <= outstanding_c;
          rin.hash_index <= (others => '0');
          rin.hash_beat <= 0;
          rin.filling <= 0;
        end if;

      when ST_READ =>
        if is_over(r.data) then
          rin.state <= ST_DONE;
        end if;

      when ST_DONE =>
        null;
    end case;
  end process;

  moore: process(r) is
  begin
    axi_o <= master_t'(aw => address_defaults(config_c),
                       w => write_data_defaults(config_c),
                       b => accept(config_c, false),
                       ar => address_defaults(config_c),
                       r => accept(config_c, false));

    busy_o <= '0';
    writing_o <= '0';
    done_o <= '0';
    error_count_o <= r.error_count;
    first_error_address_o <= r.first_error;

    case r.state is
      when ST_RESET | ST_IDLE =>
        null;

      when ST_DONE =>
        done_o <= '1';

      when ST_WRITE =>
        busy_o <= '1';
        writing_o <= '1';

        if r.issue_credit /= 0 and not is_over(r.issue) then
          axi_o.aw <= transaction_command(index(r.issue));
        end if;

        if r.data_credit /= 0 and not is_over(r.data)
          and r.filling = pipe_depth_c then
          axi_o.w <= write_data(config_c,
                                bytes => hashed_pattern(r.stirred(mix_round_count_c - 1)),
                                strb => (0 to beat_byte_c - 1 => '1'),
                                last => r.beat = burst_length_c - 1,
                                valid => true);
        end if;

        axi_o.b <= accept(config_c, r.issue_credit /= outstanding_c
                                    and r.data_credit /= outstanding_c);

      when ST_READ =>
        busy_o <= '1';

        if r.issue_credit /= 0 and not is_over(r.issue) then
          axi_o.ar <= transaction_command(index(r.issue));
        end if;

        axi_o.r <= accept(config_c, r.filling = pipe_depth_c
                                    and r.issue_credit /= outstanding_c);
    end case;
  end process;

end architecture;
