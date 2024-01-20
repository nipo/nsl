library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_memory, nsl_data;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;

entity committed_sizer is
  generic(
    clock_count_c : natural range 1 to 2 := 1;
    offset_c : integer := 0;
    txn_count_c : natural;
    max_size_l2_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic_vector(0 to clock_count_c-1);
    
    in_i   : in committed_req;
    in_o   : out committed_ack;

    size_o : out unsigned(max_size_l2_c-1 downto 0);
    good_o : out std_ulogic;
    size_valid_o : out std_ulogic;
    size_ready_i : in std_ulogic;

    out_o   : out committed_req;
    out_i   : in committed_ack
    );
end entity;

architecture beh of committed_sizer is

  constant offset_u_c : unsigned(max_size_l2_c-1 downto 0)
    := to_unsigned(offset_c mod (2**max_size_l2_c), max_size_l2_c);
  
  type in_state_t is (
    IN_RESET,
    IN_FORWARD,
    IN_IGNORE,
    IN_REPORT_GOOD,
    IN_REPORT_BAD,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_FORWARD,
    OUT_COMMIT,
    OUT_CANCEL
    );

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    in_state: in_state_t;
    count: unsigned(max_size_l2_c-1 downto 0);

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    out_state: out_state_t;
  end record;

  signal r, rin: regs_t;

  signal size_valid_s, size_ready_s : std_ulogic;
  signal fifo_in_s : committed_bus_t;
  signal report_i_s: std_ulogic_vector(max_size_l2_c downto 0);
  signal report_o_s: std_ulogic_vector(max_size_l2_c downto 0);

begin

  regs: process(clock_i(0), reset_n_i) is
  begin
    if rising_edge(clock_i(0)) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.in_state <= IN_RESET;
      r.out_state <= OUT_RESET;
    end if;
  end process;

  transition: process(r, in_i, fifo_in_s.ack, size_ready_s) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;
    
    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.in_state <= IN_FORWARD;
        rin.count <= offset_u_c;

      when IN_FORWARD =>
        if in_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
          if in_i.last = '1' then
            if in_i.data(0) = '1' then
              rin.in_state <= IN_REPORT_GOOD;
            else
              rin.in_state <= IN_REPORT_BAD;
            end if;
          elsif r.count = (r.count'range => '1') then
            rin.in_state <= IN_IGNORE;
          else
            fifo_push := true;
            rin.count <= r.count + 1;
          end if;
        end if;

      when IN_IGNORE =>
        if in_i.valid = '1' and in_i.last = '1' then
          rin.in_state <= IN_REPORT_BAD;
        end if;

      when IN_REPORT_BAD =>
        if size_ready_s = '1' then
          rin.in_state <= IN_CANCEL;
        end if;
        
      when IN_REPORT_GOOD =>
        if size_ready_s = '1' then
          rin.in_state <= IN_COMMIT;
        end if;
                
      when IN_COMMIT | IN_CANCEL =>
        if (r.out_state = OUT_CANCEL or r.out_state = OUT_COMMIT)
          and (r.fifo_fillness = 0 or
               (r.fifo_fillness = 1 and fifo_in_s.ack.ready = '1')) then
          rin.in_state <= IN_FORWARD;
          rin.count <= offset_u_c;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_FORWARD;

      when OUT_FORWARD =>
        if r.fifo_fillness > 0 and fifo_in_s.ack.ready = '1' then
          fifo_pop := true;
        end if;

        if (r.fifo_fillness = 1 and fifo_in_s.ack.ready = '1')
          or r.fifo_fillness = 0 then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_COMMIT;
          end if;

          if r.in_state = IN_CANCEL then
            rin.out_state <= OUT_CANCEL;
          end if;
        end if;

      when OUT_COMMIT | OUT_CANCEL =>
        if fifo_in_s.ack.ready = '1' then
          rin.out_state <= OUT_FORWARD;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= in_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= in_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    in_o <= committed_ack_idle_c;
    fifo_in_s.req <= committed_req_idle_c;
    size_valid_s <= '0';

    report_i_s(r.count'length) <= '0';
    report_i_s(r.count'range) <= std_ulogic_vector(r.count);

    case r.in_state is
      when IN_RESET | IN_CANCEL | IN_COMMIT =>
        null;

      when IN_FORWARD =>
        in_o <= committed_accept(r.fifo_fillness < fifo_depth_c);

      when IN_IGNORE =>
        in_o <= committed_accept(true);

      when IN_REPORT_BAD =>
        size_valid_s <= '1';
        report_i_s(r.count'length) <= '0';

      when IN_REPORT_GOOD =>
        size_valid_s <= '1';
        report_i_s(r.count'length) <= '1';
    end case;

    case r.out_state is
      when OUT_RESET =>
        null;

      when OUT_FORWARD =>
        fifo_in_s.req <= committed_flit(first_left(r.fifo), valid => r.fifo_fillness > 0, last => false);

      when OUT_COMMIT =>
        fifo_in_s.req <= committed_commit(true);

      when OUT_CANCEL =>
        fifo_in_s.req <= committed_commit(false);
    end case;
  end process;
  
  data_pipe: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => 2**max_size_l2_c,
      data_width_c => 9,
      clock_count_c => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_data_i(8) => fifo_in_s.req.last,
      in_data_i(7 downto 0) => fifo_in_s.req.data,
      in_valid_i => fifo_in_s.req.valid,
      in_ready_o => fifo_in_s.ack.ready,

      out_data_o(8) => out_o.last,
      out_data_o(7 downto 0) => out_o.data,
      out_ready_i => out_i.ready,
      out_valid_o => out_o.valid
      );

  size_pipe: nsl_memory.fifo.fifo_homogeneous
    generic map(
      word_count_c => txn_count_c,
      data_width_c => max_size_l2_c + 1,
      clock_count_c => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_data_i => report_i_s,
      in_valid_i => size_valid_s,
      in_ready_o => size_ready_s,

      out_data_o => report_o_s,
      out_ready_i => size_ready_i,
      out_valid_o => size_valid_o
      );

  size_o <= unsigned(report_o_s(size_o'range));
  good_o <= report_o_s(report_o_s'left);
  
end architecture;
