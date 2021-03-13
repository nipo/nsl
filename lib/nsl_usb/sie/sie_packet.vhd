library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic, nsl_memory;
use nsl_usb.usb.all;
use nsl_usb.sie.all;
use nsl_usb.utmi.all;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_logic.bool.all;

entity sie_packet is
  port (
    clock_i     : in  std_ulogic;
    reset_n_i   : in  std_ulogic;
    
    phy_data_o  : out utmi_data8_sie2phy;
    phy_data_i  : in  utmi_data8_phy2sie;

    chirp_tx_i    : in  std_ulogic;

    out_o  : out packet_out;
    in_i   : in packet_in_cmd;
    in_o   : out packet_in_rsp
    );

end entity sie_packet;

architecture beh of sie_packet is

  type state_t is (
    ST_RESET,
    ST_IDLE,

    ST_RX_PID,
    ST_RX_TOKEN,
    ST_RX_DATA,
    ST_RX_IGNORE,
    ST_RX_COMMIT,

    ST_TX_START
    );

  type filler_state_t is (
    FILLER_RESET,
    FILLER_IDLE,
    FILLER_PUSH_DATA,
    FILLER_PUSH_CRC_1,
    FILLER_PUSH_CRC_2,
    FILLER_WAIT_TX_DONE
    );

  type txer_state_t is (
    TXER_RESET,
    TXER_CHIRP_TX,
    TXER_IDLE,
    TXER_FILL,
    TXER_FLUSH,
    TXER_CANCEL
    );
  
  type regs_t is
  record
    state : state_t;

    phy_in : utmi_data8_phy2sie;

    data_buffer : byte_string(0 to 2);
    data_buffer_valid : std_ulogic_vector(0 to 2);
    token_len_m1 : integer range 0 to 2;
    token_crc_value : token_crc;
    data_crc_value : data_crc;

    -- TXer FSM
    txer : txer_state_t;

    -- Filler FSM
    filler : filler_state_t;
    filler_data_crc : data_crc;
    append_data_crc : boolean;
  end record;

  signal r, rin: regs_t;

  signal tx_fifo_out_ready, tx_fifo_out_valid,
    tx_fifo_in_valid, tx_fifo_in_ready : std_ulogic;
  signal tx_fifo_out_data, tx_fifo_in_data : byte;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.filler <= FILLER_RESET;
      r.txer <= TXER_RESET;
    end if;
  end process;

  tx_fifo: nsl_memory.fifo.fifo_register_slice
    generic map(
      data_width_c => 8
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      out_data_o => tx_fifo_out_data,
      out_ready_i => tx_fifo_out_ready,
      out_valid_o => tx_fifo_out_valid,

      in_data_i => tx_fifo_in_data,
      in_ready_o => tx_fifo_in_ready,
      in_valid_i => tx_fifo_in_valid
      );
  
  transition: process(chirp_tx_i, in_i, phy_data_i,
                      r, tx_fifo_in_ready, tx_fifo_out_valid) is
  begin
    rin <= r;

    rin.phy_in <= phy_data_i;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        rin.token_crc_value <= token_crc_init;
        rin.data_crc_value <= data_crc_init;

        rin.data_buffer <= (others => (others => '-'));
        rin.data_buffer_valid <= (others => '0');

        if chirp_tx_i = '1' then
          null;

        elsif phy_data_i.rx_active = '1' then
          -- Beware: We work with port data here
          rin.state <= ST_RX_PID;

        elsif in_i.valid = '1' and r.filler = FILLER_IDLE then
          rin.state <= ST_TX_START;
        end if;

      when ST_RX_PID =>
        -- Beware: We work with registered data here
        if r.phy_in.rx_active = '0' then
          rin.state <= ST_IDLE;
        elsif r.phy_in.rx_valid = '1' then
          if not pid_byte_is_correct(r.phy_in.data) then
            rin.state <= ST_RX_IGNORE;
          else
            rin.data_buffer_valid(0) <= '1';
            rin.data_buffer(0) <= r.phy_in.data;

            case pid_get(r.phy_in.data) is
              when PID_DATA0 | PID_DATA1 | PID_DATA2 | PID_MDATA =>
                rin.state <= ST_RX_DATA;

              when others =>
                rin.state <= ST_RX_TOKEN;
                rin.token_len_m1 <= 0;

            end case;
          end if;
        end if;
        
      when ST_RX_TOKEN =>
        rin.data_buffer_valid(0) <= '0';

        if r.phy_in.rx_active = '0' then
          if r.token_len_m1 = 0 then
            rin.state <= ST_RX_COMMIT;
          elsif r.token_len_m1 = 2 and r.token_crc_value = token_crc_check then
            rin.state <= ST_RX_COMMIT;
          else
            rin.state <= ST_IDLE;
          end if;

        elsif r.phy_in.rx_error = '1' then
          rin.state <= ST_RX_IGNORE;

        elsif r.phy_in.rx_valid = '1' then
          rin.data_buffer_valid(0) <= '1';
          rin.data_buffer(0) <= r.phy_in.data;
          rin.token_len_m1 <= r.token_len_m1 + 1;
          rin.token_crc_value <= token_crc_update(r.token_crc_value, r.phy_in.data);
        end if;

      when ST_RX_DATA =>
        rin.data_buffer_valid(0) <= '0';

        if r.phy_in.rx_active = '0' then
          if r.data_crc_value = data_crc_check then
            rin.state <= ST_RX_COMMIT;
          else
            rin.state <= ST_IDLE;
          end if;

        elsif r.phy_in.rx_error = '1' then
          rin.state <= ST_RX_IGNORE;

        elsif r.phy_in.rx_valid = '1' then
          rin.data_buffer_valid <= r.data_buffer_valid(1 to 2) & '1';
          rin.data_buffer <= r.data_buffer(1 to 2) & r.phy_in.data;
          rin.data_crc_value <= data_crc_update(r.data_crc_value, r.phy_in.data);
        end if;

      when ST_RX_COMMIT =>
        rin.data_buffer_valid(0) <= '0';
        if r.data_buffer_valid(0) = '0' then
          rin.state <= ST_IDLE;
        end if;

      when ST_RX_IGNORE =>
        if r.phy_in.rx_active = '0' then
          rin.state <= ST_IDLE;
        end if;

      when ST_TX_START =>
        rin.state <= ST_IDLE;
    end case;

    case r.filler is
      when FILLER_RESET =>
        rin.filler <= FILLER_IDLE;

      when FILLER_IDLE =>
        if r.state = ST_TX_START then
          rin.filler_data_crc <= data_crc_init;
          rin.filler <= FILLER_PUSH_DATA;

          case pid_get(in_i.data) is
            when PID_DATA0 | PID_DATA1 | PID_DATA2 | PID_MDATA =>
              rin.append_data_crc <= true;

              -- ZLP ?
              if in_i.last = '1' then
                rin.filler <= FILLER_PUSH_CRC_1;
              end if;
            when others =>
              rin.append_data_crc <= false;

              -- Standalone PID ?
              if in_i.last = '1' then
                rin.filler <= FILLER_WAIT_TX_DONE;
              end if;
          end case;
        end if;

      when FILLER_PUSH_DATA =>
        if tx_fifo_in_ready = '1' and in_i.valid = '1' then
          rin.filler_data_crc <= data_crc_update(r.filler_data_crc, in_i.data);
          if in_i.last = '1' then
            if r.append_data_crc then
              rin.filler <= FILLER_PUSH_CRC_1;
            else
              rin.filler <= FILLER_WAIT_TX_DONE;
            end if;
          end if;
        end if;
        
      when FILLER_PUSH_CRC_1 =>
        if tx_fifo_in_ready = '1' then
          rin.filler <= FILLER_PUSH_CRC_2;
        end if;

      when FILLER_PUSH_CRC_2 =>
        if tx_fifo_in_ready = '1' then
          rin.filler <= FILLER_WAIT_TX_DONE;
        end if;

      when FILLER_WAIT_TX_DONE =>
        if r.txer = TXER_IDLE then
          rin.filler <= FILLER_IDLE;
        end if;
    end case;
            
    case r.txer is
      when TXER_RESET =>
        rin.txer <= TXER_IDLE;

      when TXER_IDLE =>
        if r.state = ST_TX_START then
          rin.txer <= TXER_FILL;
        elsif chirp_tx_i = '1' then
          rin.txer <= TXER_CHIRP_TX;
        end if;

      when TXER_CHIRP_TX =>
        if chirp_tx_i = '0' then
          rin.txer <= TXER_IDLE;
        end if;

      when TXER_FILL =>
        if tx_fifo_out_valid = '1' then
          rin.txer <= TXER_FLUSH;
        end if;

      when TXER_FLUSH =>
        if tx_fifo_out_valid = '0' then
          rin.txer <= TXER_IDLE;
        elsif phy_data_i.rx_active = '1' then
          rin.txer <= TXER_CANCEL;
        end if;

      when TXER_CANCEL =>
        if tx_fifo_out_valid = '0' then
          rin.txer <= TXER_IDLE;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    out_o.active <= '0';
    out_o.valid <= '0';
    out_o.data <= (others => '-');
    out_o.commit <= '0';

    case r.state is
      when ST_RX_PID | ST_RX_TOKEN | ST_RX_DATA =>
        out_o.active <= '1';
        out_o.valid <= r.data_buffer_valid(0);
        out_o.data <= r.data_buffer(0);
        out_o.commit <= '0';

      when ST_RX_COMMIT =>
        if r.data_buffer_valid(0) = '1' then
          out_o.active <= '1';
          out_o.valid <= r.data_buffer_valid(0);
          out_o.data <= r.data_buffer(0);
          out_o.commit <= '0';
        else
          out_o.commit <= '1';
        end if;

      when others =>
        null;
    end case;
  end process;

  filler: process(r, tx_fifo_in_ready, in_i)
  begin
    -- Forward from Packet interface to internal FIFO.
    in_o.ready <= '0';
    tx_fifo_in_valid <= '0';
    tx_fifo_in_data <= (others => '-');

    case r.filler is
      when FILLER_IDLE =>
        if r.state = ST_TX_START then
          tx_fifo_in_valid <= '1';
          tx_fifo_in_data <= in_i.data;
          in_o.ready <= '1';
        end if;

      when FILLER_PUSH_DATA =>
        tx_fifo_in_valid <= in_i.valid;
        tx_fifo_in_data <= in_i.data;
        in_o.ready <= tx_fifo_in_ready;

      when FILLER_PUSH_CRC_1 =>
        tx_fifo_in_valid <= '1';
        tx_fifo_in_data <= byte(r.filler_data_crc(7 downto 0));

      when FILLER_PUSH_CRC_2 =>
        tx_fifo_in_valid <= '1';
        tx_fifo_in_data <= byte(r.filler_data_crc(15 downto 8));

      when others =>
        null;
    end case;
  end process;

  txer: process(r, tx_fifo_out_valid, tx_fifo_out_data, phy_data_i)
  begin
    -- Forward from internal FIFO to Phy interface.
    tx_fifo_out_ready <= '0';
    phy_data_o.tx_valid <= '0';
    phy_data_o.data <= (others => '-');

    case r.txer is
      when TXER_CHIRP_TX =>
        phy_data_o.tx_valid <= '1';
        phy_data_o.data <= (others => '0');

      when TXER_FLUSH =>
        phy_data_o.tx_valid <= tx_fifo_out_valid;
        phy_data_o.data <= tx_fifo_out_data;
        tx_fifo_out_ready <= phy_data_i.tx_ready;

      when TXER_CANCEL =>
        tx_fifo_out_ready <= '1';

      when others =>
        null;
    end case;
  end process;

end architecture beh;

