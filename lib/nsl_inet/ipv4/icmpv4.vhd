library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_inet, nsl_data, nsl_math;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.ipv4.all;

entity icmpv4 is
  generic(
    header_length_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- To IPv4
    to_l3_o : out committed_req;
    to_l3_i : in committed_ack;
    from_l3_i : in committed_req;
    from_l3_o : out committed_ack
    );
end entity;

architecture beh of icmpv4 is

  constant icmp_type_dest_unreach_c      : integer := 3;
  constant icmp_type_time_exceeded_c     : integer := 11;
  constant icmp_type_param_problem_c     : integer := 12;
  constant icmp_type_source_quench_c     : integer := 4;
  constant icmp_type_redirect_c          : integer := 5;
  constant icmp_type_echo_request_c      : integer := 8;
  constant icmp_type_echo_reply_c        : integer := 0;
  constant icmp_type_timestamp_request_c : integer := 13;
  constant icmp_type_timestamp_reply_c   : integer := 14;
  constant icmp_type_info_request_c      : integer := 15;
  constant icmp_type_info_reply_c        : integer := 16;

  -- Codes for icmp_type_dest_unreach_c
  constant icmp_code_du_net_c      : integer := 0;
  constant icmp_code_du_host_c     : integer := 1;
  constant icmp_code_du_protocol_c : integer := 2;
  constant icmp_code_du_port_c     : integer := 3;
  constant icmp_code_du_frag_c     : integer := 4;
  constant icmp_code_du_route_c    : integer := 5;

  -- Codes for icmp_type_time_exceeded_c
  constant icmp_code_te_transit_c : integer := 0;
  constant icmp_code_te_defrag_c  : integer := 1;

  -- Codes for icmp_type_redirect_c
  constant icmp_code_redir_network_c     : integer := 0;
  constant icmp_code_redir_host_c        : integer := 1;
  constant icmp_code_redir_tos_network_c : integer := 2;
  constant icmp_code_redir_tos_host_c    : integer := 3;

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_TYPE,
    IN_CODE,
    IN_CHK,
    IN_DATA,
    IN_DROP,
    IN_CHK_ASSESS,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_HEADER,
    OUT_TYPE,
    OUT_CODE,
    OUT_CHK,
    OUT_DATA,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;
  constant max_step_c : integer := nsl_math.arith.max(header_length_c, 2);

  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to max_step_c-1;

    header: byte_string(0 to header_length_c-1);
    in_checksum : checksum_t;
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_checksum : checksum_t;
    out_state : out_state_t;
    out_left : integer range 0 to max_step_c-1;
  end record;

  signal r, rin: regs_t;

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

  transition: process(r, to_l3_i, from_l3_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_checksum <= (others => '0');
        if header_length_c /= 0 then
          rin.in_state <= IN_HEADER;
          rin.in_left <= header_length_c - 1;
        else
          rin.in_state <= IN_CODE;
        end if;

      when IN_HEADER =>
        if from_l3_i.valid = '1' then
          rin.header <= shift_left(r.header, from_l3_i.data);

          if from_l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_left /= 0 then
            rin.in_left <= r.in_left - 1;
          else
            rin.in_state <= IN_TYPE;
          end if;
        end if;

      when IN_TYPE =>
        if from_l3_i.valid = '1' then
          rin.in_checksum <= checksum_update(r.in_checksum, from_l3_i.data);
          if from_l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif from_l3_i.data /= to_byte(icmp_type_echo_request_c) then
            rin.in_state <= IN_DROP;
          else
            rin.in_state <= IN_CODE;
          end if;
        end if;

      when IN_CODE =>
        if from_l3_i.valid = '1' then
          rin.in_checksum <= checksum_update(r.in_checksum, from_l3_i.data);
          if from_l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif from_l3_i.data /= x"00" then
            rin.in_state <= IN_DROP;
          else
            rin.in_state <= IN_CHK;
            rin.in_left <= 1;
          end if;
        end if;

      when IN_CHK =>
        if from_l3_i.valid = '1' then
          rin.in_checksum <= checksum_update(r.in_checksum, from_l3_i.data);
          rin.out_checksum <= checksum_update(r.in_checksum, from_l3_i.data);
          if from_l3_i.last = '1' then
            rin.in_state <= IN_RESET;
          elsif r.in_left /= 0 then
            rin.in_left <= r.in_left - 1;
          else
            rin.in_state <= IN_DATA;
          end if;
        end if;

      when IN_DATA =>
        if from_l3_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          if from_l3_i.last = '1' then
            rin.in_state <= IN_CHK_ASSESS;
          else
            fifo_push := true;
            rin.in_checksum <= checksum_update(r.in_checksum, from_l3_i.data);
          end if;
        end if;

      when IN_CHK_ASSESS =>
        if r.in_checksum = "01111111111111111" or r.in_checksum = "11111111111111110" then
          rin.in_state <= IN_COMMIT;
        else
          rin.in_state <= IN_CANCEL;
        end if;
          
      when IN_DROP =>
        if from_l3_i.valid = '1' and from_l3_i.last = '1' then
          rin.in_state <= IN_RESET;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL then
          rin.in_state <= IN_RESET;
        end if;
    end case;
    
    case r.out_state is
      when OUT_RESET =>
        if r.in_state = IN_DATA then
          if header_length_c /= 0 then
            rin.out_state <= OUT_HEADER;
            rin.out_left <= header_length_c - 1;
          else
            rin.out_state <= OUT_TYPE;
          end if;
        end if;

      when OUT_HEADER =>
        if to_l3_i.ready = '1' then
          rin.header <= shift_left(r.header);
          if r.out_left = 0 then
            rin.out_state <= OUT_TYPE;
          else
            rin.out_left <= r.out_left - 1;
          end if;
        end if;

      when OUT_TYPE =>
        if to_l3_i.ready = '1' then
          rin.out_state <= OUT_CODE;
          rin.out_checksum <= checksum_update(r.out_checksum, x"00");
        end if;

      when OUT_CODE =>
        if to_l3_i.ready = '1' then
          rin.out_state <= OUT_CHK;
          rin.out_left <= 1;
          rin.out_checksum <= checksum_update(r.out_checksum, x"00");
        end if;

      when OUT_CHK =>
        if to_l3_i.ready = '1' then
          rin.out_checksum <= "-" & r.out_checksum(7 downto 0) & "--------";
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_DATA;
          end if;
        end if;

      when OUT_DATA =>
        if to_l3_i.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
          or (to_l3_i.ready = '1' and r.fifo_fillness = 1) then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          elsif r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if to_l3_i.ready = '1' then
          rin.out_state <= OUT_RESET;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= from_l3_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= from_l3_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  mealy: process(r) is
  begin
    case r.in_state is
      when IN_RESET | IN_CHK_ASSESS | IN_COMMIT | IN_CANCEL =>
        from_l3_o <= committed_accept(false);

      when IN_HEADER | IN_TYPE | IN_CODE | IN_CHK | IN_DROP =>
        from_l3_o <= committed_accept(true);

      when IN_DATA =>
        from_l3_o <= committed_accept(r.fifo_fillness < fifo_depth_c);
    end case;

    case r.out_state is
      when OUT_RESET =>
        to_l3_o <= committed_req_idle_c;

      when OUT_HEADER =>
        to_l3_o <= committed_flit(r.header(0));

      when OUT_TYPE | OUT_CODE =>
        to_l3_o <= committed_flit(x"00");

      when OUT_CHK =>
        to_l3_o <= committed_flit(std_ulogic_vector(r.out_checksum(15 downto 8)));

      when OUT_DATA =>
        to_l3_o <= committed_flit(r.fifo(0), valid => r.fifo_fillness /= 0);

      when OUT_COMMIT =>
        to_l3_o <= committed_commit(true);

      when OUT_CANCEL =>
        to_l3_o <= committed_commit(false);
    end case;
  end process;

end architecture;
