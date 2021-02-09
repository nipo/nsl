library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_memory, nsl_logic, nsl_math;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.to_logic;

-- Zero-length interrupt endpoint do exist. They provide binary interrupt
-- information through ZLP/NAK difference.

entity device_ep_intr_in is
  port (
    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    transfer_i : in  transfer_cmd;
    transfer_o : out transfer_rsp;

    valid_i   : in  std_ulogic;
    ready_o   : out std_ulogic;
    data_i    : in  byte_string;
    pending_o : out std_ulogic
    );
begin

  assert data_i'length <= 64
    report "Interrupt endpoint over 64 bytes is unsupported"
    severity failure;

end entity;

architecture beh of device_ep_intr_in is

  constant packet_size_c : integer := data_i'length;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_NAK,
    ST_SEND,
    ST_HANDSHAKE
    );

  subtype ptr_t is integer range 0 to packet_size_c-1;
  
  type regs_t is
  record
    state   : state_t;
    ptr     : ptr_t;
    toggle  : std_ulogic;
    pending : boolean;
    halted  : boolean;
    data    : byte_string(0 to packet_size_c - 1);
  end record;

  signal r, rin : regs_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state  <= ST_RESET;
      r.toggle <= '0';
      r.halted <= false;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, transfer_i, valid_i, data_i) is
  begin
    rin <= r;
    
    case r.state is
      when ST_RESET =>
        rin.pending <= false;
        rin.halted <= false;
        rin.toggle <= '0';
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if valid_i = '1' then
          rin.pending <= true;
          rin.data <= data_i;
        end if;

        if not r.halted and transfer_i.phase /= PHASE_NONE then
          if not r.pending then
            rin.state  <= ST_NAK;
          else
            rin.state <= ST_SEND;
            rin.ptr <= 0;
          end if;
        end if;

      when ST_NAK =>
        if transfer_i.phase = PHASE_NONE then
          rin.state <= ST_IDLE;
        end if;

      when ST_SEND =>
        if packet_size_c /= 0 then
          case transfer_i.phase is
            when PHASE_NONE =>
              rin.state <= ST_IDLE;

            when PHASE_TOKEN =>
              -- Wait
              null;

            when PHASE_DATA =>
              if transfer_i.nxt = '1' then
                if r.ptr = packet_size_c-1 then
                  rin.state <= ST_HANDSHAKE;
                else
                  rin.ptr <= r.ptr + 1;
                end if;
              end if;

            when PHASE_HANDSHAKE =>
              -- Early termination ? Is this even possible ?
              rin.state <= ST_HANDSHAKE;
          end case;
        else
          -- Zero-length interrupt endpoint
          case transfer_i.phase is
            when PHASE_NONE =>
              rin.state <= ST_IDLE;

            when PHASE_TOKEN | PHASE_DATA =>
              -- Wait
              null;

            when PHASE_HANDSHAKE =>
              rin.state <= ST_HANDSHAKE;
          end case;
        end if;

      when ST_HANDSHAKE =>
        case transfer_i.phase is
          when PHASE_HANDSHAKE =>
            case transfer_i.handshake is
              when HANDSHAKE_ACK =>
                rin.pending <= false;
                rin.toggle <= not r.toggle;

              when HANDSHAKE_NAK =>
                rin.state <= ST_IDLE;

              when others =>
                null;
            end case;

          when PHASE_TOKEN =>
            null;

          when others =>
            rin.state <= ST_IDLE;
        end case;
    end case;
  end process;

  pending_o <= to_logic(r.pending);

  moore: process(r) is
  begin
    ready_o <= '0';
    transfer_o <= TRANSFER_RSP_IDLE;

    transfer_o.toggle  <= r.toggle;
    transfer_o.data <= r.data(r.ptr);
    transfer_o.last <= to_logic(r.ptr = packet_size_c-1);

    case r.state is
      when ST_IDLE =>
        transfer_o.phase <= PHASE_TOKEN;
        transfer_o.handshake <= HANDSHAKE_ACK;
        ready_o <= '1';

      when ST_NAK | ST_RESET =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        transfer_o.handshake <= HANDSHAKE_NAK;

      when ST_SEND =>
        if packet_size_c /= 0 then
          transfer_o.phase <= PHASE_DATA;
        else
          transfer_o.phase <= PHASE_HANDSHAKE;
        end if;
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
