library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, work, nsl_math, nsl_logic, nsl_memory, nsl_data;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ipv4.all;
use work.checksum.all;
use nsl_logic.bool.all;
use nsl_data.text.all;

entity ipv4_checksum_inserter is
  generic(
    header_length_c : integer;
    mtu_c: integer := 1500;
    handle_tcp_c: boolean := true;
    handle_udp_c: boolean := true
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    -- IPv4 packet input
    input_i : in committed_req;
    input_o : out committed_ack;

    -- IPv4 packet output
    output_o : out committed_req;
    output_i : in committed_ack
    );
end entity;

architecture beh of ipv4_checksum_inserter is

  constant offset_length_c: integer := nsl_math.arith.log2(mtu_c);
  subtype offset_t is unsigned(offset_length_c-1 downto 0);

  signal to_fifo_en_s : std_ulogic;
  signal to_fifo_s, from_fifo_s : committed_bus;

  signal patch_fifo_input_ready_s, patch_fifo_input_valid_s : std_ulogic;
  signal patch_fifo_input_data_s : std_ulogic_vector(offset_length_c + 16 downto 0);
  signal patch_fifo_output_ready_s, patch_fifo_output_valid_s : std_ulogic;
  signal patch_fifo_output_data_s : std_ulogic_vector(offset_length_c + 16 downto 0);

