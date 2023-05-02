library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_memory, nsl_logic, nsl_math, nsl_bnoc;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.to_logic;
use nsl_logic.bool.if_else;

entity device_ep_framed_in is
  generic (
    hs_supported_c : boolean;
    fs_mps_l2_c : integer range 3 to 6 := 6;
    double_buffer_c : boolean := true
    );
  port (
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    transaction_i : in  transaction_cmd;
    transaction_o : out transaction_rsp;

    framed_i : in nsl_bnoc.framed.framed_req;
    framed_o : out nsl_bnoc.framed.framed_ack
    );

end entity;

architecture beh of device_ep_framed_in is

  constant mps_l2_c : integer := if_else(hs_supported_c, 9, fs_mps_l2_c);
  constant fifo_packet_count_c : integer := if_else(double_buffer_c, 2, 1);
  constant fifo_word_count_l2_c: integer := mps_l2_c + if_else(double_buffer_c, 1, 0);

  subtype ram_ptr_t is unsigned(fifo_word_count_l2_c-1 downto 0);
  subtype pkt_size_t is unsigned(mps_l2_c downto 0);

  type sie_state_t is (
    SIE_RESET,
    SIE_IDLE,
    SIE_FILL,
    SIE_SEND,
    SIE_SEND_LAST,
    SIE_HS_IN,
    SIE_ZLP,
    SIE_STALL,
    SIE_NAK
    );

  type stream_state_t is (
    STREAM_RESET,
    STREAM_FILL,
    STREAM_SWITCH,
    STREAM_ZLP
    );

  type packet_t is
  record
    valid: boolean;
    length: pkt_size_t;
  end record;

  subtype packet_index is integer range 0 to fifo_packet_count_c-1;
  type packet_array is array (packet_index) of packet_t;

  constant fifo_depth_c : integer := 4;

  type regs_t is
  record
    pkt: packet_array;

    halted: boolean;
    mps_m1: pkt_size_t;

    sie_state: sie_state_t;
    sie_pkt: packet_index;
    sie_packet_no: std_ulogic;
    sie_has_read: boolean;
    sie_ptr: pkt_size_t;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    stream_state: stream_state_t;
    stream_pkt: packet_index;
    stream_ptr: pkt_size_t;
    stream_zlp_pending: boolean;
  end record;

  signal r, rin : regs_t;

  signal ram_rdata_s, ram_wdata_s : byte;
  signal ram_raddr_s, ram_waddr_s : ram_ptr_t;
  signal ram_wen_s, ram_ren_s : std_ulogic;

  function packet_next(cur : packet_index) return packet_index is
  begin
    if cur = fifo_packet_count_c-1 then
      return 0;
    else
      return cur + 1;
    end if;
  end function;
  
begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.sie_state <= SIE_RESET;
      r.stream_state <= STREAM_RESET;
      r.halted <= false;
      r.fifo_fillness <= 0;
      for i in packet_array'range
      loop
        r.pkt(i).valid <= false;
        r.pkt(i).length <= (others => '0');
      end loop;
    end if;
  end process;

  transition: process(r, transaction_i, framed_i, ram_rdata_s) is
    variable fifo_push, fifo_pop: boolean;
  begin
    rin <= r;

    fifo_pop := false;
    fifo_push := false;

    if hs_supported_c and transaction_i.hs = '1' then
      rin.mps_m1 <= to_unsigned((2 ** 9) - 1, rin.mps_m1'length);
    else
      rin.mps_m1 <= to_unsigned((2 ** fs_mps_l2_c) - 1, rin.mps_m1'length);
    end if;
    
    case r.sie_state is
      when SIE_RESET =>
        rin.sie_state <= SIE_IDLE;
        rin.sie_ptr <= (others => '0');
        rin.sie_pkt <= 0;
        rin.sie_packet_no <= '0';

      when SIE_IDLE =>
        rin.sie_ptr <= (others => '0');
        rin.fifo_fillness <= 0;
        rin.sie_has_read <= false;

        if not r.halted and transaction_i.phase /= PHASE_NONE then
          if not r.pkt(r.sie_pkt).valid then
            rin.sie_state <= SIE_NAK;
          elsif r.pkt(r.sie_pkt).length = 0 then
            rin.sie_state <= SIE_ZLP;
          else
            rin.sie_state <= SIE_FILL;
          end if;
        end if;

      when SIE_FILL =>
        rin.sie_has_read <= false;
        fifo_push := r.sie_has_read;

        if r.sie_ptr = r.pkt(r.sie_pkt).length then
          rin.sie_state <= SIE_SEND_LAST;
        elsif r.fifo_fillness >= fifo_depth_c - 1 then
          rin.sie_state <= SIE_SEND;
        else
          rin.sie_ptr <= r.sie_ptr + 1;
          rin.sie_has_read <= true;
        end if;
        
      when SIE_SEND | SIE_SEND_LAST =>
        case transaction_i.phase is
          when PHASE_NONE =>
            rin.sie_ptr <= (others => '0');
            rin.sie_state <= SIE_IDLE;

          when PHASE_TOKEN =>
            null;

          when PHASE_DATA =>
            rin.sie_has_read <= false;
            fifo_push := r.sie_has_read;
            fifo_pop := transaction_i.nxt = '1' and r.fifo_fillness > 0;

            if r.sie_state = SIE_SEND then
              if r.sie_ptr = r.pkt(r.sie_pkt).length then
                rin.sie_state <= SIE_SEND_LAST;
              elsif r.fifo_fillness < fifo_depth_c - 1 then
                rin.sie_ptr <= r.sie_ptr + 1;
                rin.sie_has_read <= true;
              end if;
            end if;

          when PHASE_HANDSHAKE =>
            -- Early termination ? Is this even possible ?
            rin.sie_state <= SIE_HS_IN;
        end case;
        
      when SIE_STALL | SIE_NAK =>
        if transaction_i.phase = PHASE_NONE then
          rin.sie_ptr <= (others => '0');
          rin.sie_state <= SIE_IDLE;
        end if;

      when SIE_ZLP =>
        rin.sie_state <= SIE_HS_IN;
        
      when SIE_HS_IN =>
        case transaction_i.phase is
          when PHASE_HANDSHAKE =>
            case transaction_i.handshake is
              when HANDSHAKE_ACK =>
                rin.pkt(r.sie_pkt).valid <= false;
                rin.sie_pkt <= packet_next(r.sie_pkt);
                rin.sie_ptr <= (others => '0');
                rin.sie_state <= SIE_IDLE;
                rin.sie_packet_no <= not r.sie_packet_no;

              when HANDSHAKE_NAK =>
                rin.sie_ptr <= (others => '0');
                rin.sie_state <= SIE_IDLE;

              when others =>
                null;
            end case;

          when PHASE_DATA =>
            null;

          when others =>
            rin.sie_ptr <= (others => '0');
            rin.sie_state <= SIE_IDLE;
        end case;
    end case;

    case r.stream_state is
      when STREAM_RESET =>
        rin.stream_state <= STREAM_FILL;
        rin.stream_ptr <= (others => '0');
        rin.stream_pkt <= 0;

      when STREAM_FILL =>
        if not r.pkt(r.stream_pkt).valid and framed_i.valid = '1' and not r.halted then
          rin.stream_ptr <= r.stream_ptr + 1;

          if framed_i.last = '1' or r.stream_ptr = r.mps_m1 then
            rin.stream_state <= STREAM_SWITCH;
            rin.stream_zlp_pending <= framed_i.last = '1' and r.stream_ptr = r.mps_m1;
          end if;
        end if;
        
      when STREAM_SWITCH =>
        rin.pkt(r.stream_pkt).valid <= true;
        rin.pkt(r.stream_pkt).length <= r.stream_ptr;
        rin.stream_ptr <= (others => '0');
        rin.stream_pkt <= packet_next(r.stream_pkt);
        if r.stream_zlp_pending then
          rin.stream_state <= STREAM_ZLP;
        else
          rin.stream_state <= STREAM_FILL;
        end if;

      when STREAM_ZLP =>
        if not r.pkt(r.stream_pkt).valid then
          rin.pkt(r.stream_pkt).valid <= true;
          rin.pkt(r.stream_pkt).length <= (others => '0');
          rin.stream_pkt <= packet_next(r.stream_pkt);
        end if;
    end case;
        
    if transaction_i.clear = '1' then
      rin.halted <= false;
      rin.sie_state <= SIE_RESET;
      rin.stream_state <= STREAM_RESET;

      for i in packet_array'range
      loop
        rin.pkt(i).valid <= false;
        rin.pkt(i).length <= (others => '0');
      end loop;
    elsif transaction_i.halt = '1' then
      rin.halted <= true;
    end if;

    if fifo_push and fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo(r.fifo_fillness-1) <= ram_rdata_s;
    elsif fifo_push then
      rin.fifo(r.fifo_fillness) <= ram_rdata_s;
      rin.fifo_fillness <= r.fifo_fillness + 1;
    elsif fifo_pop then
      rin.fifo <= shift_left(r.fifo);
      rin.fifo_fillness <= r.fifo_fillness - 1;
    end if;
  end process;

  ram_wdata_s <= framed_i.data;
  
  ram: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => ram_ptr_t'length,
      data_size_c => 8,
      clock_count_c => 1,
      registered_output_c => false
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => ram_waddr_s,
      write_en_i => ram_wen_s,
      write_data_i => ram_wdata_s,

      read_address_i => ram_raddr_s,
      read_en_i => ram_ren_s,
      read_data_o => ram_rdata_s
      );

  moore: process(r, framed_i) is
  begin
    transaction_o <= TRANSACTION_RSP_IDLE;
    transaction_o.toggle  <= '-';
    transaction_o.last <= '-';
    transaction_o.data <= (others => '-');

    ram_ren_s <= '0';
    ram_raddr_s <= resize(r.sie_ptr, ram_raddr_s'length);
    if double_buffer_c then
      ram_raddr_s(ram_raddr_s'left) <= to_logic(r.sie_pkt /= 0);
    end if;
    
    case r.sie_state is
      when SIE_IDLE | SIE_RESET =>
        transaction_o.phase <= PHASE_TOKEN;
        transaction_o.handshake <= HANDSHAKE_ACK;
        ram_ren_s <= '1';

      when SIE_FILL =>
        ram_ren_s <= '1';
        transaction_o.phase <= PHASE_TOKEN;
        transaction_o.handshake <= HANDSHAKE_ACK;

      when SIE_SEND =>
        ram_ren_s <= '1';
        transaction_o.phase <= PHASE_DATA;
        transaction_o.toggle  <= r.sie_packet_no;
        transaction_o.last <= '0';
        transaction_o.data <= r.fifo(0);
        transaction_o.handshake <= HANDSHAKE_ACK;

      when SIE_SEND_LAST =>
        if r.fifo_fillness /= 0 then
          transaction_o.phase <= PHASE_DATA;
        else
          transaction_o.phase <= PHASE_HANDSHAKE;
        end if;
        transaction_o.handshake <= HANDSHAKE_ACK;
        transaction_o.toggle  <= r.sie_packet_no;
        transaction_o.data <= r.fifo(0);
        transaction_o.last <= to_logic(r.fifo_fillness <= 1 and not r.sie_has_read);

      when SIE_STALL =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_STALL;

      when SIE_NAK =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_NAK;

      when SIE_ZLP =>
        transaction_o.phase <= PHASE_TOKEN;
        transaction_o.handshake <= HANDSHAKE_ACK;

      when SIE_HS_IN =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_ACK;
    end case;

    ram_wen_s <= '0';
    ram_waddr_s <= resize(r.stream_ptr, ram_waddr_s'length);
    if double_buffer_c then
      ram_waddr_s(ram_waddr_s'left) <= to_logic(r.stream_pkt /= 0);
    end if;

    framed_o.ready <= '0';
    
    case r.stream_state is
      when STREAM_RESET | STREAM_SWITCH | STREAM_ZLP =>
        null;

      when STREAM_FILL =>
        framed_o.ready <= to_logic(not r.pkt(r.stream_pkt).valid or r.halted);
        ram_wen_s <= to_logic(not r.pkt(r.stream_pkt).valid or r.halted) and framed_i.valid;
    end case;

    transaction_o.halted <= to_logic(r.halted);
    if r.halted then
      transaction_o.phase <= PHASE_HANDSHAKE;
      transaction_o.handshake <= HANDSHAKE_STALL;
    end if;
  end process;
  
end architecture;
