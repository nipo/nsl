library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_line_coding, nsl_logic;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;

entity hdlc_framer is
  generic(
    stuff_c : boolean := false
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    frame_i : in nsl_bnoc.committed.committed_req;
    frame_o : out nsl_bnoc.committed.committed_ack;

    hdlc_o : out nsl_bnoc.pipe.pipe_req_t;
    hdlc_i : in nsl_bnoc.pipe.pipe_ack_t
    );
end entity;

architecture beh of hdlc_framer is

  type in_state_t is (
    IN_RESET,
    IN_DATA,
    IN_COMMIT,
    IN_CANCEL
    );

  type out_state_t is (
    OUT_RESET,
    OUT_FLAG_STUFF,
    OUT_FLAG_START,
    OUT_DATA,
    OUT_DATA_ESCAPED,
    OUT_BREAK_FCS,
    OUT_FLAG_END
    );

  signal fcsed_i : nsl_bnoc.committed.committed_req;
  signal fcsed_o : nsl_bnoc.committed.committed_ack;

  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    in_state : in_state_t;
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
    out_stuffed: boolean;
    out_state : out_state_t;
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

  transition: process(r, fcsed_i, hdlc_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.fifo_fillness <= 0;
        rin.in_state <= IN_DATA;

      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and fcsed_i.valid = '1' then
          if fcsed_i.last = '1' then
            if fcsed_i.data(0) = '1' then
              rin.in_state <= IN_COMMIT;
            else
              rin.in_state <= IN_CANCEL;
            end if;
          else
            fifo_push := true;
          end if;
        end if;

      when IN_COMMIT | IN_CANCEL =>
        if r.out_state = OUT_FLAG_END and hdlc_i.ready = '1' then
          rin.in_state <= IN_RESET;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_FLAG_STUFF;
        rin.out_stuffed <= false;

      when OUT_FLAG_STUFF =>
        if r.fifo_fillness > 0 then
          if r.out_stuffed then
            rin.out_state <= OUT_FLAG_START;
          else
            rin.out_state <= OUT_DATA;
          end if;
        end if;

        if hdlc_i.ready = '1' then
          rin.out_stuffed <= true;
        end if;
        
      when OUT_FLAG_START =>
        if hdlc_i.ready = '1' then
          rin.out_state <= OUT_DATA;
        end if;
        
      when OUT_DATA =>
        if r.fifo_fillness > 0 and hdlc_i.ready = '1' then
          if nsl_line_coding.hdlc.is_escaped(r.fifo(0)) then
            rin.out_state <= OUT_DATA_ESCAPED;
          else
            fifo_pop := true;
          end if;
        end if;

        if (r.in_state = IN_COMMIT or r.in_state = IN_CANCEL)
          and (r.fifo_fillness = 0
               or (r.fifo_fillness = 1 and fifo_pop)) then
          if r.in_state = IN_COMMIT then
            rin.out_state <= OUT_FLAG_END;
          else
            rin.out_state <= OUT_BREAK_FCS;
          end if;
        end if;

      when OUT_DATA_ESCAPED =>
        if hdlc_i.ready = '1' then
          fifo_pop := true;
          rin.out_state <= OUT_DATA;
        end if;

      when OUT_BREAK_FCS =>
        if hdlc_i.ready = '1' then
          rin.out_state <= OUT_FLAG_END;
        end if;

      when OUT_FLAG_END =>
        if hdlc_i.ready = '1' then
          rin.out_state <= OUT_FLAG_STUFF;
          rin.out_stuffed <= false;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & "--------";
      rin.fifo(r.fifo_fillness-1) <= fcsed_i.data;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= fcsed_i.data;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & "--------";
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    hdlc_o.data <= "--------";
    hdlc_o.valid <= '0';

    case r.out_state is
      when OUT_RESET =>
        null;

      when OUT_FLAG_END | OUT_FLAG_START =>
        hdlc_o.valid <= '1';
        hdlc_o.data <= nsl_line_coding.hdlc.flag_c;

      when OUT_FLAG_STUFF =>
        if stuff_c then
          hdlc_o.valid <= '1';
          hdlc_o.data <= nsl_line_coding.hdlc.flag_c;
        end if;

      when OUT_DATA_ESCAPED =>
        hdlc_o.valid <= '1';
        hdlc_o.data <= nsl_line_coding.hdlc.escape(r.fifo(0));
        
      when OUT_DATA =>
        hdlc_o.valid <= to_logic(r.fifo_fillness /= 0);
        if nsl_line_coding.hdlc.is_escaped(r.fifo(0)) then
          hdlc_o.data <= nsl_line_coding.hdlc.escape_byte_c;
        else
          hdlc_o.data <= r.fifo(0);
        end if;
        
      when OUT_BREAK_FCS =>
        hdlc_o.valid <= '1';
        hdlc_o.data <= x"55";
    end case;

    case r.in_state is
      when IN_RESET =>
        fcsed_o.ready <= '0';

      when IN_DATA =>
        fcsed_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);

      when IN_COMMIT | IN_CANCEL =>
        fcsed_o.ready <= '0';
    end case;
  end process;

  fcs: nsl_bnoc.crc.crc_committed_adder
    generic map(
      header_length_c => 0,
      params_c => nsl_line_coding.hdlc.fcs_params_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i => frame_i,
      in_o => frame_o,

      out_i => fcsed_o,
      out_o => fcsed_i
      );

end architecture;
