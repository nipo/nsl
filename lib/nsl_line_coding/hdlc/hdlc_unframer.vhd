library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc, nsl_data, nsl_line_coding, nsl_logic;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity hdlc_unframer is
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    hdlc_i : in nsl_bnoc.pipe.pipe_req_t;
    hdlc_o : out nsl_bnoc.pipe.pipe_ack_t;

    frame_o : out nsl_bnoc.committed.committed_req;
    frame_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of hdlc_unframer is

  type in_state_t is (
    IN_RESET,
    IN_FLAG_START,
    IN_DATA,
    IN_DATA_ESCAPED,
    IN_COMMIT
    );

  type out_state_t is (
    OUT_RESET,
    OUT_DATA,
    OUT_COMMIT
    );

  signal fcs_o : nsl_bnoc.framed.framed_req;
  signal fcs_i : nsl_bnoc.framed.framed_ack;
  constant fifo_depth_c : integer := 2;

  type regs_t is
  record
    in_state : in_state_t;
    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;
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

  transition: process(r, fcs_i, hdlc_i) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    case r.in_state is
      when IN_RESET =>
        rin.fifo_fillness <= 0;
        rin.in_state <= IN_FLAG_START;

      when IN_FLAG_START =>
        if hdlc_i.valid = '1' then
          if hdlc_i.data = nsl_line_coding.hdlc.flag_c then
            rin.in_state <= IN_FLAG_START;
          elsif hdlc_i.data = nsl_line_coding.hdlc.escape_byte_c then
            rin.in_state <= IN_DATA_ESCAPED;
          else
            rin.in_state <= IN_DATA;
            fifo_push := true;
          end if;
        end if;
        
      when IN_DATA =>
        if r.fifo_fillness < fifo_depth_c and hdlc_i.valid = '1' then
          if hdlc_i.data = nsl_line_coding.hdlc.flag_c then
            rin.in_state <= IN_COMMIT;
          elsif hdlc_i.data = nsl_line_coding.hdlc.escape_byte_c then
            rin.in_state <= IN_DATA_ESCAPED;
          else
            fifo_push := true;
          end if;
        end if;

      when IN_DATA_ESCAPED =>
        if r.fifo_fillness < fifo_depth_c and hdlc_i.valid = '1' then
          fifo_push := true;
          rin.in_state <= IN_DATA;
        end if;

      when IN_COMMIT =>
        if r.out_state = OUT_COMMIT and fcs_i.ready = '1' then
          rin.in_state <= IN_FLAG_START;
        end if;
    end case;

    case r.out_state is
      when OUT_RESET =>
        rin.out_state <= OUT_DATA;

      when OUT_DATA =>
        if r.fifo_fillness > 0 and fcs_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.in_state = IN_COMMIT
          and (r.fifo_fillness = 0
               or (r.fifo_fillness = 1 and fcs_i.ready = '1')) then
          rin.out_state <= OUT_COMMIT;
        end if;

      when OUT_COMMIT =>
        if fcs_i.ready = '1' then
          rin.out_state <= OUT_DATA;
        end if;
    end case;

    if fifo_push and fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & "--------";
      if r.in_state = IN_DATA_ESCAPED then
        rin.fifo(r.fifo_fillness-1) <= nsl_line_coding.hdlc.escape(hdlc_i.data);
      else
        rin.fifo(r.fifo_fillness-1) <= hdlc_i.data;
      end if;
    elsif fifo_push then
      if r.in_state = IN_DATA_ESCAPED then
        rin.fifo(r.fifo_fillness) <= nsl_line_coding.hdlc.escape(hdlc_i.data);
      else
        rin.fifo(r.fifo_fillness) <= hdlc_i.data;
      end if;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= r.fifo(1 to fifo_depth_c-1) & "--------";
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  moore: process(r) is
  begin
    fcs_o.data <= "--------";
    fcs_o.valid <= '0';
    fcs_o.last <= '-';

    case r.out_state is
      when OUT_RESET =>
        null;

      when OUT_COMMIT =>
        fcs_o.valid <= '1';
        fcs_o.last <= '1';
        fcs_o.data <= x"01";

      when OUT_DATA =>
        fcs_o.valid <= to_logic(r.fifo_fillness /= 0);
        fcs_o.last <= '0';
        fcs_o.data <= r.fifo(0);
    end case;

    case r.in_state is
      when IN_RESET | IN_COMMIT =>
        hdlc_o.ready <= '0';

      when IN_DATA | IN_DATA_ESCAPED =>
        hdlc_o.ready <= to_logic(r.fifo_fillness < fifo_depth_c);

      when IN_FLAG_START =>
        hdlc_o.ready <= '1';
    end case;
  end process;

  fcs: nsl_bnoc.crc.crc_committed_checker
    generic map(
      header_length_c => 0,
      crc_init_c => nsl_line_coding.hdlc.fcs_init_c,
      crc_poly_c =>  nsl_line_coding.hdlc.fcs_poly_c,
      crc_check_c => nsl_line_coding.hdlc.fcs_check_c,
      insert_msb_c => nsl_line_coding.hdlc.fcs_insert_msb_c,
      pop_lsb_c => nsl_line_coding.hdlc.fcs_pop_lsb_c,
      complement_c => nsl_line_coding.hdlc.fcs_complement_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      in_i => fcs_o,
      in_o => fcs_i,

      out_i => frame_i,
      out_o => frame_o
      );

end architecture;
