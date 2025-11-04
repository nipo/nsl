library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity axi4_stream_router is
  generic(
    config_c : config_t;
    in_count_c : positive;
    out_count_c : positive;
    in_header_length_c : natural := 0;
    out_header_length_c : natural := 0
    );
  port(
    reset_n_i : in  std_ulogic;
    clock_i   : in  std_ulogic;

    in_i      : in master_vector(0 to in_count_c-1);
    in_o      : out slave_vector(0 to in_count_c-1);

    out_o     : out master_vector(0 to out_count_c-1);
    out_i     : in slave_vector(0 to out_count_c-1);

    route_valid_o       : out std_ulogic;
    route_header_o      : out byte_string(0 to in_header_length_c-1);
    route_source_o      : out natural range 0 to in_count_c-1;

    route_ready_i       : in  std_ulogic := '1';
    route_header_i      : in  byte_string(0 to out_header_length_c-1) := (others => x"00");
    route_destination_i : in  natural range 0 to out_count_c-1 := 0;
    route_drop_i        : in std_ulogic := '0'
    );
end entity;

architecture rtl of axi4_stream_router is

  constant in_header_config_c : buffer_config_t := buffer_config(config_c, in_header_length_c);
  constant out_header_config_c : buffer_config_t := buffer_config(config_c, out_header_length_c);
  constant fifo_depth_c : natural := 2;

  type input_port_state_t is (
    IS_RESET,
    IS_HEADER,
    IS_ROUTE_REQ,
    IS_DATA,
    IS_DRAIN_HEADER,  -- Draining previous frame while accepting next frame header
    IS_DROP
    );

  type data_fifo_t is array(0 to fifo_depth_c-1) of master_t;

  type input_port_regs_t is
  record
    state : input_port_state_t;
    header : buffer_t;
    out_index: natural range 0 to out_count_c-1;
    -- FIFO for pipelining
    fifo: data_fifo_t;
    fifo_fillness: natural range 0 to fifo_depth_c;
    last_seen: boolean;  -- Tracks if last beat was pushed
  end record;

  type output_port_state_t is (
    OS_RESET,
    OS_IDLE,
    OS_HEADER,
    OS_DATA
    );

  type output_port_regs_t is
  record
    state : output_port_state_t;
    header : buffer_t;
    in_index: natural range 0 to in_count_c-1;
    -- FIFO for output pipelining
    fifo: data_fifo_t;
    fifo_fillness: natural range 0 to fifo_depth_c;
  end record;

  type input_port_regs_vector is array (natural range <>) of input_port_regs_t;
  type output_port_regs_vector is array (natural range <>) of output_port_regs_t;

  type state_t is (
    ST_RESET,
    ST_IN_SELECT,
    ST_ROUTE_REQ,
    ST_OUT_SELECT,
    ST_OUT_GRANT,
    ST_OUT_DROP
    );

  type regs_t is
  record
    ip : input_port_regs_vector(0 to in_count_c-1);
    op : output_port_regs_vector(0 to out_count_c-1);
    state: state_t;
    in_index: natural range 0 to in_count_c-1;
    out_index: natural range 0 to out_count_c-1;
    route_header : byte_string(0 to in_header_length_c-1);
  end record;

  signal r, rin: regs_t;

  -- FIFO management: handles simultaneous push and pop
  function fifo_shift_data(
    fifo: data_fifo_t;
    fillness: natural;
    push: boolean;
    push_data: master_t;
    pop: boolean
  ) return data_fifo_t is
    variable ret: data_fifo_t;
    variable can_push: boolean;
    variable can_pop: boolean;
  begin
    ret := fifo;
    can_push := push and fillness < fifo_depth_c;
    can_pop := pop and fillness > 0;

    if can_pop and can_push then
      -- Shift and insert simultaneously
      for i in 0 to fifo_depth_c-2 loop
        ret(i) := fifo(i+1);
      end loop;
      ret(fillness-1) := push_data;
    elsif can_pop then
      -- Just shift
      for i in 0 to fifo_depth_c-2 loop
        ret(i) := fifo(i+1);
      end loop;
      ret(fifo_depth_c-1) := transfer_defaults(config_c);
    elsif can_push then
      -- Just insert
      ret(fillness) := push_data;
    end if;

    return ret;
  end function;

  function fifo_shift_fillness(
    fillness: natural;
    push: boolean;
    pop: boolean
  ) return natural is
    variable ret: natural;
    variable can_push: boolean;
    variable can_pop: boolean;
  begin
    ret := fillness;
    can_push := push and fillness < fifo_depth_c;
    can_pop := pop and fillness > 0;

    if can_push and not can_pop then
      ret := fillness + 1;
    elsif can_pop and not can_push then
      ret := fillness - 1;
    end if;

    return ret;
  end function;

