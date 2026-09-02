library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

-- Multi-input, multi-output packet router with header rewrite.
--
-- Every input port peels a fixed-length header off each incoming
-- packet and queues a routing request for the external routing logic
-- while the packet payload keeps streaming into an internal fifo:
-- the input port never stalls while a routing decision is pending,
-- as long as the fifo (sized by fifo_depth_c) does not overflow.  A
-- packet is captured, and its routing decision taken, while the
-- previous packet from the same input port is still being delivered.
--
-- The routing request presents the extracted header and source port;
-- the response selects a destination port and the header to emit in
-- front of the payload, or asks for the packet to be dropped.  All
-- response signals are sampled on the cycle route_ready_i is
-- asserted.
--
-- Payload beats reach the destination port through a per-input-port
-- staging register, so that no port computes its fifo enables from
-- another input port's state.  It sustains one beat per cycle and
-- costs one cycle of delivery latency.
--
-- Packets shorter than the input header are silently dropped.
-- Packets consisting of the header alone are routed with an empty
-- payload.  Headers are expected to be a whole number of beats; when
-- the header length is not a multiple of the data width, the bytes
-- sharing a beat with the end of the header are lost.
entity axi4_stream_router is
  generic(
    config_c : config_t;
    in_count_c : positive;
    out_count_c : positive;
    in_header_length_c : natural := 0;
    out_header_length_c : natural := 0;
    -- Per-input-port payload fifo depth, in beats.  This is the
    -- elasticity available to absorb the routing decision latency and
    -- the output header emission without stalling the input.  For an
    -- input port that must never stall, size it to at least the
    -- output header length in beats, plus the routing decision
    -- latency and half a dozen beats of arbitration overhead.  The
    -- per-port staging register downstream of the fifo adds a beat of
    -- elasticity of its own and starts draining the fifo as soon as
    -- the packet is routed, before the destination port is granted,
    -- so it does not add to this budget.
    fifo_depth_c : positive := 4
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

  -- The buffer configurations are only used when the matching header
  -- length is non-zero, but they elaborate unconditionally and
  -- buffer_config() does not accept a zero size.
  constant in_header_config_c : buffer_config_t
    := buffer_config(config_c, if_else(in_header_length_c = 0, 1, in_header_length_c));
  constant out_header_config_c : buffer_config_t
    := buffer_config(config_c, if_else(out_header_length_c = 0, 1, out_header_length_c));
  constant out_fifo_depth_c : natural := 2;
  constant in_header_storage_c : natural := if_else(in_header_length_c > 0, in_header_length_c, 1);
  constant out_header_storage_c : natural := if_else(out_header_length_c > 0, out_header_length_c, 1);

  -- Packet lifecycle, tracked per input port in a two-entry queue so
  -- that a packet gets captured and routed while the previous one
  -- drains.
  type slot_state_t is (
    SLOT_IDLE,
    -- Header captured, waiting for the routing decision
    SLOT_PENDING,
    -- Decision taken, payload to forward to out_index
    SLOT_ROUTED,
    -- Decision taken, payload to discard
    SLOT_DROPPED
    );

  type slot_t is
  record
    state: slot_state_t;
    header: byte_string(0 to in_header_storage_c-1);
    -- Packet has no beat beyond its header.  The user bits of its
    -- last beat are only meaningful then: with no payload beat to
    -- carry them through, they ride the response header instead.
    empty: boolean;
    last_user: user_t;
    out_index: natural range 0 to out_count_c-1;
  end record;

  type slot_vector is array(0 to 1) of slot_t;

  type capture_state_t is (
    CS_RESET,
    CS_HEADER,
    CS_BODY
    );

  type input_port_regs_t is
  record
    state : capture_state_t;
    header : buffer_t;
    slots : slot_vector;
    -- Index of the oldest busy slot
    slot_head : natural range 0 to 1;
    in_packet : boolean;
    fifo : master_vector(0 to fifo_depth_c-1);
    fifo_fillness : natural range 0 to fifo_depth_c;
    -- Beat staged for the output port, popped off the fifo front by
    -- the input port itself as soon as the head slot is routed.  It
    -- decouples the two sides: the fifo clock enables are computed
    -- from this port's own state and from the state of the one output
    -- port xfer_out_index designates, never from another input port.
    -- xfer outlives the slot it came from, hence the registered
    -- destination: the head slot retires as soon as its last beat is
    -- staged.
    xfer : master_t;
    xfer_valid : boolean;
    xfer_out_index : natural range 0 to out_count_c-1;
  end record;

  -- Output port production state.  It only tracks what gets pushed
  -- into the output fifo; emission is driven by the fifo alone, so a
  -- port goes back to OS_IDLE, and may take a new grant, while the
  -- tail of the previous packet is still draining.  Packet ordering
  -- on the output is guaranteed by the fifo itself.
  type output_port_state_t is (
    -- No packet in production
    OS_IDLE,
    -- Pushing the response header beats
    OS_HEADER,
    -- Pushing payload beats staged by the source input port
    OS_DATA
    );

  type output_port_regs_t is
  record
    state : output_port_state_t;
    header : buffer_t;
    in_index : natural range 0 to in_count_c-1;
    empty : boolean;
    empty_user : user_t;
    fifo : master_vector(0 to out_fifo_depth_c-1);
    fifo_fillness : natural range 0 to out_fifo_depth_c;
  end record;

  type input_port_regs_vector is array (natural range <>) of input_port_regs_t;
  type output_port_regs_vector is array (natural range <>) of output_port_regs_t;

  type arbiter_state_t is (
    ST_RESET,
    ST_IN_SELECT,
    ST_ROUTE_REQ,
    ST_OUT_SELECT,
    ST_OUT_GRANT
    );

  type regs_t is
  record
    ip : input_port_regs_vector(0 to in_count_c-1);
    op : output_port_regs_vector(0 to out_count_c-1);
    state: arbiter_state_t;
    in_index: natural range 0 to in_count_c-1;
    route_slot: natural range 0 to 1;
    route_header : byte_string(0 to in_header_storage_c-1);
    out_index: natural range 0 to out_count_c-1;
    granted_header : byte_string(0 to out_header_storage_c-1);
    granted_empty : boolean;
    granted_user : user_t;
  end record;

  signal r, rin: regs_t;

  -- Slot the next packet should be allocated to, in queue order, -1
  -- when both slots are busy.
  function slot_alloc_index(p: input_port_regs_t) return integer
  is
  begin
    if p.slots(p.slot_head).state = SLOT_IDLE then
      return p.slot_head;
    elsif p.slots(1 - p.slot_head).state = SLOT_IDLE then
      return 1 - p.slot_head;
    else
      return -1;
    end if;
  end function;

  function fifo_shift_data(fifo: master_vector;
                           fillness: natural;
                           push: boolean;
                           push_data: master_t;
                           pop: boolean) return master_vector
  is
    variable ret: master_vector(0 to fifo'length-1) := fifo;
    variable can_push, can_pop: boolean;
  begin
    can_push := push and fillness < ret'length;
    can_pop := pop and fillness > 0;

    if can_pop then
      for i in 0 to ret'length-2
      loop
        ret(i) := ret(i+1);
      end loop;
      ret(ret'length-1) := transfer_defaults(config_c);
    end if;

    if can_push then
      if can_pop then
        ret(fillness-1) := push_data;
      else
        ret(fillness) := push_data;
      end if;
    end if;

    return ret;
  end function;

  function fifo_shift_fillness(fillness: natural;
                               depth: natural;
                               push: boolean;
                               pop: boolean) return natural
  is
    variable can_push, can_pop: boolean;
  begin
    can_push := push and fillness < depth;
    can_pop := pop and fillness > 0;

    if can_push and not can_pop then
      return fillness + 1;
    elsif can_pop and not can_push then
      return fillness - 1;
    else
      return fillness;
    end if;
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
        r.ip(i).state <= CS_RESET;
      end loop;

      for i in r.op'range
      loop
        r.op(i).state <= OS_IDLE;
        -- Output validity is a function of the fifo fillness alone,
        -- reset has to clear it here.
        r.op(i).fifo_fillness <= 0;
      end loop;

      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, in_i, out_i,
                      route_ready_i, route_header_i,
                      route_destination_i, route_drop_i) is
    variable push_v, pop_v, drop_pop_v : boolean;
    variable load_v, taken_v, take_v : boolean;
    variable header_push_v : boolean;
    variable push_data_v : master_t;
    variable complete_v, last_v : boolean;
    variable src_v : natural range 0 to in_count_c-1;
    variable dst_v : natural range 0 to out_count_c-1;
    variable head_v : natural range 0 to 1;
    variable alloc_v : integer range -1 to 1;
    variable shifted_v : buffer_t;
  begin
    rin <= r;

    -- Central routing arbiter
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IN_SELECT;
        rin.in_index <= 0;

      when ST_IN_SELECT =>
        head_v := r.ip(r.in_index).slot_head;
        if r.ip(r.in_index).slots(head_v).state = SLOT_PENDING then
          rin.route_slot <= head_v;
          rin.route_header <= r.ip(r.in_index).slots(head_v).header;
          rin.state <= ST_ROUTE_REQ;
        elsif r.ip(r.in_index).slots(head_v).state /= SLOT_IDLE
          and r.ip(r.in_index).slots(1 - head_v).state = SLOT_PENDING then
          rin.route_slot <= 1 - head_v;
          rin.route_header <= r.ip(r.in_index).slots(1 - head_v).header;
          rin.state <= ST_ROUTE_REQ;
        elsif r.in_index = in_count_c-1 then
          rin.in_index <= 0;
        else
          rin.in_index <= r.in_index + 1;
        end if;

      when ST_ROUTE_REQ =>
        if route_ready_i = '1' then
          if route_drop_i = '1' then
            rin.ip(r.in_index).slots(r.route_slot).state <= SLOT_DROPPED;
            rin.state <= ST_IN_SELECT;
            if r.in_index = in_count_c-1 then
              rin.in_index <= 0;
            else
              rin.in_index <= r.in_index + 1;
            end if;
          else
            rin.ip(r.in_index).slots(r.route_slot).state <= SLOT_ROUTED;
            rin.ip(r.in_index).slots(r.route_slot).out_index <= route_destination_i;
            rin.out_index <= route_destination_i;
            if out_header_length_c /= 0 then
              rin.granted_header(0 to out_header_length_c-1) <= route_header_i;
            end if;
            rin.granted_empty <= r.ip(r.in_index).slots(r.route_slot).empty;
            rin.granted_user <= r.ip(r.in_index).slots(r.route_slot).last_user;
            rin.state <= ST_OUT_SELECT;
          end if;
        end if;

      when ST_OUT_SELECT =>
        if r.op(r.out_index).state = OS_IDLE then
          rin.state <= ST_OUT_GRANT;
        end if;

      when ST_OUT_GRANT =>
        -- Header-only packets have no beat to drain, retire the slot
        -- at grant time.
        if r.granted_empty then
          rin.ip(r.in_index).slots(r.route_slot).state <= SLOT_IDLE;
          if r.route_slot = r.ip(r.in_index).slot_head then
            rin.ip(r.in_index).slot_head <= 1 - r.route_slot;
          end if;
        end if;
        rin.state <= ST_IN_SELECT;
        if r.in_index = in_count_c-1 then
          rin.in_index <= 0;
        else
          rin.in_index <= r.in_index + 1;
        end if;
    end case;

    -- Input ports
    for i in 0 to in_count_c-1
    loop
      head_v := r.ip(i).slot_head;
      dst_v := r.ip(i).xfer_out_index;

      -- The staged beat is consumed when the output port it is routed
      -- to is producing data for this input port and has room.  Only
      -- that one output port is looked at, through a mux this input
      -- port drives itself.
      taken_v := r.ip(i).xfer_valid
        and r.op(dst_v).state = OS_DATA
        and r.op(dst_v).in_index = i
        and r.op(dst_v).fifo_fillness < out_fifo_depth_c;

      -- Staging of a routed packet, one beat per cycle off the fifo
      -- front, as soon as the decision is taken and independently of
      -- the destination being granted yet.  Header-only packets have
      -- no beat of their own at the fifo front, they must not stage
      -- anything.  Loading while the staged beat is taken sustains one
      -- beat per cycle.
      load_v := r.ip(i).slots(head_v).state = SLOT_ROUTED
        and not r.ip(i).slots(head_v).empty
        and r.ip(i).fifo_fillness > 0
        and (not r.ip(i).xfer_valid or taken_v);

      -- Discarding of a dropped packet, one beat per cycle off the
      -- fifo front.  Beats of the packet may still be arriving.
      drop_pop_v := r.ip(i).slots(head_v).state = SLOT_DROPPED
        and not r.ip(i).slots(head_v).empty
        and r.ip(i).fifo_fillness > 0;

      if load_v then
        rin.ip(i).xfer <= r.ip(i).fifo(0);
        rin.ip(i).xfer_valid <= true;
        rin.ip(i).xfer_out_index <= r.ip(i).slots(head_v).out_index;
      elsif taken_v then
        rin.ip(i).xfer_valid <= false;
      end if;

      -- Retire the head slot when its last beat is staged, or when the
      -- last beat of a dropped packet is discarded.  A dropped
      -- header-only packet has no beat at all.
      if (load_v or drop_pop_v) and is_last(config_c, r.ip(i).fifo(0)) then
        rin.ip(i).slots(head_v).state <= SLOT_IDLE;
        rin.ip(i).slot_head <= 1 - head_v;
      elsif r.ip(i).slots(head_v).state = SLOT_DROPPED
        and r.ip(i).slots(head_v).empty then
        rin.ip(i).slots(head_v).state <= SLOT_IDLE;
        rin.ip(i).slot_head <= 1 - head_v;
      end if;

      pop_v := drop_pop_v or load_v;

      push_v := r.ip(i).state = CS_BODY
        and is_valid(config_c, in_i(i))
        and r.ip(i).fifo_fillness < fifo_depth_c
        and (in_header_length_c /= 0
             or r.ip(i).in_packet
             or slot_alloc_index(r.ip(i)) >= 0);

      rin.ip(i).fifo <= fifo_shift_data(r.ip(i).fifo, r.ip(i).fifo_fillness,
                                        push_v, in_i(i), pop_v);
      rin.ip(i).fifo_fillness <= fifo_shift_fillness(r.ip(i).fifo_fillness, fifo_depth_c,
                                                     push_v, pop_v);

      -- Capture
      case r.ip(i).state is
        when CS_RESET =>
          rin.ip(i).header <= reset(in_header_config_c);
          for s in 0 to 1
          loop
            rin.ip(i).slots(s).state <= SLOT_IDLE;
          end loop;
          rin.ip(i).slot_head <= 0;
          rin.ip(i).in_packet <= false;
          rin.ip(i).fifo_fillness <= 0;
          rin.ip(i).xfer_valid <= false;
          if in_header_length_c /= 0 then
            rin.ip(i).state <= CS_HEADER;
          else
            rin.ip(i).state <= CS_BODY;
          end if;

        when CS_HEADER =>
          alloc_v := slot_alloc_index(r.ip(i));
          if is_valid(config_c, in_i(i)) and alloc_v >= 0 then
            last_v := is_last(config_c, in_i(i));
            complete_v := is_last(in_header_config_c, r.ip(i).header)
              and byte_count(config_c, in_i(i)) = config_c.data_width;
            shifted_v := shift(in_header_config_c, r.ip(i).header, in_i(i));

            if complete_v then
              rin.ip(i).slots(alloc_v).state <= SLOT_PENDING;
              rin.ip(i).slots(alloc_v).header <= bytes(in_header_config_c, shifted_v);
              rin.ip(i).slots(alloc_v).empty <= last_v;
              rin.ip(i).slots(alloc_v).last_user <= in_i(i).user;
              rin.ip(i).header <= reset(in_header_config_c);
              if not last_v then
                rin.ip(i).state <= CS_BODY;
                rin.ip(i).in_packet <= true;
              end if;
            elsif last_v then
              -- Packet shorter than the header, discard
              rin.ip(i).header <= reset(in_header_config_c);
            else
              rin.ip(i).header <= shifted_v;
            end if;
          end if;

        when CS_BODY =>
          if push_v then
            if in_header_length_c = 0 and not r.ip(i).in_packet then
              alloc_v := slot_alloc_index(r.ip(i));
              rin.ip(i).slots(alloc_v).state <= SLOT_PENDING;
              rin.ip(i).slots(alloc_v).empty <= false;
            end if;

            if is_last(config_c, in_i(i)) then
              rin.ip(i).in_packet <= false;
              if in_header_length_c /= 0 then
                rin.ip(i).state <= CS_HEADER;
              end if;
            else
              rin.ip(i).in_packet <= true;
            end if;
          end if;
      end case;
    end loop;

    -- Output ports
    for i in 0 to out_count_c-1
    loop
      src_v := r.op(i).in_index;

      -- Taking of the beat staged by the source input port.  The
      -- staged destination tells whether the beat belongs to the
      -- packet this port was granted: an input port may have a packet
      -- for another output port ahead of the one this port waits for.
      -- Only the staged bits of the input ports take part here, no
      -- fifo state of theirs.
      take_v := r.op(i).state = OS_DATA
        and r.op(i).fifo_fillness < out_fifo_depth_c
        and r.ip(src_v).xfer_valid
        and r.ip(src_v).xfer_out_index = i;

      -- Response header beats and payload beats are produced by
      -- mutually exclusive states, one push port is enough.
      header_push_v := r.op(i).state = OS_HEADER
        and r.op(i).fifo_fillness < out_fifo_depth_c;

      if header_push_v then
        push_data_v := next_beat(out_header_config_c, r.op(i).header,
                                 user => r.op(i).empty_user(config_c.user_width-1 downto 0),
                                 last => r.op(i).empty);
      else
        push_data_v := r.ip(src_v).xfer;
      end if;

      -- Emission is unconditional: whatever sits at the fifo front is
      -- valid on the output, no state takes part in the decision.
      pop_v := r.op(i).fifo_fillness > 0
        and is_ready(config_c, out_i(i));

      rin.op(i).fifo <= fifo_shift_data(r.op(i).fifo, r.op(i).fifo_fillness,
                                        header_push_v or take_v, push_data_v, pop_v);
      rin.op(i).fifo_fillness <= fifo_shift_fillness(r.op(i).fifo_fillness, out_fifo_depth_c,
                                                     header_push_v or take_v, pop_v);

      case r.op(i).state is
        when OS_IDLE =>
          if r.state = ST_OUT_GRANT and r.out_index = i then
            rin.op(i).in_index <= r.in_index;
            rin.op(i).empty <= r.granted_empty;
            rin.op(i).empty_user <= r.granted_user;
            if out_header_length_c /= 0 then
              rin.op(i).header <= reset(out_header_config_c,
                                        r.granted_header(0 to out_header_length_c-1));
              rin.op(i).state <= OS_HEADER;
            elsif not r.granted_empty then
              rin.op(i).state <= OS_DATA;
            end if;
          end if;

        when OS_HEADER =>
          if header_push_v then
            rin.op(i).header <= shift(out_header_config_c, r.op(i).header);
            if is_last(out_header_config_c, r.op(i).header) then
              if r.op(i).empty then
                rin.op(i).state <= OS_IDLE;
              else
                rin.op(i).state <= OS_DATA;
              end if;
            end if;
          end if;

        when OS_DATA =>
          -- Production ends on the push of the last beat, the fifo
          -- carries the packet boundary from there on.
          if take_v and is_last(config_c, r.ip(src_v).xfer) then
            rin.op(i).state <= OS_IDLE;
          end if;
      end case;
    end loop;
  end process;

  moore: process(r) is
  begin
    route_valid_o <= to_logic(r.state = ST_ROUTE_REQ);
    route_header_o <= r.route_header(0 to in_header_length_c-1);
    route_source_o <= r.in_index;

    for i in r.ip'range
    loop
      case r.ip(i).state is
        when CS_RESET =>
          in_o(i) <= accept(config_c, false);

        when CS_HEADER =>
          in_o(i) <= accept(config_c, slot_alloc_index(r.ip(i)) >= 0);

        when CS_BODY =>
          if in_header_length_c = 0 and not r.ip(i).in_packet then
            in_o(i) <= accept(config_c,
                              slot_alloc_index(r.ip(i)) >= 0
                              and r.ip(i).fifo_fillness < fifo_depth_c);
          else
            in_o(i) <= accept(config_c, r.ip(i).fifo_fillness < fifo_depth_c);
          end if;
      end case;
    end loop;

    for i in r.op'range
    loop
      if r.op(i).fifo_fillness /= 0 then
        out_o(i) <= r.op(i).fifo(0);
      else
        out_o(i) <= transfer_defaults(config_c);
      end if;
    end loop;
  end process;

end architecture;
