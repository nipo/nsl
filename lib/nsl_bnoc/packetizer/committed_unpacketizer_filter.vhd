library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_logic, nsl_memory;
use nsl_logic.bool.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;

entity committed_unpacketizer_filter is
  generic(
    header_length_c : natural := 0;
    max_length_l2_c : natural := 12;
    max_packet_count_l2_c : natural := 4;
    clock_count_c : integer range 1 to 2 := 1;
    handle_overflow_c : boolean := false
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic_vector(0 to clock_count_c-1);

    packet_i  : in  committed_req;
    packet_o  : out committed_ack;

    frame_o   : out framed_req;
    frame_i   : in framed_ack
    );
end entity;

architecture beh of committed_unpacketizer_filter is

  signal fifo_in_s, fifo_out_s: framed_bus_t;
  
  type commit_fifo_t is
  record
    valid, ready: std_ulogic;
    ok: std_ulogic;
  end record;

  signal commit_out_s, commit_in_s: commit_fifo_t;

begin

  input_side: block is
    
    type in_state_t is (
      IN_RESET,
      IN_HEADER,
      IN_DATA,
      IN_COMMIT,
      IN_CANCEL,
      IN_WAIT,
      IN_OVERFLOW_CANCEL,
      IN_OVERFLOW_FLUSH
      );

    type out_state_t is (
      OUT_RESET,
      OUT_DATA,
      OUT_LAST
      );

    constant fifo_depth_c : integer := 3;

    type regs_t is
    record
      in_state : in_state_t;
      in_header_left : integer range 0 to header_length_c-1;
      in_size : integer range 0 to 2**max_length_l2_c-1;

      fifo: byte_string(0 to fifo_depth_c-1);
      fifo_fillness: integer range 0 to fifo_depth_c;

      out_state : out_state_t;
    end record;

    signal r, rin: regs_t;
    
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

    transition: process(r, packet_i, fifo_in_s.ack, commit_in_s.ready) is
      variable fifo_push, fifo_pop: boolean;
    begin
      rin <= r;

      fifo_pop := false;
      fifo_push := false;

      case r.in_state is
        when IN_RESET =>
          rin.fifo_fillness <= 0;
          rin.in_size <= 0;
          if header_length_c /= 0 then
            rin.in_state <= IN_HEADER;
            rin.in_header_left <= header_length_c - 1;
          else
            rin.in_state <= IN_DATA;
          end if;

        when IN_HEADER =>
          rin.in_size <= 0;
          if packet_i.valid = '1' then
            if r.in_header_left /= 0 then
              rin.in_header_left <= r.in_header_left - 1;
            else
              rin.in_state <= IN_DATA;
            end if;

            if packet_i.last = '1' then
              rin.in_header_left <= header_length_c - 1;
            end if;
          end if;

        when IN_DATA =>
          if r.fifo_fillness < fifo_depth_c and packet_i.valid = '1' then
            if packet_i.last = '0' then
              if handle_overflow_c then
                if r.in_size = 2**max_length_l2_c-1 then
                  rin.in_state <= IN_OVERFLOW_CANCEL;
                else
                  rin.in_size <= r.in_size + 1;
                end if;
              end if;
              fifo_push := true;
            elsif packet_i.data = x"00" then
              rin.in_state <= IN_CANCEL;
            else
              rin.in_state <= IN_COMMIT;
            end if;
          end if;

        when IN_OVERFLOW_CANCEL =>
          if commit_in_s.ready = '1' then
            rin.in_state <= IN_OVERFLOW_FLUSH;
          end if;

        when IN_OVERFLOW_FLUSH =>
          if packet_i.valid = '1' and packet_i.last = '1' then
            rin.in_state <= IN_WAIT;
          end if;

        when IN_COMMIT | IN_CANCEL =>
          if commit_in_s.ready = '1' then
            rin.in_state <= IN_WAIT;
          end if;

        when IN_WAIT =>
          if (r.fifo_fillness = 1 and fifo_in_s.ack.ready = '1')
            or r.fifo_fillness = 0 then
            rin.in_size <= 0;
            if header_length_c /= 0 then
              rin.in_state <= IN_HEADER;
              rin.in_header_left <= header_length_c - 1;
            else
              rin.in_state <= IN_DATA;
            end if;
          end if;
      end case;

      case r.out_state is
        when OUT_RESET =>
          rin.out_state <= OUT_DATA;

        when OUT_DATA =>
          if r.fifo_fillness > 1 and fifo_in_s.ack.ready = '1' then
            fifo_pop := true;
          end if;

          if r.in_state = IN_COMMIT
            or r.in_state = IN_CANCEL
            or r.in_state = IN_OVERFLOW_CANCEL then
            rin.out_state <= OUT_LAST;
          end if;

        when OUT_LAST =>
          if r.fifo_fillness > 0 and fifo_in_s.ack.ready = '1' then
            fifo_pop := true;
          end if;

          if ((r.fifo_fillness = 1 and fifo_in_s.ack.ready = '1')
            or r.fifo_fillness = 0)
            and r.in_state = IN_WAIT then
            rin.out_state <= OUT_DATA;
          end if;
      end case;

      if fifo_push and fifo_pop then
        rin.fifo <= shift_left(r.fifo);
        rin.fifo(r.fifo_fillness-1) <= packet_i.data;
      elsif fifo_push then
        rin.fifo(r.fifo_fillness) <= packet_i.data;
        rin.fifo_fillness <= r.fifo_fillness + 1;
      elsif fifo_pop then
        rin.fifo <= shift_left(r.fifo);
        rin.fifo_fillness <= r.fifo_fillness - 1;
      end if;
    end process;

    moore: process(r) is
    begin
      fifo_in_s.req <= framed_req_idle_c;
      packet_o <= framed_ack_idle_c;
      commit_in_s.valid <= '0';
      commit_in_s.ok <= '-';

      case r.out_state is
        when OUT_DATA =>
          fifo_in_s.req.data <= r.fifo(0);
          fifo_in_s.req.valid <= to_logic(r.fifo_fillness > 1);
          fifo_in_s.req.last <= '0';

        when OUT_LAST =>
          fifo_in_s.req.data <= r.fifo(0);
          fifo_in_s.req.valid <= to_logic(r.fifo_fillness > 0);
          fifo_in_s.req.last <= to_logic(r.fifo_fillness = 1);

        when others =>
          null;
      end case;

      case r.in_state is
        when IN_HEADER | IN_OVERFLOW_FLUSH =>
          packet_o.ready <= '1';

        when IN_DATA =>
          packet_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);

        when IN_COMMIT =>
          commit_in_s.valid <= '1';
          commit_in_s.ok <= '1';

        when IN_CANCEL | IN_OVERFLOW_CANCEL =>
          commit_in_s.valid <= '1';
          commit_in_s.ok <= '0';

        when others =>
          null;
      end case;
    end process;
  end block;

  data_fifo: nsl_bnoc.framed.framed_fifo
    generic map(
      depth => 2**max_length_l2_c,
      clk_count => clock_count_c
      )
    port map(
      p_resetn => reset_n_i,
      p_clk => clock_i,

      p_in_val => fifo_in_s.req,
      p_in_ack => fifo_in_s.ack,

      p_out_val => fifo_out_s.req,
      p_out_ack => fifo_out_s.ack
      );

  commit_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => 1,
      word_count_c => 2**max_packet_count_l2_c,
      clock_count_c => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      out_data_o(0) => commit_out_s.ok,
      out_valid_o => commit_out_s.valid,
      out_ready_i => commit_out_s.ready,

      in_data_i(0) => commit_in_s.ok,
      in_valid_i => commit_in_s.valid,
      in_ready_o => commit_in_s.ready
      );
  
  out_side: block is
    
    type state_t is (
      ST_RESET,
      ST_COMMIT_GET,
      ST_DATA,
      ST_DROP
      );

    type regs_t is
    record
      state : state_t;
    end record;

    signal r, rin: regs_t;
    
  begin

    regs: process(clock_i(clock_count_c-1), reset_n_i) is
    begin
      if rising_edge(clock_i(clock_count_c-1)) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    transition: process(r, commit_out_s.valid, commit_out_s.ok, fifo_out_s.req, frame_i) is
    begin
      rin <= r;

      case r.state is
        when ST_RESET =>
          rin.state <= ST_COMMIT_GET;

        when ST_COMMIT_GET =>
          if commit_out_s.valid = '1' then
            if commit_out_s.ok = '1' then
              rin.state <= ST_DATA;
            else
              rin.state <= ST_DROP;
            end if;
          end if;

        when ST_DATA =>
          if fifo_out_s.req.valid = '1' and frame_i.ready = '1' and fifo_out_s.req.last = '1' then
            rin.state <= ST_COMMIT_GET;
          end if;

        when ST_DROP =>
          if fifo_out_s.req.valid = '1' and fifo_out_s.req.last = '1' then
            rin.state <= ST_COMMIT_GET;
          end if;
      end case;
    end process;

    frame_o.data <= fifo_out_s.req.data when r.state = ST_DATA else "--------";
    frame_o.valid <= fifo_out_s.req.valid when r.state = ST_DATA else '0';
    frame_o.last <= fifo_out_s.req.last when r.state = ST_DATA else '-';
    fifo_out_s.ack.ready <= '1' when r.state = ST_DROP
                            else frame_i.ready when r.state = ST_DATA
                            else '0';
    commit_out_s.ready <= '1' when r.state = ST_COMMIT_GET else '0';
    
  end block;
  
end architecture;
