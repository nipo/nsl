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
    scramble_c: boolean := false
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    start_i: in std_ulogic;

    axi_o: out master_t;
    axi_i: in slave_t;

    busy_o: out std_ulogic;
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

  constant group_count_c: natural := group_count(beat_byte_c);

  -- A stage per round of the payload hash.  It costs a burst as many
  -- cycles to fill the pipe and nothing at all per beat: a beat is
  -- hashed while its predecessors are on the bus, so back to back
  -- beats stay back to back, which for a part whose whole argument is
  -- that reads and writes need no turnaround is the point.
  constant pipe_depth_c: natural := mix_round_count_c;

  type stage_vector is array (natural range <>)
    of hash_vector(0 to group_count_c - 1);

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_WRITE_ADDRESS,
    ST_WRITE_PRIME,
    ST_WRITE_DATA,
    ST_WRITE_RESPONSE,
    ST_READ_ADDRESS,
    ST_READ_PRIME,
    ST_READ_DATA,
    ST_DONE
    );

  type regs_t is
  record
    state: state_t;
    index: index_t;
    beat: natural range 0 to 2 ** 8 - 1;
    -- The beat whose hash is entering the pipe, which runs ahead of
    -- the one on the bus by the pipe's depth
    hashing: natural range 0 to 2 ** 8 - 1 + pipe_depth_c;
    filling: natural range 0 to pipe_depth_c;
    stirred: stage_vector(0 to mix_round_count_c - 1);
    reading: std_ulogic;
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

begin

  assert region_byte_l2_c > burst_byte_l2_c
    report "memory_tester: region is not bigger than one transaction"
    severity failure;

  assert burst_length_c >= 1 and burst_length_c <= 256
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
      r.index <= (others => '0');
      r.beat <= 0;
      r.hashing <= 0;
      r.filling <= 0;
      r.stirred <= (others => (others => (others => '0')));
      r.reading <= '0';
      r.error_count <= (others => '0');
      r.first_error <= (others => '0');
      r.had_error <= '0';
    end if;
  end process;

  transition: process(r, start_i, axi_i) is
    variable advance: boolean;
  begin
    rin <= r;
    advance := false;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if start_i = '1' then
          rin.state <= ST_WRITE_ADDRESS;
        end if;

      when ST_WRITE_ADDRESS =>
        if is_ready(config_c, axi_i.aw) then
          rin.hashing <= 0;
          rin.filling <= 0;
          rin.state <= ST_WRITE_PRIME;
        end if;

      when ST_WRITE_PRIME =>
        advance := true;
        if r.filling = pipe_depth_c - 1 then
          rin.beat <= 0;
          rin.state <= ST_WRITE_DATA;
        else
          rin.filling <= r.filling + 1;
        end if;

      when ST_WRITE_DATA =>
        if is_ready(config_c, axi_i.w) then
          advance := true;
          if r.beat = burst_length_c - 1 then
            rin.state <= ST_WRITE_RESPONSE;
          else
            rin.beat <= r.beat + 1;
          end if;
        end if;

      when ST_WRITE_RESPONSE =>
        if is_valid(config_c, axi_i.b) then
          if r.index = (r.index'range => '1') then
            rin.index <= (others => '0');
            rin.reading <= '1';
            rin.state <= ST_READ_ADDRESS;
          else
            rin.index <= r.index + 1;
            rin.state <= ST_WRITE_ADDRESS;
          end if;
        end if;

      when ST_READ_ADDRESS =>
        if is_ready(config_c, axi_i.ar) then
          rin.hashing <= 0;
          rin.filling <= 0;
          rin.state <= ST_READ_PRIME;
        end if;

      when ST_READ_PRIME =>
        advance := true;
        if r.filling = pipe_depth_c - 1 then
          rin.beat <= 0;
          rin.state <= ST_READ_DATA;
        else
          rin.filling <= r.filling + 1;
        end if;

      when ST_READ_DATA =>
        if is_valid(config_c, axi_i.r) then
          advance := true;
          if bytes(config_c, axi_i.r)(0 to beat_byte_c - 1)
            /= hashed_pattern(r.stirred(mix_round_count_c - 1))
            or to_resp(config_c, axi_i.r.resp) /= RESP_OKAY then
            rin.error_count <= r.error_count + 1;
            if r.had_error = '0' then
              rin.had_error <= '1';
              rin.first_error <= beat_address(r.index, r.beat);
            end if;
          end if;

          if r.beat = burst_length_c - 1 then
            if r.index = (r.index'range => '1') then
              rin.state <= ST_DONE;
            else
              rin.index <= r.index + 1;
              rin.state <= ST_READ_ADDRESS;
            end if;
          else
            rin.beat <= r.beat + 1;
          end if;
        end if;

      when ST_DONE =>
        null;
    end case;

    if advance then
      for g in 0 to group_count_c - 1
      loop
        rin.stirred(0)(g) <= mix_round(group_value(seed_c_u,
                                                   beat_address(r.index,
                                                                r.hashing),
                                                   g),
                                       0);
        for i in 1 to mix_round_count_c - 1
        loop
          rin.stirred(i)(g) <= mix_round(r.stirred(i - 1)(g), i);
        end loop;
      end loop;
      rin.hashing <= r.hashing + 1;
    end if;
  end process;

  mealy: process(r, axi_i) is
  begin
    axi_o <= master_t'(aw => address_defaults(config_c),
                       w => write_data_defaults(config_c),
                       b => accept(config_c, false),
                       ar => address_defaults(config_c),
                       r => accept(config_c, false));

    busy_o <= '0';
    done_o <= '0';
    error_count_o <= r.error_count;
    first_error_address_o <= r.first_error;

    case r.state is
      when ST_RESET | ST_IDLE =>
        null;

      when ST_DONE =>
        done_o <= '1';

      when ST_WRITE_ADDRESS =>
        busy_o <= '1';
        axi_o.aw <= address(config_c,
                            addr => transaction_address(r.index),
                            id => (config_c.id_width - 1 downto 0 => '0'),
                            len_m1 => to_unsigned(burst_length_c - 1, 8),
                            size_l2 => to_unsigned(beat_byte_l2_c, 3),
                            burst => BURST_INCR,
                            valid => true);

      when ST_WRITE_PRIME | ST_READ_PRIME =>
        busy_o <= '1';

      when ST_WRITE_DATA =>
        busy_o <= '1';
        axi_o.w <= write_data(config_c,
                              bytes => hashed_pattern(r.stirred(mix_round_count_c - 1)),
                              strb => (0 to beat_byte_c - 1 => '1'),
                              last => r.beat = burst_length_c - 1,
                              valid => true);

      when ST_WRITE_RESPONSE =>
        busy_o <= '1';
        axi_o.b <= accept(config_c, true);

      when ST_READ_ADDRESS =>
        busy_o <= '1';
        axi_o.ar <= address(config_c,
                            addr => transaction_address(r.index),
                            id => (config_c.id_width - 1 downto 0 => '0'),
                            len_m1 => to_unsigned(burst_length_c - 1, 8),
                            size_l2 => to_unsigned(beat_byte_l2_c, 3),
                            burst => BURST_INCR,
                            valid => true);

      when ST_READ_DATA =>
        busy_o <= '1';
        axi_o.r <= accept(config_c, true);
    end case;
  end process;

end architecture;
