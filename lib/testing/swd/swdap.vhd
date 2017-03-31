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

  signal r_cmd_a, s_cmd_a : unsigned(1 downto 0);
  signal r_cmd_ad, s_cmd_ad : std_logic;
  signal r_cmd_ok, s_cmd_ok : std_logic;
  signal r_cmd_rw, s_cmd_rw : std_logic;
  signal r_ready, s_ready : std_logic;
  signal r_data, s_data : unsigned(31 downto 0);
  signal r_data_par, s_data_par : std_logic;
  signal r_reset_counter, s_reset_counter : natural;
  signal r_state, s_state : state_t;
  signal r_to_shift, s_to_shift : integer;

  signal s_swdio_oe : std_logic;
  signal s_swdio_out : std_logic;
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
  reg: process (p_swclk, s_reset) is
  begin
    if rising_edge(p_swclk) then
      if s_reset = '1' then
        r_cmd_a <= "00";
        r_cmd_ad <= '0';
        r_cmd_ok <= '0';
        r_cmd_rw <= '0';
        r_data <= (others => '0');
        r_data_par <= '0';
        r_state <= STATE_IDLE;
        r_to_shift <= 0;
        r_ready <= '0';
      else
        r_cmd_a <= s_cmd_a;
        r_cmd_ad <= s_cmd_ad;
        r_cmd_ok <= s_cmd_ok;
        r_cmd_rw <= s_cmd_rw;
        r_data <= s_data;
        r_data_par <= s_data_par;
        r_state <= s_state;
        r_to_shift <= s_to_shift;
        r_ready <= s_ready;
      end if;
    end if;
  end process;

  reset: process(p_swclk)
  begin
    if rising_edge(p_swclk) then
      if p_swdio = '0' then
        r_reset_counter <= 50;
      elsif r_reset_counter /= 0 then
        r_reset_counter <= r_reset_counter - 1;
      end if;
    end if;
  end process;

  ready: process(r_state, p_dap_ready)
  begin
    case r_state is
      when STATE_R0 =>
        s_ready <= p_dap_ready;

      when others =>
        s_ready <= r_ready;
    end case;
  end process;

  state: process(r_state, p_swdio, r_cmd_ok, p_dap_ready, r_cmd_rw, r_to_shift)
  begin
    s_state <= r_state;
    
    case r_state is
      when STATE_IDLE =>
        if p_swdio = '1' then
          s_state <= STATE_CMD_AD;
        end if;

      when STATE_CMD_AD =>
        s_state <= STATE_CMD_RW;

      when STATE_CMD_RW =>
        s_state <= STATE_CMD_A0;

      when STATE_CMD_A0 =>
        s_state <= STATE_CMD_A1;

      when STATE_CMD_A1 =>
        s_state <= STATE_CMD_PAR;

      when STATE_CMD_PAR =>
        s_state <= STATE_CMD_STOP;

      when STATE_CMD_STOP =>
        if p_swdio = '1' then
          s_state <= STATE_IDLE;
        else
          s_state <= STATE_CMD_PARK;
        end if;

      when STATE_CMD_PARK =>
        if p_swdio = '0' then
          s_state <= STATE_IDLE;
        else
          s_state <= STATE_R0;
        end if;

      when STATE_ACK_OK =>
        s_state <= STATE_ACK_WAIT;

      when STATE_ACK_WAIT =>
        s_state <= STATE_ACK_FAULT;

      when STATE_R1 =>
        s_state <= STATE_DATA;

      when STATE_R0 =>
        if r_cmd_ok = '1' then
          s_state <= STATE_ACK_OK;
        else
          s_state <= STATE_IDLE;
        end if;

      when STATE_ACK_FAULT =>
        if r_cmd_ok = '1' and r_ready = '1' then
          if r_cmd_rw = '1' then
            s_state <= STATE_DATA;
          else
            s_state <= STATE_R1;
          end if;
        else
          s_state <= STATE_IDLE;
        end if;

      when STATE_DATA =>
        if r_to_shift = 0 then
          s_state <= STATE_DATA_PAR;
        end if;

      when STATE_DATA_PAR =>
        if r_cmd_rw = '1' then
          s_state <= STATE_R2;
        else
          s_state <= STATE_IDLE;
        end if;

      when STATE_R2 =>
        s_state <= STATE_IDLE;

      when others =>
        null;
    end case;
  end process;

  par: process(r_state, r_data_par, r_data)
  begin
    s_data_par <= r_data_par;
  
    case r_state is
      when STATE_DATA =>
        s_data_par <= r_data_par xor r_data(0);

      when others =>
        s_data_par <= '0';
    end case;
  end process;

  data: process(r_state, r_data, p_swdio, r_to_shift, r_cmd_rw)
  begin
    s_data <= r_data;
    s_to_shift <= r_to_shift;

    case r_state is
      when STATE_DATA =>
        s_data <= p_swdio & r_data(1 + 30 downto 1);
        s_to_shift <= r_to_shift - 1;

      when STATE_ACK_FAULT =>
        s_to_shift <= 31;
        if r_cmd_rw = '1' then
          s_data <= p_dap_rdata;
        end if;

      when others =>
        null;
    end case;
  end process;

  cmd_in: process(p_swdio, r_state)
  begin
    s_cmd_ad <= r_cmd_ad;
    s_cmd_rw <= r_cmd_rw;
    s_cmd_a <= r_cmd_a;

    case r_state is
      when STATE_CMD_AD =>
        s_cmd_ad <= p_swdio;

      when STATE_CMD_RW =>
        s_cmd_rw <= p_swdio;

      when STATE_CMD_A0 =>
        s_cmd_a(0) <= p_swdio;

      when STATE_CMD_A1 =>
        s_cmd_a(1) <= p_swdio;

      when others =>
        null;
    end case;
  end process;

  cmd_ok: process(r_state, p_swdio, r_cmd_ad, r_cmd_rw, r_cmd_a, r_cmd_ok)
  begin
    s_cmd_ok <= r_cmd_ok;

    case r_state is
      when STATE_IDLE =>
        s_cmd_ok <= '1';

      when STATE_CMD_PAR =>
        s_cmd_ok <= not (p_swdio xor r_cmd_ad xor r_cmd_rw xor r_cmd_a(0) xor r_cmd_a(1));

      when STATE_CMD_STOP =>
        s_cmd_ok <= r_cmd_ok and not p_swdio;

      when STATE_CMD_PARK =>
        s_cmd_ok <= r_cmd_ok and p_swdio;

      when others =>
        null;
    end case;
  end process;

  s_reset <= '1' when r_reset_counter = 0 else '0';
  p_swdio <= s_swdio_out when s_swdio_oe = '1' else 'Z';

  moore_dap: process (r_cmd_ad, r_cmd_a, r_data, r_cmd_rw, r_data_par, p_swdio, r_cmd_rw, r_state) is
  begin
    p_dap_ad <= r_cmd_ad;
    p_dap_a <= r_cmd_a;
    p_dap_wdata <= r_data;

    case r_state is
      when STATE_DATA_PAR =>
        p_dap_wen <= not r_cmd_rw and (r_data_par xnor p_swdio);
        p_dap_ren <= r_cmd_rw;

      when others =>
        p_dap_wen <= '0';
        p_dap_ren <= '0';
    end case;
  end process;

  swd_io: process (r_state, r_cmd_ok, r_ready, r_data, r_data_par, r_cmd_rw) is
  begin
    case r_state is
      when STATE_ACK_OK =>
        s_swdio_out <= r_cmd_ok and r_ready;
        s_swdio_oe <= '1';

      when STATE_ACK_WAIT =>
        s_swdio_out <= r_cmd_ok and not r_ready;
        s_swdio_oe <= '1';

      when STATE_ACK_FAULT =>
        s_swdio_out <= not r_cmd_ok;
        s_swdio_oe <= '1';

      when STATE_DATA =>
        s_swdio_out <= r_data(0);
        s_swdio_oe <= r_cmd_rw;

      when STATE_DATA_PAR =>
        s_swdio_out <= r_data_par;
        s_swdio_oe <= r_cmd_rw;

      when others =>
        s_swdio_out <= 'U';
        s_swdio_oe <= '0';
    end case;
  end process;

end architecture;

