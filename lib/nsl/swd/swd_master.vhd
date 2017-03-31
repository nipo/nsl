library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.noc.all;

entity swd_master is
  port (
    p_clk      : in  std_logic;
    p_resetn   : in  std_logic;

    p_in_val    : in noc_cmd;
    p_in_ack    : out noc_rsp;
    p_out_val   : out noc_cmd;
    p_out_ack   : in noc_rsp;

    p_swclk    : out std_logic;
    p_swdio_i  : in  std_logic;
    p_swdio_o  : out std_logic;
    p_swdio_oe : out std_logic
  );
end entity; 

architecture rtl of swd_master is
  type state_type is (
    STATE_ACK_FAULT,
    STATE_ACK_OK,
    STATE_ACK_WAIT,
    STATE_CMD_CHECK,
    STATE_CMD_PREPARE,
    STATE_DATA_GET,
    STATE_DATA_SET,
    STATE_IDLE,
    STATE_R0,
    STATE_R1,
    STATE_R2,
    STATE_RESET_START,
    STATE_RESULT_STATUS,
    STATE_SHIFT_CMD,
    STATE_SHIFT_DATA,
    STATE_SHIFT_DATA_PAR,
    STATE_SHIFT_RESET1,
    STATE_SHIFT_RESET2
  );


  signal r_ack, s_ack                     : std_ulogic_vector(2 downto 0);
  signal r_cmd_a, s_cmd_a                 : std_ulogic_vector(1 downto 0);
  signal r_cmd_ad, s_cmd_ad               : std_ulogic;
  signal r_cmd_read, s_cmd_read           : std_ulogic;
  signal r_cmd_reset, s_cmd_reset         : std_ulogic;
  signal r_command, s_command             : std_ulogic_vector(7 downto 0);
  signal r_data, s_data                   : std_ulogic_vector(31 downto 0);
  signal r_data_par, s_data_par           : std_logic;
  signal r_has_more, s_has_more           : std_logic;
  signal r_state, s_state                 : state_type;
  signal r_status, s_status               : std_ulogic_vector(3 downto 0);
  signal r_to_shift_left, s_to_shift_left : integer range 0 to 31;

  function Ternary_Logic(T : Boolean; X, Y : std_logic) return std_ulogic is
  begin
    if T then return X; else return Y; end if;
  end function;
