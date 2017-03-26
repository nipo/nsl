library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity swdap is
  port (
    p_swclk : in std_logic;
    p_swdio : inout std_logic;

    p_dap_a : out unsigned(1 downto 0);
    p_dap_ad : out std_logic;
    p_dap_rdata : in unsigned(31 downto 0);
    p_dap_ready : in std_logic;
    p_dap_ren : out std_logic;
    p_dap_wdata : out unsigned(31 downto 0);
    p_dap_wen : out std_logic
  );
end entity; 

architecture rtl of swdap is

  type state_t is (
    STATE_IDLE,
    STATE_CMD_AD,
    STATE_CMD_RW,
    STATE_CMD_A0,
    STATE_CMD_A1,
    STATE_CMD_PAR,
    STATE_CMD_STOP,
    STATE_CMD_PARK,
    STATE_R0,
    STATE_ACK_OK,
    STATE_ACK_WAIT,
    STATE_ACK_FAULT,
    STATE_R1,
    STATE_DATA,
    STATE_DATA_PAR,
    STATE_R2
    );

  signal r_cmd_a : unsigned(1 downto 0);
  signal r_cmd_ad : std_logic;
  signal r_cmd_ok : std_logic;
  signal r_cmd_rw : std_logic;
  signal r_data : unsigned(31 downto 0);
  signal r_data_par : std_logic;
  signal r_reset_counter : natural range 0 to 50;
  signal r_state : state_t;
  signal r_swdio_oe : std_logic;
  signal r_swdio_out : std_logic;
  signal r_to_shift : natural range 0 to 31;
  signal s_reset : std_logic;
  
  function Boolean_To_Logic(B : Boolean) return std_logic is
  begin
    if B then
      return '1';
    else
      return '0';
    end if;
  end function;
begin
  transition: process (p_swclk) is
  begin
    if rising_edge(p_swclk) then
      if p_swdio = '0' then
        r_reset_counter <= 50;
      elsif r_reset_counter /= 0 then
        r_reset_counter <= r_reset_counter - 1;
      end if;

      if s_reset = '1' then
        r_state <= STATE_IDLE;
      else
        case r_state is
          when STATE_IDLE =>
            if p_swdio = '1' then
              r_state <= STATE_CMD_AD;
            end if;

          when STATE_CMD_AD =>
            r_state <= STATE_CMD_RW;

          when STATE_CMD_RW =>
            r_state <= STATE_CMD_A0;

          when STATE_CMD_A0 =>
            r_state <= STATE_CMD_A1;

          when STATE_CMD_A1 =>
            r_state <= STATE_CMD_PAR;

          when STATE_CMD_PAR =>
            r_state <= STATE_CMD_STOP;

          when STATE_CMD_STOP =>
            r_state <= STATE_CMD_PARK;

          when STATE_CMD_PARK =>
            r_state <= STATE_R0;

          when STATE_ACK_OK =>
            r_state <= STATE_ACK_WAIT;

          when STATE_ACK_WAIT =>
            r_state <= STATE_ACK_FAULT;

          when STATE_R1 =>
            r_state <= STATE_DATA;

          when STATE_R0 =>
            if r_cmd_ok = '1' then
              r_state <= STATE_ACK_OK;
            else
              r_state <= STATE_IDLE;
            end if;

          when STATE_ACK_FAULT =>
            if r_cmd_ok = '1' and p_dap_ready = '1' then
              if r_cmd_rw = '1' then
                r_state <= STATE_DATA;
              else
                r_state <= STATE_R1;
              end if;
            else
              r_state <= STATE_IDLE;
            end if;

          when STATE_DATA =>
            if r_to_shift = 0 then
              r_state <= STATE_DATA_PAR;
            end if;

          when STATE_DATA_PAR =>
            if r_cmd_rw = '1' then
              r_state <= STATE_R2;
            else
              r_state <= STATE_IDLE;
            end if;

          when STATE_R2 =>
            r_state <= STATE_IDLE;

          when others =>
            null;
        end case;

        case r_state is
          when others =>
            r_data_par <= '0';

          when STATE_DATA =>
            r_data_par <= r_data_par xor r_data(0);
        end case;

        case r_state is
          when STATE_DATA =>
            r_data <= p_swdio & r_data(1 + 30 downto 1);
            r_to_shift <= r_to_shift - 1;

          when STATE_ACK_FAULT =>
            r_to_shift <= 31;
            if r_cmd_rw = '1' then
              r_data <= p_dap_rdata;
            end if;

          when others =>
            null;
        end case;
      end if;

      if r_state = STATE_CMD_AD then
        r_cmd_ad <= p_swdio;
      end if;

      if r_state = STATE_CMD_RW then
        r_cmd_rw <= p_swdio;
      end if;

      if r_state = STATE_CMD_A0 then
        r_cmd_a(0) <= p_swdio;
      end if;

      if r_state = STATE_CMD_A1 then
        r_cmd_a(1) <= p_swdio;
      end if;

      case r_state is
        when STATE_IDLE =>
          r_cmd_ok <= '1';
        when STATE_CMD_PAR =>
          r_cmd_ok <= not (p_swdio xor r_cmd_ad xor r_cmd_rw xor r_cmd_a(0) xor r_cmd_a(1));
        when STATE_CMD_STOP =>
          r_cmd_ok <= r_cmd_ok and not p_swdio;
        when STATE_CMD_PARK =>
          r_cmd_ok <= r_cmd_ok and p_swdio;
        when others =>
          null;
      end case;
    end if;
  end process;

  p_dap_ad <= r_cmd_ad;
  p_dap_a <= r_cmd_a;
  p_dap_wdata <= r_data;

  s_reset <= '1' when r_reset_counter = 0 else '0';
  p_swdio <= r_swdio_out when r_swdio_oe = '1' else 'Z';

  moore: process (r_cmd_rw, r_state, r_data_par, p_swdio, r_cmd_rw) is
  begin
    if r_state = STATE_DATA_PAR then
      p_dap_wen <= not r_cmd_rw and (r_data_par xnor p_swdio);
    else
      p_dap_wen <= '0';
    end if;

    if r_state = STATE_ACK_FAULT then
      p_dap_ren <= r_cmd_rw;
    else
      p_dap_ren <= '0';
    end if;
  end process;

  swd: process (r_state, r_cmd_ok, p_dap_ready, r_data, r_data_par, r_cmd_rw) is
  begin
    case r_state is
      when STATE_ACK_OK =>
        r_swdio_out <= r_cmd_ok and p_dap_ready;
      when STATE_ACK_WAIT =>
        r_swdio_out <= r_cmd_ok and not p_dap_ready;
      when STATE_ACK_FAULT =>
        r_swdio_out <= not r_cmd_ok;
      when STATE_DATA =>
        r_swdio_out <= r_data(0);
      when STATE_DATA_PAR =>
        r_swdio_out <= r_data_par;
      when others =>
        r_swdio_out <= 'U';
    end case;

    case r_state is
      when STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT =>
        r_swdio_oe <= '1';
      when STATE_DATA | STATE_DATA_PAR =>
        r_swdio_oe <= r_cmd_rw;
      when others =>
        r_swdio_oe <= '0';
    end case;
  end process;

end architecture;

