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
  
  signal to_fifo_req_s, from_fifo_req_s : committed_req;
  signal to_fifo_ack_s, from_fifo_ack_s : committed_ack;

  signal patch_fifo_input_ready_s, patch_fifo_input_valid_s : std_ulogic;
  signal patch_fifo_input_data_s : std_ulogic_vector(offset_length_c + 16 - 1 downto 0);
  signal patch_fifo_output_ready_s, patch_fifo_output_valid_s : std_ulogic;
  signal patch_fifo_output_data_s : std_ulogic_vector(offset_length_c + 16 - 1 downto 0);

begin

  checksummer: block
    type in_state_t is (
      IN_RESET,
      IN_FORWARD,
      IN_COMMIT,
      IN_CANCEL,
      IN_WAIT
      );

    type out_state_t is (
      OUT_RESET,
      OUT_FORWARD,
      OUT_COMMIT,
      OUT_CANCEL
      );

    type chk_state_t is (
      CHK_RESET,
      CHK_HEADER,
      CHK_IP,
      CHK_UDP,
      CHK_TCP,
      CHK_ICMP,
      CHK_OTHER,
      CHK_NOT_IP,
      CHK_PUT_IP_INFO,
      CHK_PUT_PDU_INFO,
      CHK_PUT_DONE
      );

    constant fifo_depth_c : integer := 2;

    type regs_t is
    record
      in_state : in_state_t;
      fifo: byte_string(0 to fifo_depth_c-1);
      fifo_fillness: integer range 0 to fifo_depth_c;
      out_state : out_state_t;

      chk_valid: boolean;
      chk_state : chk_state_t;
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
        r.in_state <= IN_RESET;
        r.out_state <= OUT_RESET;
        r.chk_state <= CHK_RESET;
      end if;
    end process;

    transition: process(r, input_i, to_fifo_ack_s, patch_fifo_input_ready_s) is
      variable fifo_push, fifo_pop: boolean;
    begin
      rin <= r;

      fifo_pop := false;
      fifo_push := false;

      case r.in_state is
        when IN_RESET =>
          if r.chk_state = CHK_RESET then
            rin.in_state <= IN_FORWARD;
          end if;

        when IN_FORWARD =>
          if input_i.valid = '1' and r.fifo_fillness < fifo_depth_c then
            if input_i.last = '0' then
              fifo_push := true;
            elsif input_i.data = x"01" then
              rin.in_state <= IN_COMMIT;
            else
              rin.in_state <= IN_CANCEL;
            end if;
          end if;

        when IN_COMMIT | IN_CANCEL =>
          if r.out_state = OUT_COMMIT or r.out_state = OUT_CANCEL then
            rin.in_state <= IN_WAIT;
          end if;

        when IN_WAIT =>
          rin.in_state <= IN_RESET;
      end case;

      case r.out_state is
        when OUT_RESET =>
          rin.out_state <= OUT_FORWARD;

        when OUT_FORWARD =>
          if to_fifo_ack_s.ready = '1' and r.fifo_fillness /= 0 then
            fifo_pop := true;
          end if;

          if r.fifo_fillness = 0
            or (to_fifo_ack_s.ready = '1' and r.fifo_fillness = 1) then
            if r.in_state = IN_COMMIT then
              rin.out_state <= OUT_COMMIT;
            elsif r.in_state = IN_CANCEL then
              rin.out_state <= OUT_CANCEL;
            end if;
          end if;

        when OUT_COMMIT | OUT_CANCEL =>
          if to_fifo_ack_s.ready = '1' then
            rin.out_state <= OUT_RESET;
          end if;
      end case;

      rin.chk_valid <= false;
      
      if fifo_push and fifo_pop then
        rin.chk_valid <= true;
        rin.fifo <= shift_left(r.fifo);
        rin.fifo(r.fifo_fillness-1) <= input_i.data;
      elsif fifo_push then
        rin.chk_valid <= true;
        rin.fifo(r.fifo_fillness) <= input_i.data;
        rin.fifo_fillness <= r.fifo_fillness + 1;
      elsif fifo_pop then
        rin.chk_valid <= r.fifo_fillness > 1;
        rin.fifo <= shift_left(r.fifo);
        rin.fifo_fillness <= r.fifo_fillness - 1;
      end if;

      case r.chk_state is
        when CHK_RESET =>
          rin.ipv4_checksum <= checksum_acc_init_c;
          rin.pdu_checksum <= checksum_acc_init_c;

          if r.in_state = IN_RESET then
            rin.total_offset <= (others => '0');
            rin.offset <= (others => '0');
            if header_length_c = 0 then
              rin.chk_state <= CHK_IP;
            else
              rin.chk_state <= CHK_HEADER;
            end if;
          end if;

        when CHK_HEADER =>
          if r.chk_valid then
            rin.total_offset <= r.total_offset + 1;
            rin.offset <= r.offset + 1;

            if r.offset = header_length_c - 1 then
              rin.chk_state <= CHK_IP;
              rin.offset <= (others => '0');
            end if;
          end if;

          if r.in_state = IN_WAIT then
            rin.chk_state <= CHK_PUT_DONE;
          end if;

        when CHK_IP =>
          if r.chk_valid then
            rin.total_offset <= r.total_offset + 1;
            rin.offset <= r.offset + 1;
            
            rin.ipv4_checksum <= checksum_update(r.ipv4_checksum, r.fifo(0));

            case to_integer(r.offset) is
              when ip_off_type_len =>
                if r.fifo(0)(7 downto 4) /= x"4" then
                  rin.chk_state <= CHK_NOT_IP;
                end if;
                rin.ipv4_last <= to_unsigned(header_length_c - 1, rin.ipv4_last'length)
                                 + resize(unsigned(r.fifo(0)(3 downto 0)) & "00", rin.ipv4_last'length);
                -- By adding total ip length to pseudo-header checksum,
                -- we have a checksum off by ip header size. Correct
                -- this by setting (not(header_size)) ==
                -- (-header_size-1) to a correction factor.
                rin.ip_header_size_correction <= "11" & (not r.fifo(0)(3 downto 0)) & "11";
                
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
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, r.fifo(0));
                rin.ip_proto <= to_integer(unsigned(r.fifo(0)));

              when ip_off_len_h | ip_off_len_l
                | ip_off_src0 | ip_off_src1 | ip_off_src2 | ip_off_src3
                | ip_off_dst0 | ip_off_dst1 | ip_off_dst2 | ip_off_dst3 =>
                -- TCP/UDP a pseudo-header (address, len)
                rin.pdu_checksum <= checksum_update(r.pdu_checksum, r.fifo(0));

              when others =>
                null;
            end case;

            if r.offset /= 0 and r.total_offset = r.ipv4_last then
              rin.offset <= (others => '0');
              case r.ip_proto is
                when ip_proto_tcp =>
                  rin.chk_state <= CHK_TCP;
                  rin.pdu_checksum_offset <= r.ipv4_last + 1 + 16;
                when ip_proto_udp =>
                  rin.chk_state <= CHK_UDP;
                  rin.pdu_checksum_offset <= r.ipv4_last + 1 + 6;
                when ip_proto_icmp =>
                  rin.chk_state <= CHK_ICMP;
                  rin.pdu_checksum_offset <= r.ipv4_last + 1 + 2;
                  -- ICMP does not have a pseudo-header
                  rin.pdu_checksum <= checksum_acc_init_c;
                when others =>
                  rin.chk_state <= CHK_OTHER;
              end case;
            end if;
          end if;

          if r.in_state = IN_WAIT then
            rin.chk_state <= CHK_PUT_DONE;
          end if;

        when CHK_UDP | CHK_TCP | CHK_ICMP | CHK_OTHER =>
          if r.chk_valid then
            rin.total_offset <= r.total_offset + 1;
            rin.offset <= r.offset + 1;

            if r.pdu_checksum_offset /= r.total_offset and r.pdu_checksum_offset + 1 /= r.total_offset then
              rin.pdu_checksum <= checksum_update(r.pdu_checksum, r.fifo(0));
            end if;
          elsif r.in_state = IN_COMMIT or r.in_state = IN_CANCEL or r.in_state = IN_WAIT then
            rin.chk_state <= CHK_PUT_IP_INFO;
          end if;

        when CHK_NOT_IP =>
          if r.in_state = IN_COMMIT or r.in_state = IN_CANCEL or r.in_state = IN_WAIT then
            rin.chk_state <= CHK_PUT_DONE;
          end if;

        when CHK_PUT_IP_INFO =>
          if patch_fifo_input_ready_s = '1' then
            case r.ip_proto is
              when ip_proto_tcp | ip_proto_udp | ip_proto_icmp =>
                rin.chk_state <= CHK_PUT_PDU_INFO;
              when others =>
                rin.chk_state <= CHK_PUT_DONE;
            end case;
          end if;

        when CHK_PUT_PDU_INFO =>
          if patch_fifo_input_ready_s = '1' then
            rin.chk_state <= CHK_PUT_DONE;
          end if;

        when CHK_PUT_DONE =>
          if patch_fifo_input_ready_s = '1' then
            rin.chk_state <= CHK_RESET;
          end if;
      end case;
    end process;

    moore: process(r) is
    begin
      case r.in_state is
        when IN_RESET | IN_WAIT | IN_COMMIT | IN_CANCEL =>
          input_o <= committed_accept(false);

        when IN_FORWARD =>
          input_o <= committed_accept(r.fifo_fillness < fifo_depth_c);
      end case;

      case r.out_state is
        when OUT_RESET =>
          to_fifo_req_s <= committed_flit(data => "--------", valid => false);

        when OUT_FORWARD =>
          to_fifo_req_s <= committed_flit(data => r.fifo(0), valid => r.fifo_fillness /= 0, last => false);

        when OUT_COMMIT =>
          to_fifo_req_s <= committed_commit(true);

        when OUT_CANCEL =>
          to_fifo_req_s <= committed_commit(false);
      end case;

      case r.chk_state is
        when CHK_RESET | CHK_HEADER | CHK_IP | CHK_UDP | CHK_TCP | CHK_ICMP | CHK_OTHER | CHK_NOT_IP =>
          patch_fifo_input_valid_s <= '0';
          patch_fifo_input_data_s <= (others => '-');

        when CHK_PUT_IP_INFO =>
          patch_fifo_input_valid_s <= '1';
          patch_fifo_input_data_s <= std_ulogic_vector(r.ipv4_checksum_offset
                                                       & from_be(checksum_spill(r.ipv4_checksum)));

        when CHK_PUT_PDU_INFO =>
          patch_fifo_input_valid_s <= '1';
          patch_fifo_input_data_s <= std_ulogic_vector(r.pdu_checksum_offset
                                                       & from_be(checksum_spill(r.pdu_checksum,
                                                                                r.offset(0) = '1')));

        when CHK_PUT_DONE =>
          patch_fifo_input_valid_s <= '1';
          patch_fifo_input_data_s <= (others => '0');
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

    transition: process(r, output_i, from_fifo_req_s, patch_fifo_output_valid_s, patch_fifo_output_data_s) is
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
            rin.patch_offset <= unsigned(patch_fifo_output_data_s(offset_length_c + 16 - 1 downto 16));
            rin.patch_data <= patch_fifo_output_data_s(15 downto 0);
            if unsigned(patch_fifo_output_data_s(offset_length_c + 16 - 1 downto 16)) = 0 then
              rin.in_state <= IN_FLUSH;
            else
              rin.in_state <= IN_PATCH_H;
            end if;
          end if;

        when IN_PATCH_H =>
          if from_fifo_req_s.valid = '1' and r.fifo_fillness < fifo_depth_c then
            rin.offset <= r.offset + 1;

            fifo_push := true;
            if r.offset = r.patch_offset then
              rin.in_state <= IN_PATCH_L;
              fifo_data := r.patch_data(15 downto 8);
            else
              fifo_data := from_fifo_req_s.data;
            end if;

            assert from_fifo_req_s.last = '0'
              report "Short packet while we did not reach patch end"
              severity failure;
          end if;

        when IN_PATCH_L =>
          if from_fifo_req_s.valid = '1' and r.fifo_fillness < fifo_depth_c then
            rin.offset <= r.offset + 1;

            fifo_push := true;
            fifo_data := r.patch_data(7 downto 0);

            if patch_fifo_output_valid_s = '1' then
              rin.patch_offset <= unsigned(patch_fifo_output_data_s(offset_length_c + 16 - 1 downto 16));
              rin.patch_data <= patch_fifo_output_data_s(15 downto 0);
              if unsigned(patch_fifo_output_data_s(offset_length_c + 16 - 1 downto 16)) = 0 then
                rin.in_state <= IN_FLUSH;
              else
                rin.in_state <= IN_PATCH_H;
              end if;
            else
              rin.in_state <= IN_PATCH_GET;
            end if;

            assert from_fifo_req_s.last = '0'
              report "Short packet while we did not reach patch end"
              severity failure;
          end if;
          
        when IN_FLUSH =>
          if from_fifo_req_s.valid = '1' and r.fifo_fillness < fifo_depth_c then
            rin.offset <= r.offset + 1;

            fifo_push := true;
            fifo_data := from_fifo_req_s.data;

            if from_fifo_req_s.last = '1' then
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
      from_fifo_ack_s <= committed_accept(false);

      case r.in_state is
        when IN_RESET | IN_DONE =>
          null;

        when IN_PATCH_GET =>
          patch_fifo_output_ready_s <= '1';

        when IN_PATCH_H | IN_FLUSH =>
          from_fifo_ack_s <= committed_accept(r.fifo_fillness < fifo_depth_c);

        when IN_PATCH_L =>
          from_fifo_ack_s <= committed_accept(r.fifo_fillness < fifo_depth_c);
          patch_fifo_output_ready_s <= '1';
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

      in_i => to_fifo_req_s,
      in_o => to_fifo_ack_s,

      out_o => from_fifo_req_s,
      out_i => from_fifo_ack_s
      );

end architecture;
