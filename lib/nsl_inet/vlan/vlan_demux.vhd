library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_math, nsl_logic, work;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use work.mac.all;
use work.vlan.all;

entity vlan_demux is
  generic(
    header_length_c : integer := 0;
    vlan_id_c : vlan_id_vector;
    native_vlan_id_c : vlan_id_t := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    in_i : in nsl_bnoc.committed.committed_req;
    in_o : out nsl_bnoc.committed.committed_ack;

    vlan_o : out nsl_bnoc.committed.committed_req_array(0 to vlan_id_c'length-1);
    vlan_i : in nsl_bnoc.committed.committed_ack_array(0 to vlan_id_c'length-1)
    );
end entity;

architecture beh of vlan_demux is

  alias vlan_id_l_c : vlan_id_vector(0 to vlan_id_c'length-1) is vlan_id_c;

  constant destination_count_c : integer := vlan_id_c'length;

  function vlan_index(v: vlan_id_vector; vid: vlan_id_t) return integer
  is
  begin
    for i in v'range
    loop
      if v(i) = vid then
        return i;
      end if;
    end loop;
    return -1;
  end function;

  -- Destination of untagged frames, -1 if they are to be dropped
  constant native_index_c : integer := vlan_index(vlan_id_l_c, native_vlan_id_c);

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_ADDR,
    IN_TYPE,
    IN_DECIDE,
    IN_TCI,
    IN_VID_DECIDE,
    IN_DATA,
    IN_DROP,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_IDLE,
    OUT_HEADER,
    OUT_ADDR,
    OUT_TYPE,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;
  constant left_max: integer := nsl_math.arith.max(12, header_length_c)-1;

  type regs_t is
  record
    in_state : in_state_t;
    in_ctr : integer range 0 to left_max;

    header : byte_string(0 to nsl_math.arith.max(header_length_c-1, 1));
    addr : byte_string(0 to 11);
    type_buf, tci : byte_string(0 to 1);
    destination : integer range 0 to destination_count_c - 1;
    emit_type : boolean;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_ctr : integer range 0 to left_max;
    out_state : out_state_t;
  end record;

  signal r, rin: regs_t;

  signal parsed_s : nsl_bnoc.committed.committed_bus;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.in_state <= IN_RESET;
      r.out_state <= OUT_RESET;
    end if;
  end process;

  transition: process(r, in_i, parsed_s.ack) is
    variable fifo_pop, fifo_push: boolean;
    variable vid : vlan_id_t;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;
    vid := to_integer(from_be(r.tci) and to_unsigned(16#0fff#, 16));

    case r.in_state is
      when IN_RESET =>
        if header_length_c /= 0 then
          rin.in_state <= IN_HEADER;
          rin.in_ctr <= header_length_c-1;
        else
          rin.in_state <= IN_ADDR;
          rin.in_ctr <= 11;
        end if;

      when IN_HEADER =>
        if in_i.valid = '1' then
          rin.header <= shift_left(r.header, in_i.data);
          if in_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr = 0 then
            rin.in_state <= IN_ADDR;
            rin.in_ctr <= 11;
          else
            rin.in_ctr <= r.in_ctr - 1;
          end if;
        end if;

      when IN_ADDR =>
        if in_i.valid = '1' then
          rin.addr <= shift_left(r.addr, in_i.data);
          if in_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr = 0 then
            rin.in_state <= IN_TYPE;
            rin.in_ctr <= 1;
          else
            rin.in_ctr <= r.in_ctr - 1;
          end if;
        end if;

      when IN_TYPE =>
        if in_i.valid = '1' then
          rin.type_buf <= shift_left(r.type_buf, in_i.data);
          if in_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr /= 0 then
            rin.in_ctr <= r.in_ctr - 1;
          else
            rin.in_state <= IN_DECIDE;
          end if;
        end if;

      when IN_DECIDE =>
        if to_unsigned(ethertype_vlan, 16) = from_be(r.type_buf) then
          rin.in_state <= IN_TCI;
          rin.in_ctr <= 1;
        elsif native_index_c >= 0 then
          rin.in_state <= IN_DATA;
        else
          rin.in_state <= IN_DROP;
        end if;

      when IN_TCI =>
        if in_i.valid = '1' then
          rin.tci <= shift_left(r.tci, in_i.data);
          if in_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr /= 0 then
            rin.in_ctr <= r.in_ctr - 1;
          else
            rin.in_state <= IN_VID_DECIDE;
          end if;
        end if;

      when IN_VID_DECIDE =>
        -- Default
        rin.in_state <= IN_DROP;

        for i in vlan_id_l_c'range
        loop
          if vlan_id_l_c(i) = vid then
            rin.in_state <= IN_DATA;
          end if;
        end loop;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and in_i.valid = '1' then
          if in_i.last = '0' then
            fifo_push := true;
          elsif in_i.data(0) = '1' then
            rin.in_state <= IN_COMMIT;
          else
            rin.in_state <= IN_CANCEL;
          end if;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if r.out_state = OUT_IDLE then
          rin.in_state <= IN_RESET;
        end if;

      when IN_DROP =>
        if in_i.valid = '1' and in_i.last = '1' then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_IDLE;

      when OUT_IDLE =>
        if r.in_state = IN_DECIDE
          and to_unsigned(ethertype_vlan, 16) /= from_be(r.type_buf)
          and native_index_c >= 0 then
          rin.destination <= native_index_c;
          rin.emit_type <= true;
          if header_length_c /= 0 then
            rin.out_state <= OUT_HEADER;
            rin.out_ctr <= header_length_c - 1;
          else
            rin.out_state <= OUT_ADDR;
            rin.out_ctr <= 11;
          end if;
        end if;

        if r.in_state = IN_VID_DECIDE then
          for i in vlan_id_l_c'range
          loop
            if vlan_id_l_c(i) = vid then
              rin.destination <= i;
              rin.emit_type <= false;
              if header_length_c /= 0 then
                rin.out_state <= OUT_HEADER;
                rin.out_ctr <= header_length_c - 1;
              else
                rin.out_state <= OUT_ADDR;
                rin.out_ctr <= 11;
              end if;
            end if;
          end loop;
        end if;

      when OUT_HEADER =>
        if parsed_s.ack.ready = '1' then
          if r.out_ctr = 0 then
            rin.out_ctr <= 11;
            rin.out_state <= OUT_ADDR;
          else
            rin.out_ctr <= r.out_ctr - 1;
            rin.header <= shift_left(r.header);
          end if;
        end if;

      when OUT_ADDR =>
        if parsed_s.ack.ready = '1' then
          if r.out_ctr = 0 then
            if r.emit_type then
              rin.out_state <= OUT_TYPE;
              rin.out_ctr <= 1;
            else
              rin.out_state <= OUT_DATA;
            end if;
          else
            rin.out_ctr <= r.out_ctr - 1;
            rin.addr <= shift_left(r.addr);
          end if;
        end if;

      when OUT_TYPE =>
        if parsed_s.ack.ready = '1' then
          if r.out_ctr = 0 then
            rin.out_state <= OUT_DATA;
          else
            rin.out_ctr <= r.out_ctr - 1;
            rin.type_buf <= shift_left(r.type_buf);
          end if;
        end if;

      when OUT_DATA =>
        if parsed_s.ack.ready = '1' and r.fifo_fillness > 0 then
          fifo_pop := true;
        end if;

        if (r.fifo_fillness = 1 and parsed_s.ack.ready = '1')
          or r.fifo_fillness = 0 then
          if r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          elsif r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if parsed_s.ack.ready = '1' then
          rin.out_state <= OUT_IDLE;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= in_i.data;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= in_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    end if;
  end process;

  moore: process(r) is
  begin
    case r.in_state is
      when IN_RESET | IN_DECIDE | IN_VID_DECIDE | IN_COMMIT | IN_CANCEL =>
        in_o.ready <= '0';

      when IN_HEADER | IN_ADDR | IN_TYPE | IN_TCI | IN_DROP =>
        in_o.ready <= '1';

      when IN_DATA =>
        in_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;

    case r.out_state is
      when OUT_RESET | OUT_IDLE =>
        parsed_s.req.valid <= '0';
        parsed_s.req.last <= '-';
        parsed_s.req.data <= (others => '-');

      when OUT_HEADER =>
        parsed_s.req.valid <= '1';
        parsed_s.req.last <= '0';
        parsed_s.req.data <= r.header(0);

      when OUT_ADDR =>
        parsed_s.req.valid <= '1';
        parsed_s.req.last <= '0';
        parsed_s.req.data <= r.addr(0);

      when OUT_TYPE =>
        parsed_s.req.valid <= '1';
        parsed_s.req.last <= '0';
        parsed_s.req.data <= r.type_buf(0);

      when OUT_DATA =>
        parsed_s.req.valid <= to_logic(r.fifo_fillness > 0);
        parsed_s.req.last <= '0';
        parsed_s.req.data <= r.fifo(0);

      when OUT_COMMIT =>
        parsed_s.req.valid <= '1';
        parsed_s.req.last <= '1';
        parsed_s.req.data <= x"01";

      when OUT_CANCEL =>
        parsed_s.req.valid <= '1';
        parsed_s.req.last <= '1';
        parsed_s.req.data <= x"00";
    end case;
  end process;

  dispatch: nsl_bnoc.committed.committed_dispatch
    generic map(
      destination_count_c => destination_count_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      destination_i => r.destination,

      in_i => parsed_s.req,
      in_o => parsed_s.ack,

      out_o => vlan_o,
      out_i => vlan_i
      );

end architecture;
