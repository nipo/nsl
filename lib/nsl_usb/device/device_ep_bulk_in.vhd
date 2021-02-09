library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_memory, nsl_logic, nsl_math;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.to_logic;
use nsl_logic.bool.if_else;

entity device_ep_bulk_in is
  generic (
    hs_supported_c : boolean;
    fs_mps_l2_c : integer range 3 to 6 := 6;
    mps_count_l2_c : integer := 1
    );
  port (
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    transfer_i : in  transfer_cmd;
    transfer_o : out transfer_rsp;

    valid_i : in  std_ulogic;
    data_i  : in  byte;
    ready_o : out std_ulogic;
    room_o  : out unsigned(if_else(hs_supported_c, 9, fs_mps_l2_c) + mps_count_l2_c downto 0);

    flush_i : in std_ulogic
    );

end entity;

architecture beh of device_ep_bulk_in is

  constant mps_l2_c : integer := if_else(hs_supported_c, 9, fs_mps_l2_c);
  subtype ptr_t is unsigned(mps_l2_c + mps_count_l2_c downto 0);
  subtype mem_ptr_t is unsigned(mps_l2_c + mps_count_l2_c - 1 downto 0);

  function to_ptr(i: integer) return ptr_t is
  begin
    return to_unsigned(i, ptr_t'length);
  end function;

  constant buffer_size_c : ptr_t := to_ptr(2 ** (mps_l2_c + mps_count_l2_c));
  constant mps_max_c : integer := 2 ** mps_l2_c;

  type state_t is (
    ST_IDLE,
    ST_STALL,
    ST_NAK,
    ST_ZLP_START,
    ST_FILL,
    ST_SEND,
    ST_HANDSHAKE
    );
  
  type regs_t is
  record
    state : state_t;

    fifo_wptr,
      fifo_rptr,
      transfer_rptr,
      transfer_end_ptr : ptr_t;

    flush          : boolean;
    last_was_short : boolean;
    last_was_acked : boolean;
    toggle         : std_ulogic;
    halted         : boolean;
  end record;

  signal s_rdata : byte;
  signal s_do_read, s_do_write, s_full_n  : std_ulogic;
  
  signal r, rin : regs_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state              <= ST_IDLE;
      r.fifo_rptr          <= (others => '0');
      r.transfer_rptr      <= (others => '0');
      r.fifo_wptr          <= (others => '0');

      r.last_was_short <= true;
      r.last_was_acked <= true;

      r.toggle <= '0';
      r.halted <= false;

      r.flush <= false;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, transfer_i, valid_i, data_i, flush_i, s_full_n) is
    variable max_txsize : ptr_t;
    variable empty : boolean;
  begin
    rin <= r;
    empty := r.fifo_rptr = r.fifo_wptr;

    if hs_supported_c and transfer_i.hs = '1' then
      max_txsize := to_ptr(BULK_MPS_HS);
    else
      max_txsize := to_ptr(2 ** fs_mps_l2_c);
    end if;

    if flush_i = '1' then
      rin.flush <= true;
    end if;
    
    case r.state is
      when ST_IDLE =>
        rin.transfer_rptr <= r.fifo_rptr;

        if not r.halted and transfer_i.phase /= PHASE_NONE then
          rin.last_was_short <= true;
          if empty then
            if r.flush or not r.last_was_short or not r.last_was_acked then
              rin.state <= ST_ZLP_START;
            else
              rin.state  <= ST_NAK;
            end if;
          elsif not r.last_was_acked and r.fifo_rptr = r.transfer_end_ptr then
            -- (8.6.4 p. 234)
            -- The data transmitter must guarantee that any retried
            -- data packet is identical (same length and content)
            rin.state <= ST_ZLP_START;
          else
            if r.last_was_acked then
              rin.transfer_end_ptr <= r.fifo_rptr + max_txsize;
            end if;
            rin.state <= ST_FILL;
          end if;
        end if;

      when ST_STALL | ST_NAK =>
        if transfer_i.phase = PHASE_NONE then
          rin.state <= ST_IDLE;
        end if;

      when ST_FILL =>
        rin.last_was_acked <= false;
        rin.state <= ST_SEND;
        rin.transfer_rptr <= r.transfer_rptr + 1;
        rin.last_was_short <= false;

      when ST_ZLP_START =>
        rin.last_was_acked <= false;
        rin.state <= ST_HANDSHAKE;

      when ST_SEND =>
        case transfer_i.phase is
          when PHASE_NONE =>
            rin.state <= ST_IDLE;

          when PHASE_TOKEN =>
            -- Wait
            null;

          when PHASE_DATA =>
            if transfer_i.nxt = '1' then
              if r.transfer_rptr = r.fifo_wptr or r.transfer_rptr = r.transfer_end_ptr then
                rin.state <= ST_HANDSHAKE;
              else
                rin.transfer_rptr <= r.transfer_rptr + 1;
              end if;
            end if;

          when PHASE_HANDSHAKE =>
            -- Early termination ? Is this even possible ?
            rin.state <= ST_HANDSHAKE;
        end case;

      when ST_HANDSHAKE =>
        rin.transfer_end_ptr <= r.transfer_rptr;
        rin.last_was_short <= r.transfer_rptr /= r.fifo_rptr + max_txsize;

        case transfer_i.phase is
          when PHASE_HANDSHAKE =>
            case transfer_i.handshake is
              when HANDSHAKE_ACK =>
                rin.last_was_acked <= true;
                rin.fifo_rptr <= r.transfer_rptr;
                rin.toggle <= not r.toggle;
                rin.state <= ST_IDLE;
                if r.last_was_short then
                  rin.flush <= false;
                end if;

              when HANDSHAKE_NAK =>
                rin.state <= ST_IDLE;

              when others =>
                null;
            end case;

          when PHASE_TOKEN | PHASE_DATA =>
            null;

          when others =>
            rin.state <= ST_IDLE;
        end case;
    end case;

    if transfer_i.clear = '1' then
      rin.halted <= false;
      rin.toggle <= '0';
    elsif transfer_i.halt = '1' then
      rin.halted <= true;
    end if;

    if s_full_n = '1' and valid_i = '1' then
      rin.fifo_wptr <= r.fifo_wptr + 1;
    end if;
  end process;

  s_full_n <= to_logic(r.fifo_wptr /= r.fifo_rptr + buffer_size_c);
  s_do_read <= (to_logic(r.state = ST_SEND and transfer_i.phase = PHASE_DATA) and transfer_i.nxt) or to_logic(r.state = ST_FILL);
  s_do_write <= valid_i and s_full_n;

  storage: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => mem_ptr_t'length,
      data_size_c => 8,
      clock_count_c => 1,
      registered_output_c => false
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => r.fifo_wptr(mem_ptr_t'range),
      write_en_i => s_do_write,
      write_data_i => data_i,

      read_address_i => r.transfer_rptr(mem_ptr_t'range),
      read_en_i => s_do_read,
      read_data_o => s_rdata
      );

  ready_o <= s_full_n;
  room_o <= r.fifo_rptr + buffer_size_c - r.fifo_wptr;

  moore: process(r, s_rdata) is
  begin
    transfer_o <= TRANSFER_RSP_IDLE;

    transfer_o.toggle  <= r.toggle;
    transfer_o.data <= s_rdata;
    transfer_o.last <= to_logic(r.transfer_rptr = r.fifo_wptr
                          or r.transfer_rptr = r.transfer_end_ptr);

    case r.state is
      when ST_IDLE | ST_FILL =>
        transfer_o.phase <= PHASE_TOKEN;
        transfer_o.handshake <= HANDSHAKE_ACK;

      when ST_STALL =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        transfer_o.handshake <= HANDSHAKE_STALL;

      when ST_NAK =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        transfer_o.handshake <= HANDSHAKE_NAK;

      when ST_ZLP_START =>
        transfer_o.phase <= PHASE_TOKEN;
        transfer_o.handshake <= HANDSHAKE_ACK;

      when ST_SEND =>
        transfer_o.phase <= PHASE_DATA;
        transfer_o.handshake <= HANDSHAKE_ACK;

      when ST_HANDSHAKE =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        transfer_o.handshake <= HANDSHAKE_ACK;
    end case;

    transfer_o.halted <= to_logic(r.halted);
    if r.halted then
      transfer_o.phase <= PHASE_HANDSHAKE;
      transfer_o.handshake <= HANDSHAKE_STALL;
    end if;
  end process;

end architecture;
