library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.utmi.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity sie_transaction is
  generic (
    hs_supported_c : boolean := false;
    phy_clock_rate_c : integer := 60000000
    );
  port (
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;

    frame_number_o : out frame_no_t;
    frame_o        : out std_ulogic;

    hs_i        : in  std_ulogic;
    dev_addr_i  : in  device_address_t;

    packet_out_i  : in  packet_out;
    packet_in_o   : out packet_in_cmd;
    packet_in_i   : in  packet_in_rsp;

    transaction_o : out transaction_cmd;
    transaction_i : in  transaction_rsp
    );
end entity sie_transaction;

architecture beh of sie_transaction is

  type state_t is (
    ST_RESET,

    ST_TOKEN_WAIT_PID,
    ST_TOKEN_WAIT_1,
    ST_TOKEN_WAIT_2,
    ST_TOKEN_WAIT_COMMIT,
    ST_TOKEN_ROUTE,

    ST_SETUP_DATA_WAIT_PID,
    ST_SETUP_DATA_FORWARD,
    ST_SETUP_HANDSHAKE_WAIT_APP,
    ST_SETUP_HANDSHAKE_WAIT_TX,

    ST_OUT_DATA_WAIT_PID,
    ST_OUT_DATA_FORWARD,
    ST_OUT_HANDSHAKE_WAIT_APP,
    ST_OUT_HANDSHAKE_WAIT_TX,

    ST_PING_HANDSHAKE_WAIT_APP,
    ST_PING_HANDSHAKE_WAIT_TX,

    ST_IN_DATA_WAIT_APP,
    ST_IN_DATA_SEND_ZLP,
    ST_IN_DATA_BUFFER_FILL,
    ST_IN_DATA_SEND_PID,
    ST_IN_DATA_FORWARD,
    ST_IN_HANDSHAKE_WAIT_PID,
    ST_IN_HANDSHAKE_TELL_APP,
    ST_IN_HANDSHAKE_WAIT_TX,

    ST_IGNORE
    );

  function t_cycles(s : real) return integer
  is
  begin
    return integer(s * real(phy_clock_rate_c));
  end function;

  -- USB2 7.1.19
  -- ULPI 3.8.2.6.1
--  constant host_wait_timeout_fs_c : integer := bit_count_cycles_fs(18, phy_clock_rate_c/1000000) + 20;
--  constant host_wait_timeout_hs_c : integer := bit_count_cycles_hs(816, phy_clock_rate_c/1000000) + 20;
  constant host_wait_timeout_fs_c : integer := t_cycles(6.0e-6);
  constant host_wait_timeout_hs_c : integer := t_cycles(6.0e-6);
  constant app_wait_timeout_c : integer := bit_count_cycles_hs(192, phy_clock_rate_c/1000000) - 4; -- ~400ns

  constant timeout_max_c : integer := nsl_logic.bool.if_else(
    hs_supported_c,
    host_wait_timeout_hs_c,
    host_wait_timeout_fs_c);

  subtype timeout_t is integer range 0 to timeout_max_c;

  signal host_wait_timeout_c : timeout_t;
  
  type data_buf_element is
  record
    valid, last : std_ulogic;
    data : byte;
  end record;

  type data_buf_vector is array (natural range <>) of data_buf_element;
  
  type regs_t is
  record
    state : state_t;

    hs : std_ulogic;

    pid   : pid_t;
    token : unsigned(10 downto 0); -- skip CRC

    frame_number : frame_no_t;
    frame : std_ulogic;

    handshake : handshake_t;
    
    wait_timeout : timeout_t;

    toggle : std_ulogic;
    data_buf : data_buf_vector(0 to 1);
  end record;

  signal r, rin: regs_t;
  