begin

  checksummer: block
    type state_t is (
      ST_RESET,
      ST_HEADER,
      ST_IP,
      ST_UDP,
      ST_TCP,
      ST_ICMP,
      ST_OTHER,
      ST_NOT_IP,
      ST_PUT_IP_INFO,
      ST_PUT_PDU_INFO,
      ST_PUT_DONE
      );

    type regs_t is
    record
      state : state_t;
      total_offset, offset, ipv4_last : offset_t;
      ipv4_checksum, pdu_checksum : checksum_acc_t;
      ip_header_size_correction: byte;
      ipv4_checksum_offset, pdu_checksum_offset : offset_t;
      ip_proto : ip_proto_t;
    end record;

    signal r, rin: regs_t;
    
  begin

    regs: process(clock_i, reset_n_i) is
    begin
      if rising_edge(clock_i) then
        r <= rin;
      end if;

      if reset_n_i = '0' then
        r.state <= ST_RESET;
      end if;
    end process;

    to_fifo_s.req.data <= input_i.data;
    to_fifo_s.req.valid <= input_i.valid and to_fifo_en_s;
    to_fifo_s.req.last <= input_i.last;
    input_o.ready <= to_fifo_s.ack.ready and to_fifo_en_s;
    
    transition: process(r, input_i, to_fifo_s.ack, patch_fifo_input_ready_s) is
      variable valid, last: boolean;
      variable data: byte;
    begin
      rin <= r;

      valid := input_i.valid = '1' and to_fifo_s.ack.ready = '1';
      last := input_i.last = '1';
      data := input_i.data;
      
      case r.state is
        when ST_RESET =>
          rin.ipv4_checksum <= checksum_acc_init_c;
          rin.pdu_checksum <= checksum_acc_init_c;

          rin.total_offset <= (others => '0');
          rin.offset <= (others => '0');
          if header_length_c = 0 then
            rin.state <= ST_IP;
          else
            rin.state <= ST_HEADER;
          end if;

        when ST_HEADER =>
          if valid then
            rin.total_offset <= r.total_offset + 1;
            rin.offset <= r.offset + 1;

            if r.offset = header_length_c - 1 then
              rin.state <= ST_IP;
              rin.offset <= (others => '0');
            end if;
          end if;

          if last then
            rin.state <= ST_PUT_DONE;
          end if;

        when ST_IP =>
          if valid then
            rin.total_offset <= r.total_offset + 1;
            rin.offset <= r.offset + 1;
            
            rin.ipv4_checksum <= checksum_update(r.ipv4_checksum, data);

            case to_integer(r.offset) is
              when ip_off_type_len =>
                if data(7 downto 4) /= x"4" then
                  rin.state <= ST_NOT_IP;
                end if;
                rin.ipv4_last <= unsigned(to_signed(header_length_c - 1, rin.ipv4_last'length))
                                 + resize(unsigned(data(3 downto 0)) & "00", rin.ipv4_last'length);
                -- By adding total ip length to pseudo-header checksum,
                -- we have a checksum off by ip header size. Correct
                -- this by setting (not(header_size)) ==
                -- (-header_size-1) to a correction factor.
                rin.ip_header_size_correction <= "11" & (not data(3 downto 0)) & "11";
                
              when ip_off_chk_h =>
                rin.ipv4_checksum_offset <= r.total_offset;
                -- Apply correction factor to checksum (high order)
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, x"ff");
                -- Do not update IPv4 checksum with current checksum field
                rin.ipv4_checksum <= r.ipv4_checksum;

              when ip_off_chk_l =>
                -- Apply correction factor to checksum (low order)
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, r.ip_header_size_correction);
                -- Do not update IPv4 checksum with current checksum field
                rin.ipv4_checksum <= r.ipv4_checksum;

              when ip_off_ttl =>
                -- TCP/UDP a pseudo-header, protocol number (high)
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, x"00");

              when ip_off_proto =>
                -- TCP/UDP a pseudo-header, protocol number (low)
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, data);
                rin.ip_proto <= to_integer(unsigned(data));

              when ip_off_len_h | ip_off_len_l
                | ip_off_src0 | ip_off_src1 | ip_off_src2 | ip_off_src3
                | ip_off_dst0 | ip_off_dst1 | ip_off_dst2 | ip_off_dst3 =>
                -- TCP/UDP a pseudo-header (address, len)
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, data);

              when others =>
                null;
            end case;

            if r.offset /= 0 and r.total_offset = r.ipv4_last then
              rin.offset <= (others => '0');
              case r.ip_proto is
                when ip_proto_tcp =>
                  rin.state <= ST_TCP;
                  rin.pdu_checksum_offset <= r.ipv4_last + 1 + 16;
                when ip_proto_udp =>
                  rin.state <= ST_UDP;
                  rin.pdu_checksum_offset <= r.ipv4_last + 1 + 6;
                when ip_proto_icmp =>
                  rin.state <= ST_ICMP;
                  rin.pdu_checksum_offset <= r.ipv4_last + 1 + 2;
                  -- ICMP does not have a pseudo-header
                  rin.pdu_checksum <= checksum_acc_init_c;
                when others =>
                  rin.state <= ST_OTHER;
              end case;
            end if;
          end if;

          if last then
            rin.state <= ST_PUT_DONE;
          end if;

        when ST_UDP | ST_TCP | ST_ICMP | ST_OTHER =>
          if valid then
            if last then
              rin.state <= ST_PUT_IP_INFO;
            else
              rin.total_offset <= r.total_offset + 1;
              rin.offset <= r.offset + 1;

              if r.pdu_checksum_offset /= r.total_offset and r.pdu_checksum_offset + 1 /= r.total_offset then
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, data);
              end if;
            end if;
          end if;

        when ST_NOT_IP =>
          if valid and last then
            rin.state <= ST_PUT_DONE;
          end if;

        when ST_PUT_IP_INFO =>
          if patch_fifo_input_ready_s = '1' then
            case r.ip_proto is
              when ip_proto_tcp | ip_proto_udp | ip_proto_icmp =>
                rin.state <= ST_PUT_PDU_INFO;
              when others =>
                rin.state <= ST_RESET;
            end case;
          end if;

        when ST_PUT_PDU_INFO | ST_PUT_DONE =>
          if patch_fifo_input_ready_s = '1' then
            rin.state <= ST_RESET;
          end if;
      end case;
    end process;

    moore: process(r) is
    begin
      to_fifo_en_s <= '0';
      patch_fifo_input_valid_s <= '0';
      patch_fifo_input_data_s <= (others => '-');

      case r.state is
        when ST_PUT_IP_INFO =>
          patch_fifo_input_valid_s <= '1';
          patch_fifo_input_data_s <= std_ulogic_vector("0"
                                                       & r.ipv4_checksum_offset
                                                       & from_be(checksum_spill(r.ipv4_checksum)));

          case r.ip_proto is
            when ip_proto_tcp | ip_proto_udp | ip_proto_icmp =>
              null;
            when others =>
              patch_fifo_input_data_s(patch_fifo_input_data_s'left) <= '1';
          end case;

        when ST_PUT_PDU_INFO =>
          patch_fifo_input_valid_s <= '1';
          patch_fifo_input_data_s <= std_ulogic_vector("1"
                                                       & r.pdu_checksum_offset
                                                       & from_be(checksum_spill(r.pdu_checksum,
                                                                                r.offset(0) = '1')));

        when ST_PUT_DONE =>
          patch_fifo_input_valid_s <= '1';
          patch_fifo_input_data_s <= (others => '0');
          patch_fifo_input_data_s(patch_fifo_input_data_s'left) <= '1';

        when ST_RESET =>
          null;

        when ST_HEADER | ST_IP | ST_UDP | ST_TCP | ST_ICMP | ST_OTHER | ST_NOT_IP =>
          to_fifo_en_s <= '1';
      end case;
    end process;
  end block;

  patcher: block
    type in_state_t is (
      IN_RESET,
      IN_PATCH_GET,
      IN_PATCH_H,
      IN_PATCH_L,
      IN_FLUSH,
      IN_DONE
      );

    type out_state_t is (
      OUT_RESET,
      OUT_FORWARD,
      OUT_DONE
      );

    constant fifo_depth_c : integer := 3;

    type regs_t is
    record
      in_state : in_state_t;
      fifo: byte_string(0 to fifo_depth_c-1);
      fifo_fillness: integer range 0 to fifo_depth_c;
      out_state : out_state_t;

      offset, patch_offset : offset_t;
      patch_data : std_ulogic_vector(15 downto 0);
      patch_done : boolean;
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

    transition: process(r, output_i, from_fifo_s.req, patch_fifo_output_valid_s, patch_fifo_output_data_s) is
      variable fifo_push, fifo_pop: boolean;
      variable fifo_data: byte;
    begin
      rin <= r;

      fifo_pop := false;
      fifo_push := false;
      fifo_data := "--------";

      case r.in_state is
        when IN_RESET =>
          rin.in_state <= IN_PATCH_GET;
          rin.offset <= (others => '0');
          rin.fifo_fillness <= 0;

        when IN_PATCH_GET =>
          if patch_fifo_output_valid_s = '1' then
            rin.patch_done <= patch_fifo_output_data_s(patch_fifo_output_data_s'left) = '1';
            rin.patch_offset <= unsigned(patch_fifo_output_data_s(offset_length_c + 16 - 1 downto 16));
            rin.patch_data <= patch_fifo_output_data_s(15 downto 0);
            if unsigned(patch_fifo_output_data_s(offset_length_c + 16 - 1 downto 16)) = 0
              and patch_fifo_output_data_s(patch_fifo_output_data_s'left) = '1' then
              rin.in_state <= IN_FLUSH;
            else
              rin.in_state <= IN_PATCH_H;
            end if;
          end if;

        when IN_PATCH_H =>
          if from_fifo_s.req.valid = '1' and r.fifo_fillness < fifo_depth_c then
            rin.offset <= r.offset + 1;

            fifo_push := true;
            if r.offset = r.patch_offset then
              rin.in_state <= IN_PATCH_L;
              fifo_data := r.patch_data(15 downto 8);
            else
              fifo_data := from_fifo_s.req.data;
            end if;

            assert from_fifo_s.req.last = '0'
              report "Short packet while we did not reach patch end"
              severity failure;
          end if;

        when IN_PATCH_L =>
          if from_fifo_s.req.valid = '1' and r.fifo_fillness < fifo_depth_c then
            rin.offset <= r.offset + 1;

            fifo_push := true;
            fifo_data := r.patch_data(7 downto 0);

            if r.patch_done then
              rin.in_state <= IN_FLUSH;
            else
              rin.in_state <= IN_PATCH_GET;
            end if;

            assert from_fifo_s.req.last = '0'
              report "Short packet while we did not reach patch end"
              severity failure;
          end if;
          
        when IN_FLUSH =>
          if from_fifo_s.req.valid = '1' and r.fifo_fillness < fifo_depth_c then
            rin.offset <= r.offset + 1;

            fifo_push := true;
            fifo_data := from_fifo_s.req.data;

            if from_fifo_s.req.last = '1' then
              rin.in_state <= IN_DONE;
            end if;
          end if;

        when IN_DONE =>
          if r.fifo_fillness = 0 then
            rin.in_state <= IN_RESET;
          end if;
      end case;

      case r.out_state is
        when OUT_RESET =>
          rin.out_state <= OUT_FORWARD;

        when OUT_FORWARD =>
          if output_i.ready = '1' and r.fifo_fillness > 1 then
            fifo_pop := true;
          end if;

          if r.in_state = IN_DONE then
            rin.out_state <= OUT_DONE;
          end if;

        when OUT_DONE =>
          if output_i.ready = '1' and r.fifo_fillness > 0 then
            fifo_pop := true;
          end if;

          if (output_i.ready = '1' and r.fifo_fillness = 1)
            or r.fifo_fillness = 0 then
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
      patch_fifo_output_ready_s <= '0';
      from_fifo_s.ack <= committed_accept(false);

      case r.in_state is
        when IN_RESET | IN_DONE =>
          null;

        when IN_PATCH_GET =>
          patch_fifo_output_ready_s <= '1';

        when IN_PATCH_H | IN_FLUSH =>
          from_fifo_s.ack <= committed_accept(r.fifo_fillness < fifo_depth_c);

        when IN_PATCH_L =>
          from_fifo_s.ack <= committed_accept(r.fifo_fillness < fifo_depth_c);
      end case;

      case r.out_state is
        when OUT_RESET =>
          output_o <= committed_req_idle_c;

        when OUT_FORWARD =>
          output_o <= committed_flit(data => r.fifo(0), valid => r.fifo_fillness > 1, last => false);

        when OUT_DONE =>
          output_o <= committed_flit(data => r.fifo(0), valid => r.fifo_fillness > 0, last => r.fifo_fillness = 1);
      end case;
    end process;
  end block;

  check_fifo: nsl_memory.fifo.fifo_homogeneous
    generic map(
      data_width_c => patch_fifo_input_data_s'length,
      word_count_c => 8,
      clock_count_c => 1,
      input_slice_c => false,
      output_slice_c => false,
      register_counters_c => false
      )
    port map(
      clock_i(0) => clock_i,
      reset_n_i => reset_n_i,

      out_data_o => patch_fifo_output_data_s,
      out_ready_i => patch_fifo_output_ready_s,
      out_valid_o => patch_fifo_output_valid_s,

      in_data_i => patch_fifo_input_data_s,
      in_valid_i => patch_fifo_input_valid_s,
      in_ready_o => patch_fifo_input_ready_s
      );

  data_fifo: nsl_bnoc.committed.committed_fifo
    generic map(
      clock_count_c => 1,
      depth_c => nsl_math.arith.align_up(mtu_c)
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i(0) => clock_i,

      in_i => to_fifo_s.req,
      in_o => to_fifo_s.ack,

      out_o => from_fifo_s.req,
      out_i => from_fifo_s.ack
      );

end architecture;
