library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity sie_ep0 is
  generic (
    in_ep_count_c, out_ep_count_c : endpoint_idx_t;
    self_powered_c       : boolean
    );
  port (
    clock_i          : in  std_ulogic;
    reset_n_i        : in  std_ulogic;

    dev_addr_o   : out device_address_t;
    configured_o : out std_ulogic;

    transfer_i : in  transfer_cmd;
    transfer_o : out transfer_rsp;

    halted_in_i : in std_ulogic_vector(1 to in_ep_count_c);
    halt_in_o : out std_ulogic_vector(1 to in_ep_count_c);
    clear_in_o : out std_ulogic_vector(1 to in_ep_count_c);

    halted_out_i : in std_ulogic_vector(1 to out_ep_count_c);
    halt_out_o : out std_ulogic_vector(1 to out_ep_count_c);
    clear_out_o : out std_ulogic_vector(1 to out_ep_count_c);

    descriptor_o : out descriptor_cmd;
    descriptor_i : in  descriptor_rsp
    );
end entity sie_ep0;

architecture beh of sie_ep0 is

  -- See Figure 8-37

  -- For now, we do not support EP0 Control Write transfers (control
  -- with a OUT Data Stage), matching states are not defined, we'll
  -- use STATUS_ERROR for them.
  type status_t is (
    -- Sends STALL to any Data transfer
    STATUS_ERROR,
    -- ZLP Data IN, STALL Data Out
    STATUS_NODATA_DONE,
    -- Stall Data IN, ACK Data Out
    STATUS_READ_DONE,
    -- Returns data from buffer in Data IN Phases, ACKs Data OUT Status
    STATUS_READ_BUFFER,
    -- Returns data from descriptor in Data IN Phases, ACKs Data OUT Status
    STATUS_READ_DESCRIPTOR
    );

  -- Just an alias, has the same effect: ZLP IN, Stall OUT
  constant STATUS_READ_ERROR : status_t := STATUS_NODATA_DONE;
  
  type stage_t is (
    STAGE_NONE,
    STAGE_SETUP,

    STAGE_OUT_DATA,
    STAGE_IN_STATUS,

    STAGE_IN_DATA,
    STAGE_OUT_STATUS
    );
  
  type state_t is (
    ST_RESET,

    ST_IDLE,

    ST_CONTROL_NODATA,
    ST_CONTROL_WRITE,
    ST_CONTROL_READ,
    ST_CONTROL_ENDPOINT_HALT_CLEAR,
    ST_CONTROL_ENDPOINT_HALT_SET,
    ST_CONTROL_ENDPOINT_HALT_READ,
    ST_CONTROL_DEVICE_READ,
    ST_CONTROL_EP_READ,

    ST_DESCRIPTOR_LOOKUP,
    ST_DESCRIPTOR_ROUTE,
    
    ST_STALL,

    ST_EP0_SETUP,
    ST_EP0_IN,
    ST_EP0_OUT,
    ST_EP0_PING,
    ST_EP0_IN_BUFFER_DATA_FILL,
    ST_EP0_IN_BUFFER_DATA_RUN,
    ST_EP0_IN_HANDSHAKE,
    ST_EP0_IN_DESC_DATA_SEEKING,
    ST_EP0_IN_DESC_DATA_FILL,
    ST_EP0_IN_DESC_DATA_RUN,
    ST_EP0_IN_DESC_HANDSHAKE,
    ST_EP0_IN_OTHER
    );
  
  constant mps_m1_c : unsigned(5 downto 0) := (others => '1');
  constant max_len_c : integer := 128;

  type regs_t is
  record
    dev_addr, dev_addr_next   : device_address_t;
    configured : std_ulogic;
    hs : std_ulogic;

    state           : state_t;

    transfer        : transfer_t;
    phase           : phase_t;

    -- Control logic
    setup       : byte_string(0 to 7);
    stage       : stage_t;
    status      : status_t;

    -- Control endpoint IN buffer
    valid, last : std_ulogic;
    data        : byte;

    -- Control endpoint Data pointers
    checkpoint  : unsigned(6 downto 0);
    ptr         : unsigned(6 downto 0);
    len_m1      : unsigned(6 downto 0);
  end record;
  
  signal r, rin : regs_t;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, transfer_i, descriptor_i, halted_in_i, halted_out_i) is
    variable setup : setup_t;
  begin
    setup := setup_unpack(r.setup);

    rin <= r;

    rin.hs <= transfer_i.hs;

    if r.transfer /= transfer_i.transfer
      or transfer_i.transfer = TRANSFER_NONE
      or transfer_i.phase = PHASE_NONE then
      -- Default catchall resetter
      rin.state <= ST_IDLE;
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;
        rin.status <= STATUS_ERROR;
        rin.dev_addr <= (others => '0');
        rin.dev_addr_next <= (others => '0');
        rin.stage <= STAGE_NONE;
        rin.configured <= '0';
        
      when ST_IDLE =>
        rin.phase <= PHASE_NONE;
        rin.transfer <= transfer_i.transfer;

        if transfer_i.phase /= PHASE_NONE then
          -- default
          rin.state <= ST_STALL;
          rin.ptr <= to_unsigned(0, rin.ptr'length);

          case transfer_i.transfer is
            when TRANSFER_SETUP =>
              rin.state <= ST_EP0_SETUP;
              rin.phase <= PHASE_DATA;
              rin.stage <= STAGE_SETUP;

            when TRANSFER_OUT =>
              rin.state <= ST_EP0_OUT;
              rin.phase <= PHASE_DATA;

            when TRANSFER_IN =>
              rin.ptr <= r.checkpoint;
              rin.state <= ST_EP0_IN;
              rin.phase <= PHASE_TOKEN;

            when TRANSFER_PING =>
              if r.stage = STAGE_OUT_STATUS then
                rin.state <= ST_EP0_PING;
                rin.phase <= PHASE_TOKEN;
              end if;

            when others =>
              null;
          end case;
        end if;

      when ST_EP0_SETUP =>
        case r.phase is
          when PHASE_DATA =>
            case transfer_i.phase is
              when PHASE_DATA =>
                if transfer_i.nxt = '1' then
                  rin.setup <= r.setup(1 to 7) & transfer_i.data;
                  rin.ptr <= r.ptr + 1;
                end if;

              when PHASE_HANDSHAKE =>
                rin.phase <= PHASE_HANDSHAKE;
                if r.ptr /= 8 then
                  -- Bad packet, cancel the setup, still stay here for
                  -- handshaking
                  rin.stage <= STAGE_NONE;
                end if;

              when others => null;
            end case;

          when PHASE_HANDSHAKE =>
            case transfer_i.phase is
              when PHASE_NONE =>
                rin.checkpoint <= to_unsigned(0, rin.checkpoint'length);
                rin.ptr <= to_unsigned(0, rin.ptr'length);
                rin.len_m1 <= to_unsigned(0, rin.len_m1'length);

                -- Setup done
                if r.stage = STAGE_NONE then
                  -- Cancelled already
                  rin.state <= ST_IDLE;
                elsif setup.direction = DEVICE_TO_HOST then
                  rin.state <= ST_CONTROL_READ;
                  rin.stage <= STAGE_IN_DATA;
                elsif setup.length = 0 then
                  rin.state <= ST_CONTROL_NODATA;
                  rin.stage <= STAGE_IN_STATUS;
                else
                  rin.state <= ST_CONTROL_WRITE;
                  rin.stage <= STAGE_OUT_DATA;
                end if;

              when others => null;
            end case;

          when others => null;
        end case;

      when ST_CONTROL_NODATA =>
        rin.status <= STATUS_ERROR;
        rin.state <= ST_IDLE;

        if setup.rtype = SETUP_TYPE_STANDARD then
          case setup.request is
            when REQUEST_SET_ADDRESS =>
              rin.dev_addr_next <= setup.value(6 downto 0);
              rin.status <= STATUS_NODATA_DONE;

            when REQUEST_SET_CONFIGURATION =>
              rin.configured <= setup.value(0);
              rin.status <= STATUS_NODATA_DONE;

            when REQUEST_CLEAR_FEATURE =>
              if feature_selector_from_value(setup.value)
                = FEATURE_SELECTOR_ENDPOINT_HALT
                and setup.recipient = SETUP_RECIPIENT_ENDPOINT then
                rin.state <= ST_CONTROL_ENDPOINT_HALT_CLEAR;
              end if;

            when REQUEST_SET_FEATURE =>
              if feature_selector_from_value(setup.value)
                = FEATURE_SELECTOR_ENDPOINT_HALT
                and setup.recipient = SETUP_RECIPIENT_ENDPOINT then
                rin.state <= ST_CONTROL_ENDPOINT_HALT_SET;
              end if;

            when others =>
              null;
          end case;
        end if;

      when ST_CONTROL_WRITE =>
        rin.status <= STATUS_ERROR;
        rin.state <= ST_IDLE;

      when ST_CONTROL_READ =>
        rin.status <= STATUS_READ_ERROR;
        rin.state <= ST_IDLE;
        rin.data <= (others => '0');

        if setup.rtype = SETUP_TYPE_STANDARD then
          case setup.recipient is
            when SETUP_RECIPIENT_DEVICE =>
              rin.state <= ST_CONTROL_DEVICE_READ;

            when SETUP_RECIPIENT_ENDPOINT =>
              rin.state <= ST_CONTROL_EP_READ;

            when others =>
              null;
          end case;
        end if;

      when ST_CONTROL_DEVICE_READ =>
        rin.state <= ST_IDLE;
        rin.status <= STATUS_READ_ERROR;

        case setup.request is
          when REQUEST_GET_STATUS =>
            if setup.length /= 2 then
              rin.status <= STATUS_READ_ERROR;
            else
              rin.status <= STATUS_READ_BUFFER;
            end if;
            rin.data(0) <= to_logic(self_powered_c);
            rin.len_m1 <= to_unsigned(1, rin.len_m1'length);
            
          when REQUEST_GET_CONFIGURATION =>
            if setup.length /= 1 then
              rin.status <= STATUS_READ_ERROR;
            else
              rin.status <= STATUS_READ_BUFFER;
            end if;
            rin.data(0) <= r.configured;
            rin.len_m1 <= to_unsigned(0, rin.len_m1'length);

          when REQUEST_GET_DESCRIPTOR =>
            rin.state <= ST_DESCRIPTOR_LOOKUP;

          when others =>
            null;
        end case;

      when ST_DESCRIPTOR_LOOKUP =>
        rin.state <= ST_DESCRIPTOR_ROUTE;

      when ST_DESCRIPTOR_ROUTE =>
        if descriptor_i.lookup_done = '0' then
          rin.state <= ST_DESCRIPTOR_ROUTE;
        else
          rin.state <= ST_IDLE;
          if descriptor_i.exists = '1' then
            rin.status <= STATUS_READ_DESCRIPTOR;
          else
            rin.status <= STATUS_READ_ERROR;
          end if;
        end if;

      when ST_EP0_IN =>
        case r.stage is
          when STAGE_IN_DATA =>
            case r.status is
              when STATUS_READ_DESCRIPTOR =>
                rin.len_m1 <= resize(setup.length - 1, rin.len_m1'length);
                rin.state <= ST_EP0_IN_DESC_DATA_SEEKING;
              when STATUS_READ_BUFFER =>
                rin.state <= ST_EP0_IN_BUFFER_DATA_FILL;
              when others =>
                rin.state <= ST_EP0_IN_OTHER;
            end case;
          when others =>
            rin.state <= ST_EP0_IN_OTHER;
        end case;

      when ST_EP0_IN_OTHER =>
        -- Special case for set address: address must be committed
        -- adter status stage
        if r.stage = STAGE_IN_STATUS
          and r.status = STATUS_NODATA_DONE
          and transfer_i.phase = PHASE_HANDSHAKE then
          rin.dev_addr <= r.dev_addr_next;
        end if;

        -- Stay here
        
      when ST_EP0_IN_BUFFER_DATA_FILL =>
        case setup.request is
          when REQUEST_GET_STATUS =>
            rin.data(0) <= to_logic(self_powered_c);
            rin.len_m1 <= to_unsigned(1, rin.len_m1'length);
            
          when REQUEST_GET_CONFIGURATION =>
            rin.data(0) <= r.configured;
            rin.len_m1 <= to_unsigned(0, rin.len_m1'length);

          when others =>
            null;
        end case;
        rin.state <= ST_EP0_IN_BUFFER_DATA_RUN;

      when ST_EP0_IN_DESC_DATA_SEEKING =>
        rin.state <= ST_EP0_IN_DESC_DATA_FILL;

      when ST_EP0_IN_DESC_DATA_FILL =>
        rin.data <= descriptor_i.data;
        rin.last <= descriptor_i.last;
        if descriptor_i.last = '1' then
          rin.state <= ST_EP0_IN_DESC_HANDSHAKE;
        else
          rin.state <= ST_EP0_IN_DESC_DATA_RUN;
        end if;

      when ST_EP0_IN_DESC_DATA_RUN =>
        if (transfer_i.phase = PHASE_DATA and transfer_i.nxt = '1')
          or r.valid = '0' then
          rin.data <= descriptor_i.data;
          rin.last <= descriptor_i.last;
          rin.valid <= '1';
        end if;

        if transfer_i.phase = PHASE_DATA and transfer_i.nxt = '1' then
          rin.ptr <= r.ptr + 1;
          if r.ptr = r.len_m1 -- Setup size overflow
            or r.last = '1' -- Descriptor end
            or r.ptr(mps_m1_c'range) = mps_m1_c -- MPS
          then
            rin.state <= ST_EP0_IN_DESC_HANDSHAKE;
          end if;
        end if;
        
      when ST_CONTROL_EP_READ =>
        rin.state <= ST_IDLE;
        rin.status <= STATUS_READ_ERROR;

        case setup.request is
          when REQUEST_GET_STATUS =>
            rin.state <= ST_CONTROL_ENDPOINT_HALT_READ;

          when others =>
            null;
        end case;

      when ST_CONTROL_ENDPOINT_HALT_READ =>
        rin.status <= STATUS_READ_ERROR;
        rin.state <= ST_IDLE;

        if setup.index(7) = '1' then
          for i in 1 to in_ep_count_c
          loop
            if i = to_integer(setup.index(3 downto 0)) then
              rin.status <= STATUS_READ_BUFFER;
              rin.data(0) <= halted_in_i(i);
              rin.len_m1 <= to_unsigned(1, rin.len_m1'length);
            end if;
          end loop;
        else
          for i in 1 to out_ep_count_c
          loop
            if i = to_integer(setup.index(3 downto 0)) then
              rin.status <= STATUS_READ_BUFFER;
              rin.data(0) <= halted_out_i(i);
              rin.len_m1 <= to_unsigned(2, rin.len_m1'length);
            end if;
          end loop;
        end if;

      when ST_CONTROL_ENDPOINT_HALT_SET | ST_CONTROL_ENDPOINT_HALT_CLEAR =>
        rin.status <= STATUS_NODATA_DONE;
        rin.state <= ST_IDLE;

      when ST_EP0_OUT =>
        rin.phase <= transfer_i.phase;
        -- catchall resetter will take it
        null;

      when ST_EP0_PING | ST_STALL =>
        null;

      when ST_EP0_IN_BUFFER_DATA_RUN =>
        if transfer_i.phase = PHASE_DATA and transfer_i.nxt = '1' then
          rin.data <= (others => '0');
          rin.ptr <= r.ptr + 1;
          if r.ptr = r.len_m1 then
            rin.state <= ST_EP0_IN_HANDSHAKE;
          end if;
        end if;

      when ST_EP0_IN_DESC_HANDSHAKE =>
        if transfer_i.phase = PHASE_HANDSHAKE then
          case transfer_i.handshake is
            when HANDSHAKE_ACK =>
              rin.checkpoint <= r.ptr;
              rin.phase <= PHASE_NONE;

            when HANDSHAKE_NAK =>
              rin.phase <= PHASE_NONE;

            when others =>
          end case;
        end if;

      when ST_EP0_IN_HANDSHAKE =>
        if transfer_i.phase = PHASE_HANDSHAKE then
          rin.status <= STATUS_READ_DONE;
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  transfer_moore: process(r)
  begin
    transfer_o.phase <= PHASE_NONE;
    transfer_o.toggle <= '-';
    transfer_o.data <= (others => '-');
    transfer_o.last <= '-';
    transfer_o.handshake <= HANDSHAKE_SILENT;
    
    case r.state is
      when ST_RESET | ST_IDLE
        | ST_CONTROL_NODATA | ST_CONTROL_WRITE | ST_CONTROL_READ
        | ST_CONTROL_ENDPOINT_HALT_CLEAR | ST_CONTROL_ENDPOINT_HALT_SET
        | ST_CONTROL_DEVICE_READ | ST_CONTROL_EP_READ
        | ST_EP0_IN =>
        null;

      when ST_DESCRIPTOR_LOOKUP | ST_DESCRIPTOR_ROUTE =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        transfer_o.handshake <= HANDSHAKE_ACK;
        
      when ST_STALL =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        transfer_o.handshake <= HANDSHAKE_STALL;
        
      when ST_EP0_SETUP =>
        transfer_o.phase <= r.phase;
        if r.stage = STAGE_SETUP then
          transfer_o.handshake <= HANDSHAKE_ACK;
        else
          transfer_o.handshake <= HANDSHAKE_NAK;
        end if;

      when ST_CONTROL_ENDPOINT_HALT_READ | ST_EP0_IN_BUFFER_DATA_FILL
        | ST_EP0_IN_DESC_DATA_SEEKING | ST_EP0_IN_DESC_DATA_FILL =>
        transfer_o.phase <= PHASE_TOKEN;
        
      when ST_EP0_IN_BUFFER_DATA_RUN =>
        transfer_o.phase <= PHASE_DATA;
        transfer_o.data <= r.data;
        transfer_o.last <= to_logic(r.ptr = r.len_m1);
        transfer_o.toggle <= '1';

      when ST_EP0_IN_DESC_DATA_RUN =>
        transfer_o.phase <= PHASE_DATA;
        transfer_o.data <= r.data;
        transfer_o.last <= to_logic(
          r.ptr = r.len_m1 or r.last = '1' or r.ptr(mps_m1_c'range) = mps_m1_c
          );
        transfer_o.toggle <= not r.ptr(mps_m1_c'left + 1);

      when ST_EP0_IN_HANDSHAKE | ST_EP0_IN_DESC_HANDSHAKE =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        if r.last = '1' then
          transfer_o.handshake <= HANDSHAKE_ACK;
        end if;

      when ST_EP0_OUT =>
        transfer_o.phase <= r.phase;
        case r.status is
          when STATUS_ERROR | STATUS_NODATA_DONE =>
            transfer_o.handshake <= HANDSHAKE_STALL;
          when STATUS_READ_DONE | STATUS_READ_BUFFER | STATUS_READ_DESCRIPTOR =>
            transfer_o.handshake <= HANDSHAKE_ACK;
        end case;

      when ST_EP0_PING =>
        transfer_o.phase <= PHASE_HANDSHAKE;
        case r.status is
          when STATUS_ERROR | STATUS_NODATA_DONE =>
            transfer_o.handshake <= HANDSHAKE_STALL;
          when STATUS_READ_DONE | STATUS_READ_BUFFER | STATUS_READ_DESCRIPTOR =>
            transfer_o.handshake <= HANDSHAKE_ACK;
        end case;

      when ST_EP0_IN_OTHER =>
        transfer_o.toggle <= '1';
        transfer_o.phase <= PHASE_HANDSHAKE;
        case r.status is
          when STATUS_ERROR =>
            transfer_o.handshake <= HANDSHAKE_STALL;
          when STATUS_NODATA_DONE | STATUS_READ_DONE
            | STATUS_READ_BUFFER | STATUS_READ_DESCRIPTOR =>
            transfer_o.handshake <= HANDSHAKE_ACK;
        end case;
    end case;
  end process;

  halt_moore: process(r)
    variable setup : setup_t;
  begin
    setup := setup_unpack(r.setup);

    halt_in_o <= (others => '0');
    halt_out_o <= (others => '0');
    clear_in_o <= (others => '0');
    clear_out_o <= (others => '0');

    case r.state is
      when ST_CONTROL_ENDPOINT_HALT_CLEAR =>
        if setup.index(7) = '1' then
          for i in 1 to in_ep_count_c
          loop
            if i = to_integer(setup.index(3 downto 0)) then
              clear_in_o(i) <= '1';
            end if;
          end loop;
        else
          for i in 1 to out_ep_count_c
          loop
            if i = to_integer(setup.index(3 downto 0)) then
              clear_out_o(i) <= '1';
            end if;
          end loop;
        end if;

      when ST_CONTROL_ENDPOINT_HALT_SET =>
        if setup.index(7) = '1' then
          for i in 1 to in_ep_count_c
          loop
            if i = to_integer(setup.index(3 downto 0)) then
              halt_in_o(i) <= '1';
            end if;
          end loop;
        else
          for i in 1 to out_ep_count_c
          loop
            if i = to_integer(setup.index(3 downto 0)) then
              halt_out_o(i) <= '1';
            end if;
          end loop;
        end if;

      when others =>
        null;
    end case;
  end process;

  dev_addr_o <= r.dev_addr;
  configured_o <= r.configured;
  
  desc_mealy: process(r, transfer_i) is
    variable setup : setup_t;
  begin
    setup := setup_unpack(r.setup);

    descriptor_o.hs <= r.hs;

    descriptor_o.lookup <= '0';
    descriptor_o.dtype <= (others => '-');
    descriptor_o.index <= (others => '-');

    descriptor_o.seek <= '0';
    descriptor_o.offset <= (others => '-');
    
    descriptor_o.read <= '0';

    case r.state is
      when ST_DESCRIPTOR_LOOKUP =>
        descriptor_o.lookup <= '1';
        descriptor_o.dtype <= descriptor_type_from_value(setup.value);
        descriptor_o.index <= resize(
          descriptor_index_from_value(setup.value), descriptor_o.index'length);
        -- index is language, we dont care.
        
      when ST_EP0_IN =>
        if r.status = STATUS_READ_DESCRIPTOR then
          descriptor_o.seek <= '1';
          descriptor_o.offset <= resize(r.ptr, descriptor_o.offset'length);
        end if;

      when ST_EP0_IN_DESC_DATA_FILL =>
        descriptor_o.read <= '1';

      when ST_EP0_IN_DESC_DATA_RUN =>
        descriptor_o.read <= transfer_i.nxt;

      when others =>
        null;
    end case;
  end process;
  
end architecture beh;
