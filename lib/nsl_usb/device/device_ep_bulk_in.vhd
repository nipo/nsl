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

    transaction_i : in  transaction_cmd;
    transaction_o : out transaction_rsp;

    valid_i : in  std_ulogic;
    data_i  : in  byte;
    ready_o : out std_ulogic;
    room_o  : out unsigned(if_else(hs_supported_c, 9, fs_mps_l2_c) + mps_count_l2_c downto 0);

    flush_i : in std_ulogic
    );

end entity;

architecture beh of device_ep_bulk_in is

  constant mps_l2_c : integer := if_else(hs_supported_c, 9, fs_mps_l2_c);
  constant fifo_word_count_l2_c: integer := mps_l2_c + mps_count_l2_c;

  subtype ptr_t is unsigned(fifo_word_count_l2_c downto 0);
  constant mps_max_c : integer := 2 ** mps_l2_c;

  function to_ptr(i: integer) return ptr_t is
  begin
    return to_unsigned(i, ptr_t'length);
  end function;

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

    transaction_left, last_size, mps_mask : ptr_t;

    flush          : boolean;
    last_was_short : boolean;
    last_was_acked : boolean;
    toggle         : std_ulogic;
    halted         : boolean;

    do_commit, do_rollback : std_ulogic;
    tx_buffer : std_ulogic_vector(7 downto 0);
  end record;

  signal r, rin : regs_t;

  signal fifo_out_data : std_ulogic_vector(7 downto 0);
  signal fifo_out_available : unsigned(fifo_word_count_l2_c downto 0);
  signal fifo_out_valid, fifo_out_ready : std_ulogic;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state              <= ST_IDLE;
      r.transaction_left   <= to_ptr(0);
      r.last_size          <= to_ptr(0);

      r.last_was_short <= true;
      r.last_was_acked <= true;

      r.toggle <= '0';
      r.halted <= false;

      r.flush <= false;
    end if;
  end process;

  transition: process(r, transaction_i, flush_i,
                      fifo_out_available, fifo_out_valid, fifo_out_data) is
    variable max_txsize : ptr_t;
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

    if flush_i = '1' then
      rin.flush <= true;
    end if;

    case r.state is
      when ST_IDLE =>
        if not r.halted and transaction_i.phase /= PHASE_NONE then
          rin.last_was_short <= true;
          if fifo_out_valid = '0' then
            if r.flush or not r.last_was_short or not r.last_was_acked then
              rin.state <= ST_ZLP_START;
            else
              rin.state  <= ST_NAK;
            end if;
          elsif not r.last_was_acked and r.last_size = 0 then
            -- (8.6.4 p. 234)
            -- The data transmitter must guarantee that any retried
            -- data packet is identical (same length and content)
            rin.state <= ST_ZLP_START;
          else
            if r.last_was_acked then
              rin.transaction_left <= (not r.mps_mask);
            else
              rin.transaction_left <= r.last_size - 1;
            end if;
            rin.state <= ST_FILL;
            rin.last_was_acked <= false;
            rin.last_size <= to_ptr(0);
            rin.last_was_short <= false;
          end if;
        end if;

      when ST_STALL | ST_NAK =>
        if transaction_i.phase = PHASE_NONE then
          rin.do_rollback <= '1';
          rin.state <= ST_IDLE;
        end if;

      when ST_ZLP_START =>
        rin.last_was_acked <= false;
        rin.last_size <= to_ptr(0);
        rin.state <= ST_HANDSHAKE;

      when ST_FILL =>
        rin.tx_buffer <= fifo_out_data;
        rin.state <= ST_SEND;

      when ST_SEND =>
        case transaction_i.phase is
          when PHASE_NONE =>
            rin.do_rollback <= '1';
            rin.state <= ST_IDLE;

          when PHASE_TOKEN =>
            -- Wait
            null;

          when PHASE_DATA =>
            if transaction_i.nxt = '1' then
              rin.tx_buffer <= fifo_out_data;
              rin.last_size <= r.last_size + 1;
              rin.transaction_left <= r.transaction_left - 1;

              if r.transaction_left = 0 or fifo_out_valid = '0' then
                rin.state <= ST_HANDSHAKE;
              end if;
            end if;

          when PHASE_HANDSHAKE =>
            -- Early termination ? Is this even possible ?
            rin.state <= ST_HANDSHAKE;
        end case;

      when ST_HANDSHAKE =>
        rin.last_was_short <= (r.last_size and r.mps_mask) = to_ptr(0);

        case transaction_i.phase is
          when PHASE_HANDSHAKE =>
            case transaction_i.handshake is
              when HANDSHAKE_ACK =>
                rin.last_was_acked <= true;
                rin.do_commit <= '1';
                rin.toggle <= not r.toggle;
                rin.state <= ST_IDLE;
                if r.last_was_short then
                  rin.flush <= false;
                end if;

              when HANDSHAKE_NAK =>
                rin.do_rollback <= '1';
                rin.state <= ST_IDLE;

              when others =>
                null;
            end case;

          when PHASE_DATA =>
            null;

          when others =>
            rin.do_rollback <= '1';
            rin.state <= ST_IDLE;
        end case;
    end case;

    if transaction_i.clear = '1' then
      rin.halted <= false;
      rin.toggle <= '0';
    elsif transaction_i.halt = '1' then
      rin.halted <= true;
    end if;
  end process;

  fifo: nsl_memory.fifo.fifo_cancellable
    generic map(
      word_count_l2_c => fifo_word_count_l2_c,
      data_width_c => 8
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      out_data_o      => fifo_out_data,
      out_valid_o     => fifo_out_valid,
      out_ready_i     => fifo_out_ready,
      out_commit_i     => r.do_commit,
      out_rollback_i   => r.do_rollback,
      out_available_o => fifo_out_available,

      in_data_i       => data_i,
      in_valid_i      => valid_i,
      in_ready_o      => ready_o,
      in_free_o       => room_o
      );

  fifo_out_ready <= to_logic(r.state = ST_FILL)
                    or to_logic(r.state = ST_SEND
                                and transaction_i.phase = PHASE_DATA
                                and transaction_i.nxt = '1'
                                and r.transaction_left /= 0);

  moore: process(r, fifo_out_valid) is
  begin
    transaction_o <= TRANSACTION_RSP_IDLE;

    transaction_o.toggle  <= r.toggle;
    transaction_o.last <= to_logic(r.transaction_left = 0 or fifo_out_valid = '0');
    transaction_o.data <= r.tx_buffer;

    case r.state is
      when ST_IDLE | ST_FILL =>
        transaction_o.phase <= PHASE_TOKEN;
        transaction_o.handshake <= HANDSHAKE_ACK;

      when ST_STALL =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_STALL;

      when ST_NAK =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_NAK;

      when ST_ZLP_START =>
        transaction_o.phase <= PHASE_TOKEN;
        transaction_o.handshake <= HANDSHAKE_ACK;

      when ST_SEND =>
        transaction_o.phase <= PHASE_DATA;
        transaction_o.handshake <= HANDSHAKE_ACK;

      when ST_HANDSHAKE =>
        transaction_o.phase <= PHASE_HANDSHAKE;
        transaction_o.handshake <= HANDSHAKE_ACK;
    end case;

    transaction_o.halted <= to_logic(r.halted);
    if r.halted then
      transaction_o.phase <= PHASE_HANDSHAKE;
      transaction_o.handshake <= HANDSHAKE_STALL;
    end if;
  end process;

end architecture;
