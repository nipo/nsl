library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_inet, nsl_math, nsl_logic;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_inet.udp.all;
use nsl_logic.bool.all;

entity udp_transmitter is
  generic(
    mtu_c : integer := 1500;
    header_length_c : integer
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    l5_i : in committed_req;
    l5_o : out committed_ack;

    l3_o : out committed_req;
    l3_i : in committed_ack
    );
end entity;

architecture beh of udp_transmitter is

  type in_state_t is (
    IN_RESET,
    IN_HEADER,
    IN_REMOTE_PORT,
    IN_LOCAL_PORT,
    IN_SIZE,
    IN_DATA,
    IN_DONE
    );

  type out_state_t is (
    OUT_RESET,
    OUT_HEADER,
    OUT_LOCAL_PORT,
    OUT_REMOTE_PORT,
    OUT_TOTAL_LEN,
    OUT_CHK,
    OUT_DATA,
    OUT_FLUSH
    );

  constant fifo_depth_c : integer := 3;
  constant max_step_c : integer := nsl_math.arith.max(header_length_c, 2);

  signal l5_s: committed_bus;
  signal total_size_s: unsigned(nsl_math.arith.log2(mtu_c)-1 downto 0);
  signal total_size_ready_s, total_size_valid_s: std_ulogic;

  type regs_t is
  record
    in_state : in_state_t;
    in_left : integer range 0 to max_step_c-1;

    header : byte_string(0 to header_length_c-1);
    local_port, remote_port, total_len : unsigned(15 downto 0);
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

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

  transition: process(r, l3_i, l5_s.req,
                      total_size_valid_s, total_size_s) is
    variable fifo_push, fifo_pop: boolean;
    variable fifo_data : byte;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        if header_length_c /= 0 then
          rin.in_state <= IN_HEADER;
          rin.in_left <= header_length_c - 1;
        else
          rin.in_state <= IN_REMOTE_PORT;
          rin.in_left <= 1;
        end if;

      when IN_HEADER =>
        if l5_s.req.valid = '1' then
          rin.header <= shift_left(r.header, l5_s.req.data);
          if l5_s.req.last = '1' then
            rin.in_state <= IN_RESET;
          else
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_left <= 1;
              rin.in_state <= IN_REMOTE_PORT;
            end if;
          end if;
        end if;

      when IN_REMOTE_PORT =>
        if l5_s.req.valid = '1' then
          if l5_s.req.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.remote_port <= r.remote_port(7 downto 0) & unsigned(l5_s.req.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_left <= 1;
              rin.in_state <= IN_LOCAL_PORT;
            end if;
          end if;
        end if;

      when IN_LOCAL_PORT =>
        if l5_s.req.valid = '1' then
          if l5_s.req.last = '1' then
            rin.in_state <= IN_RESET;
          else
            rin.local_port <= r.local_port(7 downto 0) & unsigned(l5_s.req.data);
            if r.in_left /= 0 then
              rin.in_left <= r.in_left - 1;
            else
              rin.in_left <= 1;
              rin.in_state <= IN_SIZE;
            end if;
          end if;
        end if;

      when IN_SIZE =>
        if total_size_valid_s = '1' then
          rin.total_len <= resize(total_size_s, rin.total_len'length);
          rin.in_state <= IN_DATA;
        end if;

      when IN_DATA =>
        if l5_s.req.valid = '1' and r.fifo_fillness < fifo_depth_c then
          fifo_push := true;
          if l5_s.req.last = '0' then
            fifo_data := l5_s.req.data;
          else
            rin.in_state <= IN_DONE;
          end if;
        end if;

      when IN_DONE =>
        if r.out_state = OUT_FLUSH then
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
            rin.out_state <= OUT_REMOTE_PORT;
            rin.out_left <= 1;
          end if;
        end if;

      when OUT_HEADER =>
        if l3_i.ready = '1' then
          rin.header <= shift_left(r.header);
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_LOCAL_PORT;
            rin.out_left <= 1;
          end if;
        end if;

      when OUT_LOCAL_PORT =>
        if l3_i.ready = '1' then
          rin.local_port <= r.local_port(7 downto 0) & "--------";
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_REMOTE_PORT;
            rin.out_left <= 1;
          end if;
        end if;

      when OUT_REMOTE_PORT =>
        if l3_i.ready = '1' then
          rin.remote_port <= r.remote_port(7 downto 0) & "--------";
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_TOTAL_LEN;
            rin.out_left <= 1;
          end if;
        end if;

      when OUT_TOTAL_LEN =>
        if l3_i.ready = '1' then
          rin.total_len <= r.total_len(7 downto 0) & "--------";
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_CHK;
            rin.out_left <= 1;
          end if;
        end if;

      when OUT_CHK =>
        if l3_i.ready = '1' then
          if r.out_left /= 0 then
            rin.out_left <= r.out_left - 1;
          else
            rin.out_state <= OUT_DATA;
          end if;
        end if;

      when OUT_DATA =>
        if l3_i.ready = '1' and r.fifo_fillness > 1 then
          fifo_pop := true;
        end if;

        if r.in_state = IN_DONE then
          rin.out_state <= OUT_FLUSH;
        end if;

      when OUT_FLUSH =>
        if l3_i.ready = '1' and r.fifo_fillness /= 0 then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
          or (l3_i.ready = '1' and r.fifo_fillness = 1) then
          rin.out_state <= OUT_RESET;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= fifo_data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= fifo_data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    l3_o <= committed_req_idle_c;
    l5_s.ack <= committed_ack_idle_c;
    total_size_ready_s <= '0';

    case r.in_state is
      when IN_RESET | IN_DONE =>
        null;

      when IN_HEADER | IN_REMOTE_PORT | IN_LOCAL_PORT =>
        l5_s.ack <= committed_accept(true);
        
      when IN_DATA =>
        l5_s.ack <= committed_accept(r.fifo_fillness < fifo_depth_c);
        
      when IN_SIZE =>
        total_size_ready_s <= '1';
    end case;

    case r.out_state is
      when OUT_RESET =>
        null;

      when OUT_DATA =>
        l3_o <= committed_flit(r.fifo(0),
                               valid => r.fifo_fillness > 1);

      when OUT_FLUSH =>
        l3_o <= committed_flit(r.fifo(0),
                               valid => r.fifo_fillness /= 0,
                               last => r.fifo_fillness = 1);

      when OUT_HEADER =>
        l3_o <= committed_flit(r.header(0));

      when OUT_CHK =>
        l3_o <= committed_flit(to_byte(0));

      when OUT_LOCAL_PORT =>
        l3_o <= committed_flit(std_ulogic_vector(r.local_port(15 downto 8)));

      when OUT_REMOTE_PORT =>
        l3_o <= committed_flit(std_ulogic_vector(r.remote_port(15 downto 8)));

      when OUT_TOTAL_LEN =>
        l3_o <= committed_flit(std_ulogic_vector(r.total_len(15 downto 8)));
    end case;
  end process;

  sizer: nsl_bnoc.committed.committed_sizer
    generic map(
      clock_count_c => 1,
      -- Size of UDP header minus L12 header minus port
      offset_c => 8-header_length_c-4,
      txn_count_c => 4,
      max_size_l2_c => total_size_s'length
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_i => l5_i,
      in_o => l5_o,

      out_o => l5_s.req,
      out_i => l5_s.ack,

      size_o => total_size_s,
      size_valid_o => total_size_valid_s,
      size_ready_i => total_size_ready_s
      );
  
end architecture;