begin

  timeout_cst: process(r)
  begin
    if hs_supported_c and r.hs = '1' then
      host_wait_timeout_c <= host_wait_timeout_hs_c;
    else
      host_wait_timeout_c <= host_wait_timeout_fs_c;
    end if;
  end process;

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, packet_out_i, packet_in_i,
                      transaction_i, hs_i, dev_addr_i,
                      host_wait_timeout_c) is
    variable put, take : boolean;
  begin
    rin <= r;

    rin.hs <= hs_i;
    rin.frame <= '0';

    if r.wait_timeout /= 0 then
      rin.wait_timeout <= r.wait_timeout - 1;
      if r.wait_timeout = 1 then
        rin.pid <= PID_RESERVED;
        rin.state <= ST_TOKEN_WAIT_PID;
      end if;
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.pid <= PID_RESERVED;
        rin.state <= ST_TOKEN_WAIT_PID;
        rin.wait_timeout <= 0;
        
      when ST_TOKEN_WAIT_PID =>
        -- Actual handling of token PIDs is done below in a catchall
        -- condition
        if packet_out_i.active = '1' and packet_out_i.valid = '1' then
          rin.state <= ST_IGNORE;
        end if;

      when ST_TOKEN_WAIT_1 =>
        if packet_out_i.active = '0' then
          -- Short token packet
          rin.state <= ST_TOKEN_WAIT_PID;
        elsif packet_out_i.valid = '1' then
          rin.token(7 downto 0) <= unsigned(packet_out_i.data);
          rin.state <= ST_TOKEN_WAIT_2;
        end if;

      when ST_TOKEN_WAIT_2 =>
        if packet_out_i.active = '0' then
          -- Short token packet
          rin.state <= ST_TOKEN_WAIT_PID;
        elsif packet_out_i.valid = '1' then
          rin.token(10 downto 8) <= unsigned(packet_out_i.data(2 downto 0));
          rin.state <= ST_TOKEN_WAIT_COMMIT;
        end if;

      when ST_TOKEN_WAIT_COMMIT =>
        if packet_out_i.active = '0' then
          if packet_out_i.commit = '1' then
            rin.state <= ST_TOKEN_ROUTE;
          else
            rin.state <= ST_TOKEN_WAIT_PID;
          end if;
        elsif packet_out_i.valid = '1' then
          -- Long token packet
          rin.state <= ST_IGNORE;
        end if;

      when ST_TOKEN_ROUTE =>
        rin.handshake <= HANDSHAKE_SILENT;
        if r.token(6 downto 0) /= dev_addr_i then
          rin.state <= ST_TOKEN_WAIT_PID;
        else
          case r.pid is
            when PID_IN =>
              rin.state <= ST_IN_DATA_WAIT_APP;
              rin.wait_timeout <= app_wait_timeout_c;

            when PID_PING =>
              if hs_supported_c and r.hs = '1' then
                rin.state <= ST_PING_HANDSHAKE_WAIT_APP;
                rin.wait_timeout <= app_wait_timeout_c;
              end if;

            when PID_SETUP =>
              rin.state <= ST_SETUP_DATA_WAIT_PID;
              rin.wait_timeout <= host_wait_timeout_c;

            when PID_OUT =>
              rin.state <= ST_OUT_DATA_WAIT_PID;
              rin.wait_timeout <= host_wait_timeout_c;

            when PID_SOF =>
              rin.frame_number <= r.token;
              rin.frame <= '1';
              rin.state <= ST_TOKEN_WAIT_PID;
              
            when others =>
              null;
          end case;
        end if;

      when ST_IN_DATA_WAIT_APP =>
        rin.toggle <= transaction_i.toggle;
        case transaction_i.phase is
          when PHASE_NONE | PHASE_TOKEN =>
            -- App is not ready yet
            null;

          when PHASE_DATA =>
            rin.state <= ST_IN_DATA_BUFFER_FILL;
            rin.data_buf(0).valid <= '0';
            rin.data_buf(1).valid <= '0';
            rin.data_buf(0).last <= '0';
            rin.data_buf(1).last <= '0';
            rin.wait_timeout <= 0;

          when PHASE_HANDSHAKE =>
            -- IN Zlp if ACK, else error
            case transaction_i.handshake is
              when HANDSHAKE_ACK =>
                rin.state <= ST_IN_DATA_SEND_ZLP;
                rin.wait_timeout <= 0;

              when others =>
                rin.handshake <= transaction_i.handshake;
                rin.state <= ST_IN_HANDSHAKE_WAIT_TX;
                rin.wait_timeout <= 0;
            end case;
        end case;

      when ST_IN_DATA_BUFFER_FILL =>
        if r.data_buf(0).valid = '0' then
          rin.data_buf(0).data <= transaction_i.data;
          rin.data_buf(0).last <= transaction_i.last;
          rin.data_buf(0).valid <= '1';
        elsif r.data_buf(1).valid = '0' then
          rin.data_buf(1).data <= transaction_i.data;
          rin.data_buf(1).last <= transaction_i.last;
          rin.data_buf(1).valid <= '1';
          rin.state <= ST_IN_DATA_SEND_PID;
        end if;
        if transaction_i.last = '1' then
          rin.state <= ST_IN_DATA_SEND_PID;
        end if;

      when ST_IN_DATA_SEND_PID =>
        if packet_in_i.ready = '1' then
          -- DATA0/DATA1 was sent, IN buffer is full go with data
          rin.state <= ST_IN_DATA_FORWARD;
        end if;

      when ST_IN_DATA_SEND_ZLP =>
        if packet_in_i.ready = '1' then
          -- DATA0/DATA1 ZLP was sent
          rin.state <= ST_IN_HANDSHAKE_WAIT_PID;
        end if;
        
      when ST_IN_DATA_FORWARD =>
        put := r.data_buf(0).last = '0'
               and r.data_buf(1).last = '0'
               and r.data_buf(1).valid = '0';
        take := packet_in_i.ready = '1';
        if put and take then
          rin.data_buf(0).data <= transaction_i.data;
          rin.data_buf(0).last <= transaction_i.last;
          rin.data_buf(0).valid <= '1';
        elsif take then
          rin.data_buf(0) <= r.data_buf(1);
          rin.data_buf(1).valid <= '0';
          rin.data_buf(1).last <= '0';
        elsif put then
          rin.data_buf(1).data <= transaction_i.data;
          rin.data_buf(1).last <= transaction_i.last;
          rin.data_buf(1).valid <= '1';
        end if;

        if packet_in_i.ready = '1' and r.data_buf(0).last = '1' then
          rin.state <= ST_IN_HANDSHAKE_WAIT_PID;
          rin.wait_timeout <= host_wait_timeout_c;
        end if;

      when ST_IN_HANDSHAKE_WAIT_PID =>
        if packet_out_i.valid = '1' then
          case pid_get(packet_out_i.data) is
            when PID_ACK =>
              rin.state <= ST_IN_HANDSHAKE_TELL_APP;
              rin.wait_timeout <= 0;
              rin.handshake <= HANDSHAKE_ACK;

            when PID_NAK =>
              rin.state <= ST_IN_HANDSHAKE_TELL_APP;
              rin.wait_timeout <= 0;
              rin.handshake <= HANDSHAKE_NAK;

            when PID_STALL =>
              rin.state <= ST_IN_HANDSHAKE_TELL_APP;
              rin.wait_timeout <= 0;
              rin.handshake <= HANDSHAKE_STALL;

            when others =>
              -- Will be catched by generic statement below
          end case;
        end if;

      when ST_IN_HANDSHAKE_TELL_APP =>
        -- IN transaction is over
        rin.state <= ST_TOKEN_WAIT_PID;

      when ST_IN_HANDSHAKE_WAIT_TX =>
        if packet_in_i.ready = '1' then
          -- Error token was sent, transaction over
          rin.state <= ST_TOKEN_WAIT_PID;
        end if;
        
      when ST_OUT_DATA_WAIT_PID | ST_SETUP_DATA_WAIT_PID =>
        rin.data_buf(0).valid <= '0';
        if packet_out_i.valid = '1' then
          case pid_get(packet_out_i.data) is
            when PID_DATA0 | PID_DATA1 =>
              rin.pid <= pid_get(packet_out_i.data);
              if r.state = ST_SETUP_DATA_WAIT_PID then
                rin.state <= ST_SETUP_DATA_FORWARD;
              else
                rin.state <= ST_OUT_DATA_FORWARD;
              end if;
              rin.wait_timeout <= 0;

            when others =>
              -- Will be catched by generic statement below
          end case;
        end if;

      when ST_OUT_DATA_FORWARD | ST_SETUP_DATA_FORWARD =>
        rin.data_buf(0).valid <= packet_out_i.valid;
        rin.data_buf(0).data <= packet_out_i.data;
        if packet_out_i.active = '0' then
          if packet_out_i.commit = '1' then
            if r.state = ST_SETUP_DATA_FORWARD then
              rin.state <= ST_SETUP_HANDSHAKE_WAIT_APP;
            else
              rin.state <= ST_OUT_HANDSHAKE_WAIT_APP;
            end if;
            rin.wait_timeout <= app_wait_timeout_c;
          else
            -- Packet was invalid, dont even try to accept handshake
            -- from app.
            rin.handshake <= HANDSHAKE_NAK;
            if r.state = ST_SETUP_DATA_FORWARD then
              rin.state <= ST_SETUP_HANDSHAKE_WAIT_TX;
            else
              rin.state <= ST_OUT_HANDSHAKE_WAIT_TX;
            end if;
          end if;
        end if;

      when ST_OUT_HANDSHAKE_WAIT_APP | ST_SETUP_HANDSHAKE_WAIT_APP =>
        case transaction_i.phase is
          when PHASE_NONE | PHASE_TOKEN =>
            -- App cancelled response
            rin.state <= ST_TOKEN_WAIT_PID;

          when PHASE_DATA =>
            null;

          when PHASE_HANDSHAKE =>
            rin.handshake <= transaction_i.handshake;
            rin.wait_timeout <= 0;
            if r.state = ST_SETUP_HANDSHAKE_WAIT_APP then
              rin.state <= ST_SETUP_HANDSHAKE_WAIT_TX;
            else
              rin.state <= ST_OUT_HANDSHAKE_WAIT_TX;
            end if;
        end case;

      when ST_OUT_HANDSHAKE_WAIT_TX | ST_SETUP_HANDSHAKE_WAIT_TX | ST_PING_HANDSHAKE_WAIT_TX =>
        if packet_in_i.ready = '1' then
          -- OUT/SETUP/PING Transaction done
          rin.state <= ST_TOKEN_WAIT_PID;
        end if;

      when ST_PING_HANDSHAKE_WAIT_APP =>
        case transaction_i.phase is
          when PHASE_NONE =>
            -- App cancelled response
            rin.state <= ST_TOKEN_WAIT_PID;

          when PHASE_TOKEN | PHASE_DATA =>
            -- Should not happen, but this allows to use the same App
            -- state machine for OUT and PING, so, accept this.
            null;

          when PHASE_HANDSHAKE =>
            rin.handshake <= transaction_i.handshake;
            rin.wait_timeout <= 0;
            rin.state <= ST_PING_HANDSHAKE_WAIT_TX;
        end case;

      when ST_IGNORE =>
        if packet_out_i.valid = '0' then
          rin.State <= ST_TOKEN_WAIT_PID;
        end if;
    end case;

    -- For any state where app is following the transaction, we should
    -- not have a NONE phase
    case r.state is
      when ST_RESET =>
        -- Dont handle anything in reset.
        null;

      when ST_SETUP_DATA_FORWARD | ST_SETUP_HANDSHAKE_WAIT_APP
        | ST_SETUP_HANDSHAKE_WAIT_TX
        | ST_OUT_DATA_FORWARD | ST_OUT_HANDSHAKE_WAIT_APP
        | ST_OUT_HANDSHAKE_WAIT_TX
        | ST_PING_HANDSHAKE_WAIT_TX
        | ST_IN_DATA_SEND_PID | ST_IN_HANDSHAKE_WAIT_PID
        | ST_IN_HANDSHAKE_TELL_APP | ST_IN_HANDSHAKE_WAIT_TX =>
        if transaction_i.phase = PHASE_NONE then
          rin.state <= ST_TOKEN_WAIT_PID;
          rin.wait_timeout <= 0;
        end if;

      when others =>
        null;
    end case;

    -- For any state where we do not expect data from host (or
    -- actually expect a PID), we take any token PID as a cancellation
    -- of current transaction.
    case r.state is
      when ST_RESET =>
        -- Dont handle anything in reset.
        null;

      when ST_SETUP_DATA_FORWARD | ST_OUT_DATA_FORWARD | ST_TOKEN_WAIT_1
        | ST_TOKEN_WAIT_2 | ST_TOKEN_WAIT_COMMIT | ST_IGNORE =>
        -- Those states are the ones where data from host is not a
        -- PID.
        null;

      when others =>
        if packet_out_i.active = '1' and packet_out_i.valid = '1' then
          case pid_get(packet_out_i.data) is
            when PID_OUT | PID_IN | PID_SOF | PID_SETUP | PID_PING =>
              rin.pid <= pid_get(packet_out_i.data);
              rin.state <= ST_TOKEN_WAIT_1;
              rin.wait_timeout <= 0;

            when others =>
              -- Other PIDs happen when we expect them and are handled
              -- in state machine above
          end case;
        end if;
    end case;
  end process;

  packet_moore: process(r)
  begin
    packet_in_o.valid <= '0';
    packet_in_o.last <= '-';
    packet_in_o.data <= (others => '-');

    case r.state is
      when ST_SETUP_HANDSHAKE_WAIT_TX | ST_OUT_HANDSHAKE_WAIT_TX
        | ST_PING_HANDSHAKE_WAIT_TX | ST_IN_HANDSHAKE_WAIT_TX =>
        case r.handshake is
          when HANDSHAKE_ACK =>
            packet_in_o.valid <= '1';
            packet_in_o.last <= '1';
            packet_in_o.data <= pid_byte(PID_ACK);
          when HANDSHAKE_NAK =>
            packet_in_o.valid <= '1';
            packet_in_o.last <= '1';
            packet_in_o.data <= pid_byte(PID_NAK);
          when HANDSHAKE_STALL =>
            packet_in_o.valid <= '1';
            packet_in_o.last <= '1';
            packet_in_o.data <= pid_byte(PID_STALL);
          when HANDSHAKE_NYET =>
            packet_in_o.valid <= '1';
            packet_in_o.last <= '1';
            if hs_supported_c and r.hs = '1' then
              packet_in_o.data <= pid_byte(PID_NYET);
            else
              packet_in_o.data <= pid_byte(PID_ACK);
            end if;
          when others =>
            null;
        end case;

      when ST_IN_DATA_SEND_PID =>
        packet_in_o.valid <= '1';
        packet_in_o.last <= '0';
        if r.toggle = '1' then
          packet_in_o.data <= pid_byte(PID_DATA1);
        else
          packet_in_o.data <= pid_byte(PID_DATA0);
        end if;

      when ST_IN_DATA_SEND_ZLP =>
        packet_in_o.valid <= '1';
        packet_in_o.last <= '1';
        if r.toggle = '1' then
          packet_in_o.data <= pid_byte(PID_DATA1);
        else
          packet_in_o.data <= pid_byte(PID_DATA0);
        end if;

      when ST_IN_DATA_FORWARD =>
        packet_in_o.valid <= r.data_buf(0).valid;
        packet_in_o.last <= r.data_buf(0).last;
        packet_in_o.data <= r.data_buf(0).data;

      when others =>
        null;
    end case;
  end process;

  transaction_moore: process(r) is
  begin
    transaction_o <= TRANSACTION_CMD_IDLE;

    transaction_o.hs <= r.hs;
    transaction_o.ep_no <= r.token(10 downto 7);
    transaction_o.data <= (others => '-');
    transaction_o.nxt <= '0';
    transaction_o.toggle <= r.pid(3);
    transaction_o.handshake <= r.handshake;

    case r.state is
      when ST_RESET =>
        transaction_o.transaction <= TRANSACTION_NONE;
        transaction_o.phase <= PHASE_NONE;

      when ST_TOKEN_WAIT_PID =>
        transaction_o.transaction <= TRANSACTION_NONE;
        transaction_o.phase <= PHASE_NONE;

      when ST_TOKEN_WAIT_1 =>
        transaction_o.transaction <= TRANSACTION_NONE;
        transaction_o.phase <= PHASE_NONE;

      when ST_TOKEN_WAIT_2 =>
        transaction_o.transaction <= TRANSACTION_NONE;
        transaction_o.phase <= PHASE_NONE;

      when ST_TOKEN_WAIT_COMMIT =>
        transaction_o.transaction <= TRANSACTION_NONE;
        transaction_o.phase <= PHASE_NONE;

      when ST_TOKEN_ROUTE =>
        transaction_o.transaction <= TRANSACTION_NONE;
        transaction_o.phase <= PHASE_NONE;

      when ST_SETUP_DATA_WAIT_PID =>
        transaction_o.transaction <= TRANSACTION_SETUP;
        transaction_o.phase <= PHASE_TOKEN;

      when ST_SETUP_DATA_FORWARD =>
        transaction_o.transaction <= TRANSACTION_SETUP;
        transaction_o.phase <= PHASE_DATA;
        transaction_o.nxt <= r.data_buf(0).valid;
        transaction_o.data <= r.data_buf(0).data;

      when ST_SETUP_HANDSHAKE_WAIT_APP =>
        transaction_o.transaction <= TRANSACTION_SETUP;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_SETUP_HANDSHAKE_WAIT_TX =>
        transaction_o.transaction <= TRANSACTION_SETUP;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_OUT_DATA_WAIT_PID =>
        transaction_o.transaction <= TRANSACTION_OUT;
        transaction_o.phase <= PHASE_TOKEN;

      when ST_OUT_DATA_FORWARD =>
        transaction_o.transaction <= TRANSACTION_OUT;
        transaction_o.phase <= PHASE_DATA;
        transaction_o.nxt <= r.data_buf(0).valid;
        transaction_o.data <= r.data_buf(0).data;

      when ST_OUT_HANDSHAKE_WAIT_APP =>
        transaction_o.transaction <= TRANSACTION_OUT;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_OUT_HANDSHAKE_WAIT_TX =>
        transaction_o.transaction <= TRANSACTION_OUT;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_PING_HANDSHAKE_WAIT_APP =>
        transaction_o.transaction <= TRANSACTION_PING;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_PING_HANDSHAKE_WAIT_TX =>
        transaction_o.transaction <= TRANSACTION_PING;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_IN_DATA_WAIT_APP =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_TOKEN;

      when ST_IN_DATA_SEND_ZLP =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_TOKEN;

      when ST_IN_DATA_SEND_PID =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_DATA;
        transaction_o.nxt <= '0';

      when ST_IN_DATA_BUFFER_FILL =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_DATA;
        transaction_o.nxt <= not r.data_buf(1).valid;

      when ST_IN_DATA_FORWARD =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_DATA;
        transaction_o.nxt <= not r.data_buf(1).valid
                          and not (r.data_buf(0).last or r.data_buf(1).last);

      when ST_IN_HANDSHAKE_WAIT_PID =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_IN_HANDSHAKE_TELL_APP =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_IN_HANDSHAKE_WAIT_TX =>
        transaction_o.transaction <= TRANSACTION_IN;
        transaction_o.phase <= PHASE_HANDSHAKE;

      when ST_IGNORE =>
        transaction_o.transaction <= TRANSACTION_NONE;
        transaction_o.phase <= PHASE_NONE;
    end case;
  end process;

  frame_number_o <= r.frame_number;
  frame_o <= r.frame;

end architecture beh;