begin

  assert config_c.has_last
    report "Configuration must have last signal"
    severity failure;

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      for i in r.ip'range
      loop
        r.ip(i).state <= IS_RESET;
      end loop;

      for i in r.op'range
      loop
        r.op(i).state <= OS_RESET;
      end loop;

      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i,
                      route_ready_i, route_header_i,
                      route_destination_i, route_drop_i) is
    variable push_v : boolean;
    variable pop_v : boolean;
  begin
    rin <= r;

    -- Central arbiter state machine
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IN_SELECT;
        rin.in_index <= 0;

      when ST_IN_SELECT =>
        if r.ip(r.in_index).state = IS_ROUTE_REQ then
          rin.state <= ST_ROUTE_REQ;
          rin.route_header <= bytes(in_header_config_c, r.ip(r.in_index).header);
        elsif r.in_index = in_count_c-1 then
          rin.in_index <= 0;
        else
          rin.in_index <= r.in_index + 1;
        end if;

      when ST_ROUTE_REQ =>
        if route_ready_i = '1' then
          if route_drop_i = '1' then
            rin.state <= ST_OUT_DROP;
          else
            rin.state <= ST_OUT_SELECT;
            rin.out_index <= route_destination_i;
          end if;
        end if;

      when ST_OUT_SELECT =>
        if r.op(r.out_index).state = OS_IDLE then
          rin.state <= ST_OUT_GRANT;
        end if;
        -- Wait in this state until output becomes idle

      when ST_OUT_GRANT | ST_OUT_DROP =>
        rin.state <= ST_IN_SELECT;
    end case;

    -- Input port state machines
    for i in r.ip'range
    loop
      case r.ip(i).state is
        when IS_RESET =>
          rin.ip(i).header <= reset(in_header_config_c);
          rin.ip(i).fifo_fillness <= 0;
          rin.ip(i).last_seen <= false;
          if in_header_length_c /= 0 then
            rin.ip(i).state <= IS_HEADER;
          elsif is_valid(config_c, in_i(i)) then
            rin.ip(i).state <= IS_ROUTE_REQ;
          end if;

        when IS_HEADER =>
          if is_valid(config_c, in_i(i)) then
            rin.ip(i).header <= shift(in_header_config_c, r.ip(i).header, in_i(i));
            if is_last(in_header_config_c, r.ip(i).header) then
              rin.ip(i).state <= IS_ROUTE_REQ;
            end if;

            if is_last(config_c, in_i(i)) then
              rin.ip(i).state <= IS_RESET;
            end if;
          end if;

        when IS_ROUTE_REQ =>
          if r.in_index = i then
            case r.state is
              when ST_OUT_GRANT =>
                rin.ip(i).state <= IS_DATA;
                rin.ip(i).out_index <= r.out_index;

              when ST_OUT_DROP =>
                rin.ip(i).state <= IS_DROP;

              when others =>
                null;
            end case;
          end if;

        when IS_DROP =>
          if is_valid(config_c, in_i(i)) and is_last(config_c, in_i(i)) then
            rin.ip(i).state <= IS_RESET;
          end if;

        when IS_DATA =>
          -- FIFO operations
          push_v := is_valid(config_c, in_i(i)) and r.ip(i).fifo_fillness < fifo_depth_c;
          -- Pop when output port pulls data (not when final output is ready)
          pop_v := r.op(r.ip(i).out_index).state = OS_DATA
                   and r.ip(i).fifo_fillness > 0
                   and r.op(r.ip(i).out_index).fifo_fillness < fifo_depth_c;

          rin.ip(i).fifo <= fifo_shift_data(r.ip(i).fifo, r.ip(i).fifo_fillness,
                                            push_v, in_i(i), pop_v);
          rin.ip(i).fifo_fillness <= fifo_shift_fillness(r.ip(i).fifo_fillness,
                                                         push_v, pop_v);

          -- When last beat is pushed, transition to draining state
          if push_v and is_last(config_c, in_i(i)) then
            if in_header_length_c /= 0 then
              rin.ip(i).state <= IS_DRAIN_HEADER;
              rin.ip(i).header <= reset(in_header_config_c);
            else
              rin.ip(i).last_seen <= true;
            end if;
          end if;

          -- For zero-length headers: transition when FIFO drains
          if r.ip(i).last_seen
            and fifo_shift_fillness(r.ip(i).fifo_fillness, push_v, pop_v) = 0 then
            rin.ip(i).last_seen <= false;
            rin.ip(i).state <= IS_ROUTE_REQ;
          end if;

        when IS_DRAIN_HEADER =>
          -- Continue draining FIFO while accepting next frame's header
          pop_v := r.op(r.ip(i).out_index).state = OS_DATA
                   and r.ip(i).fifo_fillness > 0
                   and r.op(r.ip(i).out_index).fifo_fillness < fifo_depth_c;

          rin.ip(i).fifo <= fifo_shift_data(r.ip(i).fifo, r.ip(i).fifo_fillness,
                                            false, in_i(i), pop_v);
          rin.ip(i).fifo_fillness <= fifo_shift_fillness(r.ip(i).fifo_fillness,
                                                         false, pop_v);

          -- Accept header bytes
          if is_valid(config_c, in_i(i)) then
            rin.ip(i).header <= shift(in_header_config_c, r.ip(i).header, in_i(i));
            if is_last(in_header_config_c, r.ip(i).header) then
              if r.ip(i).fifo_fillness = 0 or (r.ip(i).fifo_fillness = 1 and pop_v) then
                -- FIFO drained, go directly to route request
                rin.ip(i).state <= IS_ROUTE_REQ;
              else
                -- Still draining, but header complete - wait for drain
                rin.ip(i).last_seen <= true;
              end if;
            end if;

            if is_last(config_c, in_i(i)) then
              -- Frame ended prematurely
              rin.ip(i).state <= IS_RESET;
            end if;
          elsif r.ip(i).last_seen
            and (r.ip(i).fifo_fillness = 0 or (r.ip(i).fifo_fillness = 1 and pop_v)) then
            -- Header was complete, FIFO now drained
            rin.ip(i).last_seen <= false;
            rin.ip(i).state <= IS_ROUTE_REQ;
          end if;

      end case;
    end loop;

    -- Output port state machines
    for i in r.op'range
    loop
      case r.op(i).state is
        when OS_RESET =>
          rin.op(i).state <= OS_IDLE;
          rin.op(i).header <= reset(out_header_config_c);
          rin.op(i).fifo_fillness <= 0;

        when OS_IDLE =>
          if r.state = ST_OUT_SELECT and r.out_index = i then
            if out_header_length_c /= 0 then
              rin.op(i).state <= OS_HEADER;
              rin.op(i).header <= reset(out_header_config_c, route_header_i);
            else
              rin.op(i).state <= OS_DATA;
            end if;
            rin.op(i).in_index <= r.in_index;
          end if;

        when OS_HEADER =>
          if is_ready(config_c, out_i(i)) then
            rin.op(i).header <= shift(out_header_config_c, r.op(i).header);
            if is_last(out_header_config_c, r.op(i).header) then
              rin.op(i).state <= OS_DATA;
            end if;
          end if;

        when OS_DATA =>
          -- Transfer data from input FIFO to output FIFO
          push_v := r.ip(r.op(i).in_index).fifo_fillness > 0
                    and r.op(i).fifo_fillness < fifo_depth_c;
          pop_v := r.op(i).fifo_fillness > 0
                   and is_ready(config_c, out_i(i));

          if push_v then
            rin.op(i).fifo <= fifo_shift_data(r.op(i).fifo, r.op(i).fifo_fillness,
                                              push_v, r.ip(r.op(i).in_index).fifo(0), pop_v);
            rin.op(i).fifo_fillness <= fifo_shift_fillness(r.op(i).fifo_fillness,
                                                           push_v, pop_v);
          elsif pop_v then
            rin.op(i).fifo <= fifo_shift_data(r.op(i).fifo, r.op(i).fifo_fillness,
                                              false, transfer_defaults(config_c), pop_v);
            rin.op(i).fifo_fillness <= fifo_shift_fillness(r.op(i).fifo_fillness,
                                                           false, pop_v);
          end if;

          -- Transition to IDLE when last beat is output
          if pop_v and is_last(config_c, r.op(i).fifo(0)) then
            rin.op(i).state <= OS_IDLE;
          end if;

      end case;
    end loop;
  end process;

  moore: process(r, in_i, out_i) is
  begin
    route_valid_o <= to_logic(r.state = ST_ROUTE_REQ);
    route_header_o <= r.route_header;
    route_source_o <= r.in_index;

    for i in r.ip'range
    loop
      case r.ip(i).state is
        when IS_RESET | IS_ROUTE_REQ =>
          in_o(i) <= accept(config_c, false);
        when IS_HEADER | IS_DROP | IS_DRAIN_HEADER =>
          in_o(i) <= accept(config_c, true);
        when IS_DATA =>
          -- Accept when FIFO not full (breaks combinatorial path to output)
          in_o(i) <= accept(config_c, r.ip(i).fifo_fillness < fifo_depth_c);
      end case;
    end loop;

    for i in r.op'range
    loop
      case r.op(i).state is
        when OS_RESET | OS_IDLE =>
          out_o(i) <= transfer_defaults(config_c);

        when OS_HEADER =>
          out_o(i) <= next_beat(out_header_config_c, r.op(i).header, last => false);

        when OS_DATA =>
          -- Output from output FIFO (fully pipelined)
          if r.op(i).fifo_fillness > 0 then
            out_o(i) <= r.op(i).fifo(0);
          else
            out_o(i) <= transfer_defaults(config_c);
          end if;
      end case;
    end loop;
  end process;

end architecture;