begin
  reg: process (p_clk)
    begin
    if rising_edge(p_clk) then
      if p_resetn = '0' then
        r_cmd_reset <= '0';
        r_cmd_read <= '0';
        r_cmd_ad <= '0';
        r_cmd_a <= (others => '0');
        r_state <= STATE_IDLE;
        r_to_shift_left <= 0;
        r_status <= (others => '0');
        r_data <= (others => '0');
        r_command <= (others => '0');
        r_data_par <= '0';
        r_has_more <= '0';
        r_ack <= (others => '0');
      else
        r_cmd_reset <= s_cmd_reset;
        r_cmd_read <= s_cmd_read;
        r_cmd_ad <= s_cmd_ad;
        r_cmd_a <= s_cmd_a;
        r_state <= s_state;
        r_to_shift_left <= s_to_shift_left;
        r_status <= s_status;
        r_data <= s_data;
        r_command <= s_command;
        r_data_par <= s_data_par;
        r_has_more <= s_has_more;
        r_ack <= s_ack;
      end if;
    end if;
  end process;

  state: process (r_state, p_in_val.val, p_out_ack.ack,
                  p_swdio_i, r_to_shift_left,
                  r_cmd_reset, r_cmd_read, r_status)
  begin
    s_state <= r_state;

    case r_state is
      when STATE_IDLE =>
        if p_in_val.val = '1' then
          s_state <= STATE_CMD_CHECK;
        end if;

      when STATE_CMD_CHECK =>
        if r_cmd_reset = '1' then
          s_state <= STATE_RESET_START;
        elsif r_cmd_read = '1' then
          s_state <= STATE_CMD_PREPARE;
        elsif p_in_val.val = '1' then
          s_state <= STATE_DATA_GET;
        end if;

      when STATE_DATA_GET =>
        if (p_in_val.val = '1') and (r_to_shift_left = 0) then
          s_state <= STATE_CMD_PREPARE;
        end if;

      when STATE_CMD_PREPARE =>
        s_state <= STATE_SHIFT_CMD;

      when STATE_SHIFT_CMD =>
        if r_to_shift_left = 0 then
          s_state <= STATE_R0;
        end if;

      when STATE_R0 =>
        s_state <= STATE_ACK_OK;

      when STATE_ACK_OK =>
        s_state <= STATE_ACK_WAIT;

      when STATE_ACK_WAIT =>
        s_state <= STATE_ACK_FAULT;

      when STATE_ACK_FAULT =>
        if p_swdio_i & r_ack(2 downto 1) = "010" then
          s_state <= STATE_CMD_PREPARE;
        elsif p_swdio_i & r_ack(2 downto 1) = "001" and r_cmd_read = '1' then
          s_state <= STATE_SHIFT_DATA;
        else
          s_state <= STATE_R1;
        end if;

      when STATE_R1 =>
        if r_ack = "001" then
          s_state <= STATE_SHIFT_DATA;
        else
          s_state <= STATE_RESULT_STATUS;
        end if;

      when STATE_SHIFT_DATA =>
        if r_to_shift_left = 0 then
          s_state <= STATE_SHIFT_DATA_PAR;
        end if;

      when STATE_SHIFT_DATA_PAR =>
        if r_cmd_read = '1' then
          s_state <= STATE_R2;
        else
          s_state <= STATE_RESULT_STATUS;
        end if;

      when STATE_R2 =>
        s_state <= STATE_RESULT_STATUS;

      when STATE_RESULT_STATUS =>
        if p_out_ack.ack = '1' then
          if (r_cmd_read = '1') and r_ack(0) = '1' then
            s_state <= STATE_DATA_SET;
          else
            s_state <= STATE_IDLE;
          end if;
        end if;

      when STATE_DATA_SET =>
        if (p_out_ack.ack = '1') and (r_to_shift_left = 0) then
          s_state <= STATE_IDLE;
        end if;

      when STATE_RESET_START =>
        s_state <= STATE_SHIFT_RESET1;

      when STATE_SHIFT_RESET1 =>
        if r_to_shift_left = 0 then
          s_state <= STATE_SHIFT_RESET2;
        end if;

      when STATE_SHIFT_RESET2 =>
        if r_to_shift_left = 0 then
          s_state <= STATE_RESULT_STATUS;
        end if;

      when others =>
        null;
    end case;
  end process;

  to_shift_left: process (r_state, r_to_shift_left)
  begin
    s_to_shift_left <= r_to_shift_left;

    case r_state is
      when STATE_SHIFT_CMD | STATE_SHIFT_DATA | STATE_SHIFT_RESET1 | STATE_SHIFT_RESET2
        | STATE_DATA_SET | STATE_DATA_GET =>
        s_to_shift_left <= (r_to_shift_left - 1) mod 32;
      when STATE_RESET_START =>
        s_to_shift_left <= 20;
      when STATE_RESULT_STATUS =>
        s_to_shift_left <= 3;
      when STATE_CMD_PREPARE =>
        s_to_shift_left <= 7;
      when STATE_CMD_CHECK =>
        if r_cmd_read = '1' then
          s_to_shift_left <= 7;
        else
          s_to_shift_left <= 3;
        end if;
      when STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT | STATE_R1 =>
        s_to_shift_left <= 31;
      when others =>
        null;
    end case;
  end process;

  ack: process(r_state, r_ack, p_swdio_i)
  begin
    case r_state is
      when STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT =>
        s_ack <= p_swdio_i & r_ack(2 downto 1);
      when others =>
        null;
    end case;
  end process;

  cmd: process(r_state, p_in_val.data, p_in_val.val)
  begin
    if (r_state = STATE_IDLE) and (p_in_val.val = '1') then
      s_cmd_reset <= p_in_val.data(5) and not p_in_val.data(4);
      s_cmd_read <= p_in_val.data(3);
      s_cmd_ad <= p_in_val.data(2);
      s_cmd_a <= p_in_val.data(1 downto 0);
    end if;
  end process;

  more: process(r_state, r_has_more, p_in_val.val, p_in_val.more)
  begin
    s_has_more <= r_has_more;
    
    if p_in_val.val = '1' then
      case r_state is
        when STATE_IDLE | STATE_DATA_GET =>
          s_has_more <= p_in_val.more;
        when others =>
          null;
      end case;
    end if;
  end process;
  
  data: process(r_state, r_data, p_in_val.val, p_swdio_i, p_in_val.data)
  begin
    case r_state is
      when STATE_DATA_GET =>
        if p_in_val.val = '1' then
          s_data <= p_in_val.data & r_data(31 downto 8);
        end if;

      when STATE_SHIFT_DATA =>
        s_data <= p_swdio_i & r_data(31 downto 1);

      when STATE_DATA_SET =>
        if p_out_ack.ack = '1' then
          s_data <= p_in_val.data & r_data(31 downto 8);
        end if;

      when others =>
        null;
    end case;
  end process;

  command: process(r_state, r_cmd_read, r_cmd_ad, r_cmd_a, r_command)
  begin
    case r_state is
      when STATE_CMD_PREPARE =>
        s_command <= "10" & (((r_cmd_read xor r_cmd_ad) xor r_cmd_a(1)) xor r_cmd_a(0)) & r_cmd_a(1) & r_cmd_a(0) & r_cmd_read & r_cmd_ad & '1';

      when STATE_SHIFT_CMD =>
        s_command <= '0' & r_command(1 + 6 downto 1);

      when others =>
        null;
    end case;
  end process;

  data_par: process(r_state, r_data_par, r_cmd_read, r_data, p_swdio_i)
  begin
    case r_state is
      when STATE_CMD_PREPARE =>
        s_data_par <= '0';

      when STATE_SHIFT_DATA =>
        s_data_par <= r_data_par xor Ternary_Logic((r_cmd_read = '1'), p_swdio_i, r_data(0));

      when others =>
        null;
    end case;
  end process;

  status: process(r_state, r_cmd_read, r_ack, r_data_par, p_swdio_i)
  begin
    s_status <= r_status;

    case r_state is
      when STATE_R1 =>
        if r_ack = "001" then
          s_status <= r_cmd_read & "000";
        elsif r_ack = "100" then
          s_status <= "0001";
        else
          s_status <= "0010";
        end if;

      when STATE_SHIFT_DATA =>
        if r_ack = "001" then
          s_status <= r_cmd_read & "000";
        elsif r_ack = "100" then
          s_status <= "0001";
        else
          s_status <= "0010";
        end if;

      when STATE_SHIFT_DATA_PAR =>
        if (r_cmd_read = '1') and (r_data_par /= p_swdio_i) then
          s_status <= "0011";
        end if;

      when STATE_RESET_START =>
        s_status <= "0101";

      when others =>
        null;
    end case;
  end process;
  
  p_swclk <= p_clk;

  swd_moore: process (p_clk) is
  begin
    if falling_edge(p_clk) then
      case r_state is
        when STATE_R0 | STATE_R1 | STATE_R2 | STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT =>
          p_swdio_oe <= '0';

        when STATE_SHIFT_DATA | STATE_SHIFT_DATA_PAR =>
          p_swdio_oe <= not r_cmd_read;

        when others =>
          p_swdio_oe <= '1';
      end case;

      case r_state is
        when STATE_R0 | STATE_R1 | STATE_R2 | STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT =>
          p_swdio_o <= 'X';

        when STATE_SHIFT_CMD =>
          p_swdio_o <= r_command(0);

        when STATE_SHIFT_DATA =>
          if r_cmd_read = '1' then
            p_swdio_o <= 'X';
          else
            p_swdio_o <= r_data(0);
          end if;

        when STATE_SHIFT_DATA_PAR =>
          if r_cmd_read = '1' then
            p_swdio_o <= 'X';
          else
            p_swdio_o <= r_data_par;
          end if;

        when STATE_SHIFT_RESET1 | STATE_SHIFT_RESET2 =>
          p_swdio_o <= '1';

        when others =>
          p_swdio_o <= '0';
      end case;
    end if;
  end process;
  
  noc_moore: process (r_state, r_status, r_ack, r_cmd_read, r_to_shift_left, r_has_more, r_data) is
  begin
    case r_state is
      when STATE_IDLE | STATE_DATA_GET =>
        p_in_ack.ack <= '1';

      when others =>
        p_in_ack.ack <= '0';
    end case;

    case r_state is
      when STATE_RESULT_STATUS =>
        p_out_val.data <= "0000" & r_status;
        p_out_val.val <= '1';
        if r_cmd_read = '1' and r_ack(0) = '1' then
          p_out_val.more <= '1';
        else
          p_out_val.more <= r_has_more;
        end if;

      when STATE_DATA_SET =>
        p_out_val.data <= r_data(7 downto 0);
        p_out_val.val <= '1';
        if r_to_shift_left /= 0 then
          p_out_val.more <= '1';
        else
          p_out_val.more <= r_has_more;
        end if;

      when others =>
        p_out_val.data <= (others => 'X');
        p_out_val.val <= '0';
        p_out_val.more <= 'X';
    end case;
  end process;
end architecture;

