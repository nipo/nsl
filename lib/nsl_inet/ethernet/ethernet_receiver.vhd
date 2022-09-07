library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_math, nsl_logic;
use nsl_logic.bool.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ethernet.all;

entity ethernet_receiver is
  generic(
    ethertype_c : ethertype_vector;
    l1_header_length_c : integer := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    local_address_i : in mac48_t;

    l1_i : in nsl_bnoc.committed.committed_req;
    l1_o : out nsl_bnoc.committed.committed_ack;

    -- Valid at least on first word of frame on l3_o.
    l3_type_index_o : out integer range 0 to ethertype_c'length - 1;
    l3_o : out nsl_bnoc.committed.committed_req;
    l3_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of ethernet_receiver is
  
  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_DADDR,
    IN_SADDR,
    IN_TYPE,
    IN_DECIDE,
    IN_DATA,
    IN_DROP,
    IN_COMMIT,
    IN_CANCEL
    );
  
  type out_state_t is (
    OUT_RESET,
    OUT_IDLE,
    OUT_HEADER,
    OUT_SADDR,
    OUT_CONTEXT,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;
  constant left_max: integer := nsl_math.arith.max(6, l1_header_length_c)-1;
  
  type regs_t is
  record
    in_state : in_state_t;
    in_ctr : integer range 0 to left_max;
    local_addr, saddr : mac48_t;

    type_len : byte_string(0 to 1);
    header : byte_string(0 to nsl_math.arith.max(l1_header_length_c-1, 1));
    addr_context : byte;
    l3_type_index : integer range 0 to ethertype_c'length - 1;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_ctr : integer range 0 to left_max;
    out_state : out_state_t;
  end record;

  signal r, rin: regs_t;

  signal crced_i : nsl_bnoc.committed.committed_req;
  signal crced_o : nsl_bnoc.committed.committed_ack;
  
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

  transition: process(r, crced_i, l3_i, local_address_i) is
    variable fifo_pop, fifo_push: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;
    rin.local_addr <= local_address_i;

    case r.in_state is
      when IN_RESET =>
        if l1_header_length_c /= 0 then
          rin.in_state <= IN_HEADER;
          rin.in_ctr <= l1_header_length_c-1;
        else
          rin.in_state <= IN_DADDR;
          rin.in_ctr <= 5;
        end if;

      when IN_HEADER =>
        if crced_i.valid = '1' then
          rin.header <= shift_left(r.header, crced_i.data);
          if crced_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr = 0 then
            rin.in_state <= IN_DADDR;
            rin.in_ctr <= 5;
          else
            rin.in_ctr <= r.in_ctr - 1;
          end if;
        end if;
        
      when IN_DADDR =>
        if crced_i.valid = '1' then
          rin.saddr <= shift_left(r.saddr, crced_i.data);
          if crced_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr /= 0 then
            rin.in_ctr <= r.in_ctr - 1;
          else
            rin.in_ctr <= 5;
            rin.in_state <= IN_SADDR;
          end if;
        end if;
        
      when IN_SADDR =>
        if crced_i.valid = '1' then
          if r.in_ctr = 5 then
            -- First cycle of SADDR, r.saddr contains full DADDR
            if r.saddr = ethernet_broadcast_addr_c then
              rin.addr_context <= x"01";
            elsif r.saddr = r.local_addr then
              rin.addr_context <= x"00";
            else
              rin.in_state <= IN_DROP;
            end if;
          end if;

          rin.saddr <= shift_left(r.saddr, crced_i.data);
          if crced_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr /= 0 then
            rin.in_ctr <= r.in_ctr - 1;
          else
            rin.in_ctr <= 1;
            rin.in_state <= IN_TYPE;
          end if;
        end if;

      when IN_TYPE =>
        if crced_i.valid = '1' then
          rin.type_len <= shift_left(r.type_len, crced_i.data);
          if crced_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_ctr /= 0 then
            rin.in_ctr <= r.in_ctr - 1;
          else
            rin.in_state <= IN_DECIDE;
          end if;
        end if;

      when IN_DECIDE =>
        -- Default
        rin.in_state <= IN_DROP;

        for i in ethertype_c'range
        loop
          if to_unsigned(ethertype_c(i), 16) = from_be(r.type_len) then
            rin.in_state <= IN_DATA;
          end if;
        end loop;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and crced_i.valid = '1' then
          if crced_i.last = '0' then
            fifo_push := true;
          elsif crced_i.data(0) = '1' then
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
        if crced_i.valid = '1' and crced_i.last = '1' then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_IDLE;

      when OUT_IDLE =>
        if r.in_state = IN_DECIDE then
          for i in ethertype_c'range
          loop
            if to_unsigned(ethertype_c(i), 16) = from_be(r.type_len) then
              rin.l3_type_index <= i;
              if l1_header_length_c /= 0 then
                rin.out_state <= OUT_HEADER;
                rin.out_ctr <= l1_header_length_c - 1;
              else
                rin.out_state <= OUT_SADDR;
                rin.out_ctr <= 5;
              end if;
            end if;
          end loop;
        end if;

      when OUT_HEADER =>
        if l3_i.ready = '1' then
          if r.out_ctr = 0 then
            rin.out_ctr <= 5;
            rin.out_state <= OUT_SADDR;
          else
            rin.out_ctr <= r.out_ctr - 1;
            rin.header <= shift_left(r.header);
          end if;
        end if;

      when OUT_SADDR =>
        if l3_i.ready = '1' then
          if r.out_ctr = 0 then
            rin.out_state <= OUT_CONTEXT;
          else
            rin.out_ctr <= r.out_ctr - 1;
            rin.saddr <= shift_left(r.saddr);
          end if;
        end if;
        
      when OUT_CONTEXT =>
        if l3_i.ready = '1' then
          rin.out_state <= OUT_DATA;
        end if;
        
      when OUT_DATA =>
        if l3_i.ready = '1' and r.fifo_fillness > 0 then
          fifo_pop := true;
        end if;

        if (r.fifo_fillness = 1 and l3_i.ready = '1')
          or r.fifo_fillness = 0 then
          if r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          elsif r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if l3_i.ready = '1' then
          rin.out_state <= OUT_IDLE;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= crced_i.data;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= crced_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    end if;
  end process;

  moore: process(r) is
  begin
    l3_type_index_o <= r.l3_type_index;

    case r.in_state is
      when IN_RESET | IN_DECIDE | IN_COMMIT | IN_CANCEL =>
        crced_o.ready <= '0';

      when IN_HEADER | IN_DADDR | IN_SADDR | IN_TYPE | IN_DROP =>
        crced_o.ready <= '1';

      when IN_DATA =>
        crced_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);
    end case;

    case r.out_state is
      when OUT_RESET | OUT_IDLE =>
        l3_o.valid <= '0';
        l3_o.last <= '-';
        l3_o.data <= (others => '-');
        
      when OUT_HEADER =>
        l3_o.valid <= '1';
        l3_o.last <= '0';
        l3_o.data <= r.header(0);

      when OUT_SADDR =>
        l3_o.valid <= '1';
        l3_o.last <= '0';
        l3_o.data <= r.saddr(0);

      when OUT_CONTEXT =>
        l3_o.valid <= '1';
        l3_o.last <= '0';
        l3_o.data <= r.addr_context;

      when OUT_DATA =>
        l3_o.valid <= to_logic(r.fifo_fillness > 0);
        l3_o.last <= '0';
        l3_o.data <= r.fifo(0);

      when OUT_COMMIT =>
        l3_o.valid <= '1';
        l3_o.last <= '1';
        l3_o.data <= x"01";

      when OUT_CANCEL =>
        l3_o.valid <= '1';
        l3_o.last <= '1';
        l3_o.data <= x"00";
    end case;
  end process;

  crc: nsl_bnoc.crc.crc_committed_checker
    generic map(
      header_length_c => l1_header_length_c,
      params_c => work.ethernet.fcs_params_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_i => l1_i,
      in_o => l1_o,
      out_o => crced_i,
      out_i => crced_o
      );
  
end architecture;
