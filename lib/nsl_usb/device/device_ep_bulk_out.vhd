library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic, nsl_math, nsl_memory;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.device.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity device_ep_bulk_out is
  generic (
    hs_supported_c : boolean;
    fs_mps_l2_c : integer range 3 to 6 := 6;
    mps_count_l2_c : integer := 1
    );
  port (
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    transaction_i : in  transaction_cmd;
    transaction_o : out transaction_rsp;

    valid_o     : out std_ulogic;
    data_o      : out byte;
    ready_i     : in  std_ulogic;
    available_o : out unsigned(if_else(hs_supported_c, 9, fs_mps_l2_c) + mps_count_l2_c downto 0)
    );
end entity;

architecture beh of device_ep_bulk_out is

  constant mps_l2_c : integer := if_else(hs_supported_c, 9, fs_mps_l2_c);
  subtype ptr_t is unsigned(mps_l2_c + mps_count_l2_c downto 0);
  subtype mem_ptr_t is unsigned(mps_l2_c + mps_count_l2_c - 1 downto 0);

  function to_ptr(i: integer) return ptr_t is
  begin
    return to_unsigned(i, ptr_t'length);
  end function;

  constant buffer_size_c : ptr_t := to_ptr(2 ** (mps_l2_c + mps_count_l2_c));
  constant mps_max_c : integer := 2 ** mps_l2_c;

  -- State machine
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_TAKE,
    ST_IGNORE_ACK,
    ST_NAK,
    ST_ACK
    );
  
  type regs_t is
  record
    state : state_t;

    fifo_wptr,
      fifo_rptr,
      transaction_offset,
      mps_mask : ptr_t;

    toggle              : std_ulogic;
    halted              : boolean;
    read_buffer_valid : std_ulogic;
    can_take_mps : boolean;

    available : unsigned(available_o'range);
  end record;

  signal s_do_write, s_do_read : std_ulogic;
  signal r, rin : regs_t;

  signal s_mem_woff : ptr_t;
  signal s_mem_wptr : mem_ptr_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  s_do_read <= (ready_i or not r.read_buffer_valid)
            and to_logic(r.fifo_rptr /= r.fifo_wptr);
  s_do_write <= to_logic(transaction_i.phase = PHASE_DATA and r.state = ST_TAKE)
                and transaction_i.nxt;

  transition: process(transaction_i, r, ready_i, s_do_read) is
    variable free_size : ptr_t;
  begin
    rin <= r;

    free_size := buffer_size_c + r.fifo_rptr - r.fifo_wptr - r.transaction_offset;
    rin.can_take_mps <= (r.mps_mask and free_size) /= (ptr_t'range => '0');

    rin.available <= r.fifo_wptr - r.fifo_rptr;

    -- Precomputation of MPS limit
    -- MPS is a power of two, mask will take MSBs.
    if hs_supported_c and transaction_i.hs = '1' then
      rin.mps_mask <= not to_ptr(BULK_MPS_HS - 1);
    else
      rin.mps_mask <= not to_ptr(2 ** fs_mps_l2_c - 1);
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.fifo_rptr          <= to_ptr(0);
        rin.fifo_wptr          <= to_ptr(0);
        rin.toggle             <= '0';
        rin.halted             <= false;
        rin.read_buffer_valid  <= '0';
        
      when ST_IDLE =>
        rin.transaction_offset <= to_ptr(0);

        if not r.halted then
          case transaction_i.phase is
            when PHASE_NONE =>
              null;

            when PHASE_TOKEN =>
              if r.can_take_mps then
                rin.state <= ST_TAKE;
              else
                rin.state <= ST_NAK;
              end if;

            when PHASE_DATA =>
              -- We didn't catch the start ?
              rin.state <= ST_NAK;

            when PHASE_HANDSHAKE =>
              if hs_supported_c
                and transaction_i.hs = '1'
                and transaction_i.transaction = TRANSACTION_PING then
                if r.can_take_mps then
                  rin.state <= ST_ACK;
                else
                  rin.state <= ST_NAK;
                end if;
              else
                -- We didn't catch the start ?
                rin.state <= ST_NAK;
              end if;
          end case;
        end if;

      when ST_TAKE =>
        case transaction_i.phase is
          when PHASE_NONE =>
            rin.state <= ST_IDLE;

          when PHASE_TOKEN =>
            -- wait
            null;

          when PHASE_DATA =>
            if transaction_i.toggle /= r.toggle then
              -- Already got it
              rin.state <= ST_IGNORE_ACK;

            elsif transaction_i.nxt = '1' then
              rin.transaction_offset <= r.transaction_offset + 1;

              if (r.transaction_offset and r.mps_mask) /= 0 then
                -- Next cycle is an overflow, avoid this
                rin.state <= ST_NAK;
              end if;
            end if;

          when PHASE_HANDSHAKE =>
            -- Commits the OUT
            rin.toggle <= not r.toggle;
            rin.state <= ST_ACK;
            rin.fifo_wptr <= r.fifo_wptr + r.transaction_offset;
        end case;

      when ST_NAK =>
        if transaction_i.phase = PHASE_NONE then
          rin.state <= ST_IDLE;
        end if;

      when ST_IGNORE_ACK =>
        if transaction_i.phase = PHASE_HANDSHAKE then
          rin.state <= ST_ACK;
        end if;

      when ST_ACK =>
        if transaction_i.phase = PHASE_NONE then
          rin.state <= ST_IDLE;
        end if;
    end case;

    if transaction_i.clear = '1' then
      rin.halted <= false;
      rin.toggle <= '0';
    elsif transaction_i.halt = '1' then
      rin.halted <= true;
    end if;

    rin.read_buffer_valid <= (not ready_i and r.read_buffer_valid) or s_do_read;
    if r.fifo_wptr /= r.fifo_rptr and ready_i = '1' then
      rin.fifo_rptr <= r.fifo_rptr + 1;
    end if;
  end process;

  s_mem_woff <= r.transaction_offset and not r.mps_mask;
  s_mem_wptr <= resize(r.fifo_wptr + s_mem_woff, s_mem_wptr'length);
  
  storage: nsl_memory.ram.ram_2p_r_w
    generic map(
      addr_size_c => mem_ptr_t'length,
      data_size_c => 8,
      clock_count_c => 1,
      registered_output_c => false
      )
    port map(
      clock_i(0) => clock_i,

      write_address_i => s_mem_wptr,
      write_en_i => s_do_write,
      write_data_i => transaction_i.data,

      read_address_i => r.fifo_rptr(mem_ptr_t'range),
      read_en_i => s_do_read,
      read_data_o => data_o
      );

  moore: process(r) is
  begin
    transaction_o <= TRANSACTION_RSP_IDLE;

    case r.state is
      when ST_RESET | ST_IDLE =>
        transaction_o.phase <= PHASE_TOKEN;

      when ST_TAKE | ST_IGNORE_ACK =>
        transaction_o.phase <= PHASE_DATA;

      when ST_ACK =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        if r.can_take_mps then
          transaction_o.handshake <= HANDSHAKE_ACK;
        else
          transaction_o.handshake <= HANDSHAKE_NYET;
        end if;

      when ST_NAK =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_NAK;
    end case;

    transaction_o.halted <= to_logic(r.halted);
    if r.halted then
      transaction_o.phase <= PHASE_HANDSHAKE;
      transaction_o.handshake <= HANDSHAKE_STALL;
    end if;
  end process;
    
  available_o <= r.available;
  valid_o <= r.read_buffer_valid;

end architecture;
