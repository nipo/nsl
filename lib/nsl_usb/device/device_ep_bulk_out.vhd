library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic, nsl_math, nsl_memory, nsl_bnoc;
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

    data_o      : out nsl_bnoc.pipe.pipe_req_t;
    data_i     : in  nsl_bnoc.pipe.pipe_ack_t;
    available_o : out unsigned(if_else(hs_supported_c, 9, fs_mps_l2_c) + mps_count_l2_c downto 0)
    );
end entity;

architecture beh of device_ep_bulk_out is

  constant mps_l2_c : integer := if_else(hs_supported_c, 9, fs_mps_l2_c);
  constant fifo_word_count_l2_c: integer := mps_l2_c + mps_count_l2_c;

  subtype ptr_t is unsigned(fifo_word_count_l2_c downto 0);
  constant mps_max_c : integer := 2 ** mps_l2_c;

  function to_ptr(i: integer) return ptr_t is
  begin
    return to_unsigned(i, ptr_t'length);
  end function;

  -- State machine
  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_TAKE,
    ST_IGNORE_ACK,
    ST_NAK,
    ST_TO_ACK,
    ST_TO_ACK2,
    ST_ACK
    );

  type regs_t is
  record
    state : state_t;

    transaction_left, mps_mask : ptr_t;

    toggle       : std_ulogic;
    halted       : boolean;
    can_take_mps : boolean;

    do_commit, do_rollback : std_ulogic;
  end record;

  signal r, rin : regs_t;

  signal fifo_in_data : std_ulogic_vector(7 downto 0);
  signal fifo_in_free : unsigned(fifo_word_count_l2_c downto 0);
  signal fifo_in_valid : std_ulogic;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, transaction_i, fifo_in_free) is
  begin
    rin <= r;

    rin.do_rollback <= '0';
    rin.do_commit <= '0';

    -- Precomputation of MPS limit
    -- MPS is a power of two, mask will take MSBs.
    if hs_supported_c and transaction_i.hs = '1' then
      rin.mps_mask <= not to_ptr(BULK_MPS_HS - 1);
    else
      rin.mps_mask <= not to_ptr(2 ** fs_mps_l2_c - 1);
    end if;

    rin.can_take_mps <= (r.mps_mask and fifo_in_free) /= (ptr_t'range => '0');

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.toggle <= '0';
        rin.halted <= false;

      when ST_IDLE =>
        rin.transaction_left <= (not r.mps_mask) + 1;

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
              if hs_supported_c and transaction_i.hs = '1'
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
            rin.do_rollback <= '1';
            rin.state <= ST_IDLE;

          when PHASE_TOKEN =>
            -- wait
            null;

          when PHASE_DATA =>
            if transaction_i.toggle /= r.toggle then
              -- Already got it
              rin.state <= ST_IGNORE_ACK;

            elsif transaction_i.nxt = '1' then
              rin.transaction_left <= r.transaction_left - 1;

              if r.transaction_left = 0 then
                -- Next cycle is an overflow, avoid this
                rin.state <= ST_NAK;
              end if;
            end if;

          when PHASE_HANDSHAKE =>
            -- Commits the OUT
            rin.toggle <= not r.toggle;
            rin.do_commit <= '1';
            rin.state <= ST_TO_ACK;
        end case;

      when ST_TO_ACK =>
        rin.state <= ST_TO_ACK2;

      when ST_TO_ACK2 =>
        rin.state <= ST_ACK;
        
      when ST_NAK | ST_ACK =>
        if transaction_i.phase = PHASE_NONE then
          rin.do_rollback <= '1';
          rin.state <= ST_IDLE;
        end if;

      when ST_IGNORE_ACK =>
        if transaction_i.phase = PHASE_HANDSHAKE then
          rin.state <= ST_ACK;
        end if;
    end case;

    if transaction_i.clear = '1' then
      rin.halted <= false;
      rin.toggle <= '0';
    elsif transaction_i.halt = '1' then
      rin.halted <= true;
    end if;
  end process;

  fifo_in_valid <= to_logic(transaction_i.phase = PHASE_DATA
                            and r.state = ST_TAKE
                            and transaction_i.nxt = '1');
  fifo_in_data <= transaction_i.data;

  fifo: nsl_memory.fifo.fifo_cancellable
    generic map(
      word_count_l2_c => fifo_word_count_l2_c,
      data_width_c => 8
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      out_data_o      => data_o.data,
      out_ready_i     => data_i.ready,
      out_valid_o     => data_o.valid,
      out_available_o => available_o,

      in_data_i       => fifo_in_data,
      in_valid_i      => fifo_in_valid,
      in_commit_i     => r.do_commit,
      in_rollback_i   => r.do_rollback,
      in_free_o       => fifo_in_free
      );

  moore: process(r) is
  begin
    transaction_o <= TRANSACTION_RSP_IDLE;

    case r.state is
      when ST_RESET | ST_IDLE =>
        transaction_o.phase <= PHASE_TOKEN;

      when ST_TAKE | ST_IGNORE_ACK | ST_TO_ACK | ST_TO_ACK2 =>
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

end architecture;
