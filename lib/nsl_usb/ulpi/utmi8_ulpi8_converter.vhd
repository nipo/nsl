library ieee;
use ieee.std_logic_1164.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_data.bytestream.all;
use nsl_usb.usb.all;
use nsl_usb.utmi.all;
use nsl_usb.ulpi.all;
use nsl_logic.bool.all;

entity utmi8_ulpi8_converter is
  port(
    reset_n_i : in std_ulogic;

    ulpi_i : in ulpi8_phy2link;
    ulpi_o : out ulpi8_link2phy;

    utmi_data_i: in utmi_data8_sie2phy;
    utmi_data_o: out utmi_data8_phy2sie;
    utmi_system_i: in utmi_system_sie2phy;
    utmi_system_o: out utmi_system_phy2sie
    );
end entity utmi8_ulpi8_converter;

architecture beh of utmi8_ulpi8_converter is

  type state_t is (
    ST_RESET,

    ST_RX,
    ST_TX_IDLE,

    ST_OTG_CTRL_WRITE_CMD,
    ST_OTG_CTRL_WRITE_DATA,

    ST_FUNC_CTRL_WRITE_CMD,
    ST_FUNC_CTRL_WRITE_DATA,

    ST_TX_START,
    ST_TX_PID_SEND,
    ST_TX_FORWARD,

    ST_TX_OVER
    );

  type regs_t is
  record
    state: state_t;

    last_dir : std_ulogic;
    
    -- rx buffer
    rx_valid : std_ulogic;
    rx_data : byte;

    -- tx fifo
    tx_pid : pid_t;
    tx_data_fillness : integer range 0 to 2;
    tx_data_over : boolean;
    tx_data : byte_string(0 to 1);

    -- status
    line_state : usb_symbol_t;
    host_disconnect, rx_active, rx_error : std_ulogic;

    -- control
    xcvr_select : utmi_mode_t;
    term_select : utmi_mode_t;
    suspend : boolean;
    op_mode : utmi_op_mode_t;

    func_ctrl_dirty : boolean;
    otg_ctrl_dirty : boolean;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(ulpi_i.clock, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(ulpi_i.clock) then
      r <= rin;
    end if;
  end process;

  transition: process(r, ulpi_i, utmi_system_i, utmi_data_i)
  begin
    rin <= r;

    rin.last_dir <= ulpi_i.dir;
    
    if utmi_system_i.reset = '1' then
      rin.func_ctrl_dirty <= true;
      rin.otg_ctrl_dirty <= true;
      rin.xcvr_select <= UTMI_MODE_FS;
      rin.term_select <= UTMI_MODE_HS;
      rin.op_mode <= UTMI_OP_MODE_NORMAL;
      rin.suspend <= false;
      rin.state <= ST_RX;
    end if;
    
    case r.state is
      when ST_RESET =>
        rin.func_ctrl_dirty <= true;
        rin.otg_ctrl_dirty <= true;
        rin.xcvr_select <= UTMI_MODE_FS;
        rin.term_select <= UTMI_MODE_HS;
        rin.op_mode <= UTMI_OP_MODE_NORMAL;
        rin.suspend <= false;
        rin.state <= ST_RX;
        
      when ST_RX =>
        rin.rx_valid <= '0';
        if ulpi_i.nxt = '0' then
          rin.line_state <= to_usb_symbol(ulpi_i.data(1 downto 0));
          case ulpi_i.data(5 downto 4) is
            when "00" =>
              rin.rx_active <= '0';
              rin.rx_error <= '0';
              rin.host_disconnect <= '0';
            when "01" =>
              rin.rx_active <= '1';
              rin.rx_error <= '0';
              rin.host_disconnect <= '0';
            when "11" =>
              rin.rx_active <= '1';
              rin.rx_error <= '1';
              rin.host_disconnect <= '0';
            when others =>
              rin.rx_active <= '0';
              rin.rx_error <= '0';
              rin.host_disconnect <= '1';
          end case;
        else
          rin.rx_valid <= '1';
          rin.rx_data <= ulpi_i.data;
        end if;
        
      when ST_TX_IDLE =>
        if r.otg_ctrl_dirty then
          rin.state <= ST_OTG_CTRL_WRITE_CMD;
        elsif r.func_ctrl_dirty then
          rin.state <= ST_FUNC_CTRL_WRITE_CMD;
        elsif utmi_data_i.tx_valid = '1' then
          rin.tx_pid <= pid_get(utmi_data_i.data);
          rin.state <= ST_TX_START;
          rin.tx_data_fillness <= 0;
          rin.tx_data_over <= false;
        end if;

      when ST_OTG_CTRL_WRITE_CMD =>
        if ulpi_i.nxt = '1' and ulpi_i.dir = '0' then
          rin.state <= ST_OTG_CTRL_WRITE_DATA;
          rin.otg_ctrl_dirty <= false;
        end if;

      when ST_FUNC_CTRL_WRITE_CMD =>
        if ulpi_i.nxt = '1' and ulpi_i.dir = '0' then
          rin.state <= ST_FUNC_CTRL_WRITE_DATA;
          rin.func_ctrl_dirty <= false;
        end if;

      when ST_OTG_CTRL_WRITE_DATA | ST_FUNC_CTRL_WRITE_DATA =>
        if ulpi_i.nxt = '1' then
          rin.state <= ST_TX_OVER;
        end if;

      when ST_TX_START =>
        rin.state <= ST_TX_PID_SEND;

      when ST_TX_PID_SEND =>
        if utmi_data_i.tx_valid = '0' or r.tx_data_over then
          rin.tx_data_over <= true;
        else
          if r.tx_data_fillness < 2 then
            rin.tx_data(r.tx_data_fillness) <= utmi_data_i.data;
            rin.tx_data_fillness <= r.tx_data_fillness + 1;
          end if;
        end if;

        if ulpi_i.nxt = '1' then
          if r.tx_data_over and r.tx_data_fillness = 0 then
            rin.state <= ST_TX_OVER;
          else
            rin.state <= ST_TX_FORWARD;
          end if;
        end if;

      when ST_TX_FORWARD =>
        if ulpi_i.nxt = '1' then
          rin.tx_data_fillness <= r.tx_data_fillness - 1;
          rin.tx_data(0) <= r.tx_data(1);
        end if;

        if utmi_data_i.tx_valid = '0' or r.tx_data_over then
          rin.tx_data_over <= true;
        elsif ulpi_i.nxt = '1' and r.tx_data_fillness = 2 then
          null;
        elsif ulpi_i.nxt = '1' and r.tx_data_fillness = 1 then
          rin.tx_data(0) <= utmi_data_i.data;
          rin.tx_data_fillness <= 1;
        elsif ulpi_i.nxt = '0' and r.tx_data_fillness < 2 then
          rin.tx_data(r.tx_data_fillness) <= utmi_data_i.data;
          rin.tx_data_fillness <= r.tx_data_fillness + 1;
        end if;

        if r.tx_data_fillness = 1 and ulpi_i.nxt = '1'
          and (utmi_data_i.tx_valid = '0' or r.tx_data_over) then
          rin.state <= ST_TX_OVER;
        end if;

      when ST_TX_OVER =>
        rin.state <= ST_TX_IDLE;
        rin.tx_data_over <= false;
    end case;

    if r.xcvr_select /= utmi_system_i.xcvr_select then
      rin.xcvr_select <= utmi_system_i.xcvr_select;
      rin.func_ctrl_dirty <= true;
    end if;

    if r.term_select /= utmi_system_i.term_select then
      rin.term_select <= utmi_system_i.term_select;
      rin.func_ctrl_dirty <= true;
    end if;

    if r.op_mode /= utmi_system_i.op_mode then
      rin.op_mode <= utmi_system_i.op_mode;
      rin.func_ctrl_dirty <= true;
    end if;

    if r.suspend /= utmi_system_i.suspend then
      rin.suspend <= utmi_system_i.suspend;
      rin.func_ctrl_dirty <= true;
    end if;
    
    case r.state is
      when ST_RESET =>
        null;

      when ST_RX =>
        if ulpi_i.dir = '0' then
          rin.state <= ST_TX_IDLE;
          rin.rx_active <= '0';
          rin.rx_error <= '0';
          rin.host_disconnect <= '0';
        end if;

      when others =>
        if ulpi_i.dir = '1' then
          rin.state <= ST_RX;
          rin.rx_valid <= '0';
          rin.rx_active <= '0';
          rin.rx_error <= '0';
          rin.host_disconnect <= '0';
        end if;
    end case;

    -- 3.8.2.4: If dir was previously low, the PHY will assert both
    -- dir and nxt so that the Link knows immediately that this is a
    -- USB receive packet.
    if r.last_dir = '0' and ulpi_i.dir = '1' then
      rin.rx_active <= '1';
    end if;
  end process;

  utmi_system_o.clock <= ulpi_i.clock;
  
  moore: process(r)
  begin
    ulpi_o.data <= ulpi_cmd_noop;
    ulpi_o.stp <= '0';
    ulpi_o.reset <= '0';

    utmi_system_o.line_state <= r.line_state;

    utmi_data_o.tx_ready <= '0';
    utmi_data_o.data <= (others => '-');
    utmi_data_o.rx_valid <= '0';
    utmi_data_o.rx_active <= '0';
    utmi_data_o.rx_error <= '0';

    case r.state is
      when ST_RESET =>
        ulpi_o.reset <= '1';

      when ST_TX_IDLE =>
        ulpi_o.data <= ulpi_cmd_noop;

      when ST_RX =>
        utmi_data_o.data <= r.rx_data;
        utmi_data_o.rx_valid <= r.rx_valid;
        utmi_data_o.rx_active <= r.rx_active;
        utmi_data_o.rx_error <= r.rx_error;

      when ST_OTG_CTRL_WRITE_CMD =>
        ulpi_o.data <= ulpi_cmd_reg_write(ULPI_REG_OTG_CTRL_WRITE);

      when ST_OTG_CTRL_WRITE_DATA =>
        ulpi_o.data <= (others => '0');

      when ST_FUNC_CTRL_WRITE_CMD =>
        ulpi_o.data <= ulpi_cmd_reg_write(ULPI_REG_FUNC_CTRL_WRITE);

      when ST_FUNC_CTRL_WRITE_DATA =>
        ulpi_o.data <= (others => '0');
        ulpi_o.data(6) <= to_logic(not r.suspend);
        ulpi_o.data(4 downto 3) <= to_logic(r.op_mode);
        ulpi_o.data(2) <= to_logic(r.term_select);
        ulpi_o.data(0) <= to_logic(r.xcvr_select);

      when ST_TX_START =>
        utmi_data_o.tx_ready <= '1';

      when ST_TX_PID_SEND =>
        utmi_data_o.tx_ready <= to_logic(r.tx_data_fillness < 2 and not r.tx_data_over);
        ulpi_o.data <= ulpi_cmd_transmit(r.tx_pid);

      when ST_TX_FORWARD =>
        utmi_data_o.tx_ready <= to_logic(r.tx_data_fillness < 2 and not r.tx_data_over);
        ulpi_o.data <= r.tx_data(0);
        
      when ST_TX_OVER =>
        ulpi_o.stp <= '1';
        ulpi_o.data <= ulpi_cmd_noop;
    end case;
    
  end process;
  
end architecture;
