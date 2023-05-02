library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic, nsl_math, nsl_memory, nsl_bnoc;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.device.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;
use nsl_bnoc.framed.all;

entity device_ep_framed_out is
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

    framed_o : out nsl_bnoc.framed.framed_req;
    framed_i : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture beh of device_ep_framed_out is

  constant mps_l2_c : integer := if_else(hs_supported_c, 9, fs_mps_l2_c);
  constant fifo_packet_count_c : integer := if_else(double_buffer_c, 2, 1);
  constant fifo_word_count_l2_c: integer := mps_l2_c + if_else(double_buffer_c, 1, 0);

  subtype ram_ptr_t is unsigned(fifo_word_count_l2_c-1 downto 0);
  subtype pkt_size_t is unsigned(mps_l2_c downto 0);

  type sie_state_t is (
    SIE_RESET,
    SIE_IDLE,
    SIE_TAKE,
    SIE_IGNORE_ACK,
    SIE_IGNORE_NAK,
    SIE_ACK,
    SIE_NAK
    );

  type stream_state_t is (
    STREAM_RESET,
    STREAM_IDLE,
    STREAM_FILL,
    STREAM_FULL,
    STREAM_SHORT,
    STREAM_SHORT_COMMIT
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
    mps: pkt_size_t;

    sie_state: sie_state_t;
    sie_pkt: packet_index;
    sie_packet_no: std_ulogic;
    sie_ptr: pkt_size_t;

    fifo: byte_string(0 to fifo_depth_c-1);
    fifo_fillness: integer range 0 to fifo_depth_c;

    stream_pkt: packet_index;
    stream_ptr: pkt_size_t;
    stream_take: boolean;
    stream_state: stream_state_t;
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

    -- Precomputation of MPS limit
    -- MPS is a power of two, mask will take MSBs.
    if hs_supported_c and transaction_i.hs = '1' then
      rin.mps_m1 <= to_unsigned(BULK_MPS_HS - 1, rin.mps_m1'length);
      rin.mps <= to_unsigned(BULK_MPS_HS, rin.mps_m1'length);
    else
      rin.mps_m1 <= to_unsigned(2 ** fs_mps_l2_c - 1, rin.mps_m1'length);
      rin.mps <= to_unsigned(2 ** fs_mps_l2_c, rin.mps_m1'length);
    end if;

    case r.sie_state is
      when SIE_RESET =>
        rin.sie_state <= SIE_IDLE;
        rin.sie_packet_no <= '0';
        rin.sie_pkt <= 0;
        rin.halted <= false;

      when SIE_IDLE =>
        rin.sie_ptr <= (others => '0');

        if not r.halted then
          case transaction_i.phase is
            when PHASE_NONE =>
              null;

            when PHASE_TOKEN =>
              if not r.pkt(r.sie_pkt).valid then
                rin.sie_state <= SIE_TAKE;
              else
                rin.sie_state <= SIE_IGNORE_NAK;
              end if;

            when PHASE_DATA =>
              -- We didn't catch the start ?
              rin.sie_state <= SIE_IGNORE_NAK;

            when PHASE_HANDSHAKE =>
              if hs_supported_c and transaction_i.hs = '1'
                and transaction_i.transaction = TRANSACTION_PING then
                if not r.pkt(r.sie_pkt).valid then
                  rin.sie_state <= SIE_ACK;
                else
                  rin.sie_state <= SIE_NAK;
                end if;
              else
                -- We didn't catch the start ?
                rin.sie_state <= SIE_NAK;
              end if;
          end case;
        end if;

      when SIE_TAKE =>
        case transaction_i.phase is
          when PHASE_NONE =>
            rin.sie_state <= SIE_IDLE;

          when PHASE_TOKEN =>
            -- wait
            null;

          when PHASE_DATA =>
            if transaction_i.toggle /= r.sie_packet_no then
              -- Already got it
              rin.sie_state <= SIE_IGNORE_ACK;
            elsif transaction_i.nxt = '1' then
              rin.sie_ptr <= r.sie_ptr + 1;

              if r.sie_ptr = r.mps then
                -- This should not happen, this is an overflow
                rin.sie_state <= SIE_IGNORE_NAK;
              end if;
            end if;

          when PHASE_HANDSHAKE =>
            -- Commits the OUT
            rin.sie_packet_no <= not r.sie_packet_no;
            rin.sie_state <= SIE_ACK;
            rin.sie_pkt <= packet_next(r.sie_pkt);
            rin.pkt(r.sie_pkt).length <= r.sie_ptr;
            rin.pkt(r.sie_pkt).valid <= true;
        end case;

      when SIE_IGNORE_ACK =>
        if transaction_i.phase = PHASE_HANDSHAKE then
          rin.sie_state <= SIE_ACK;
        end if;

      when SIE_IGNORE_NAK =>
        if transaction_i.phase = PHASE_HANDSHAKE then
          rin.sie_state <= SIE_NAK;
        end if;

      when SIE_ACK | SIE_NAK =>
        if transaction_i.phase = PHASE_NONE then
          rin.sie_state <= SIE_IDLE;
        end if;
    end case;

    case r.stream_state is
      when STREAM_RESET =>
        rin.stream_state <= STREAM_IDLE;
        rin.stream_take <= false;

      when STREAM_IDLE =>
        rin.stream_ptr <= (others => '0');
        rin.stream_take <= false;
        if r.pkt(r.stream_pkt).valid and not r.halted then
          if r.pkt(r.stream_pkt).length = 0 then
            rin.stream_state <= STREAM_SHORT_COMMIT;
          else
            rin.stream_state <= STREAM_FILL;
          end if;
        end if;

      when STREAM_FILL =>
        rin.stream_take <= true;
        rin.stream_ptr <= r.stream_ptr + 1;
        if r.pkt(r.stream_pkt).length <= r.mps_m1 then
          rin.stream_state <= STREAM_SHORT;
        else
          rin.stream_state <= STREAM_FULL;
        end if;

      when STREAM_FULL | STREAM_SHORT =>
        rin.stream_take <= false;
        fifo_push := r.stream_take;

        if r.fifo_fillness >= 2 and framed_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.fifo_fillness <= fifo_depth_c - 2
          and r.stream_ptr <= r.pkt(r.stream_pkt).length then
          rin.stream_take <= true;
          rin.stream_ptr <= r.stream_ptr + 1;
        end if;

        if r.stream_ptr = r.pkt(r.stream_pkt).length then
          rin.pkt(r.stream_pkt).valid <= false;
          rin.stream_pkt <= packet_next(r.stream_pkt);
          if r.stream_state = STREAM_FULL then
            rin.stream_state <= STREAM_IDLE;
          else
            rin.stream_state <= STREAM_SHORT_COMMIT;
          end if;
        end if;

      when STREAM_SHORT_COMMIT =>
        if r.fifo_fillness >= 1 and framed_i.ready = '1' then
          fifo_pop := true;
        end if;

        if r.fifo_fillness = 0
          or (r.fifo_fillness = 1 and framed_i.ready = '1') then
          rin.stream_state <= STREAM_IDLE;
        end if;
    end case;

    if transaction_i.clear = '1' then
      rin.halted <= false;
      rin.sie_packet_no <= '0';
      rin.sie_pkt <= 0;
      rin.stream_pkt <= 0;

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

  moore: process(r, transaction_i) is
  begin
    transaction_o <= TRANSACTION_RSP_IDLE;

    ram_wen_s <= '0';
    ram_waddr_s <= resize(r.sie_ptr, ram_waddr_s'length);
    if double_buffer_c then
      ram_waddr_s(ram_waddr_s'left) <= to_logic(r.sie_pkt /= 0);
    end if;

    case r.sie_state is
      when SIE_RESET | SIE_IDLE =>
        transaction_o.phase <= PHASE_TOKEN;

      when SIE_TAKE =>
        transaction_o.phase <= PHASE_DATA;
        ram_wen_s <= transaction_i.nxt;

      when SIE_IGNORE_ACK | SIE_IGNORE_NAK =>
        transaction_o.phase <= PHASE_DATA;

      when SIE_ACK =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        if r.pkt(r.sie_pkt).valid then
          transaction_o.handshake <= HANDSHAKE_NYET;
        else
          transaction_o.handshake <= HANDSHAKE_ACK;
        end if;

      when SIE_NAK =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_NAK;
    end case;

    framed_o <= framed_req_idle_c;
    ram_ren_s <= '0';
    ram_raddr_s <= resize(r.stream_ptr, ram_raddr_s'length);
    if double_buffer_c then
      ram_raddr_s(ram_raddr_s'left) <= to_logic(r.stream_pkt /= 0);
    end if;

    case r.stream_state is
      when STREAM_RESET | STREAM_IDLE =>
        null;

      when STREAM_FILL =>
        ram_ren_s <= '1';

      when STREAM_FULL | STREAM_SHORT =>
        framed_o <= framed_flit(r.fifo(0), last => false, valid => r.fifo_fillness > 1);
        ram_ren_s <= '1';
        
      when STREAM_SHORT_COMMIT =>
        framed_o <= framed_flit(r.fifo(0), last => r.fifo_fillness = 1, valid => r.fifo_fillness > 0);
    end case;
  end process;

  ram_wdata_s <= transaction_i.data;
  
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

end architecture;
