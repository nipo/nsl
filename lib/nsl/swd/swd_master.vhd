library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;
use nsl.swd.all;

entity swd_master is
  port (
    p_clk      : in  std_logic;
    p_resetn   : in  std_logic;

    p_in_val    : in fifo_framed_cmd;
    p_in_ack    : out fifo_framed_rsp;
    p_out_val   : out fifo_framed_cmd;
    p_out_ack   : in fifo_framed_rsp;

    p_swclk    : out std_logic;
    p_swdio_i  : in  std_logic;
    p_swdio_o  : out std_logic;
    p_swdio_oe : out std_logic
  );
end entity; 

architecture rtl of swd_master is
  constant SWD_STATUS_ACK: std_ulogic_vector(2 downto 0):= "001";
  constant SWD_STATUS_WAIT: std_ulogic_vector(2 downto 0):= "010";
  constant SWD_STATUS_FAULT: std_ulogic_vector(2 downto 0):= "100";

  type state_t is (
    STATE_ROUTE_GET,
    STATE_ROUTE_PUT,
    STATE_TAG_GET,
    STATE_TAG_PUT,
    STATE_CMD_GET,
    STATE_CMD_CHECK,
    STATE_CMD_PREPARE,
    STATE_CMD_DATA_GET,
    STATE_CMD_SHIFT,
    STATE_R0,
    STATE_ACK_OK,
    STATE_ACK_WAIT,
    STATE_ACK_FAULT,
    STATE_R1,
    STATE_DATA_SHIFT,
    STATE_DATA_SHIFT_PAR,
    STATE_R2,
    STATE_RESULT_STATUS,
    STATE_DATA_SET,
    STATE_RESET_START,
    STATE_RESET_SHIFT1,
    STATE_RESET_SHIFT2
  );

  type regs_t is record
    ack           : std_ulogic_vector(2 downto 0);
    cmd_a         : std_ulogic_vector(1 downto 0);
    cmd_ad        : std_ulogic;
    cmd_read      : std_ulogic;
    cmd_reset     : std_ulogic;
    command       : std_ulogic_vector(7 downto 0);
    data          : std_ulogic_vector(31 downto 0);
    data_par      : std_logic;
    has_more      : std_logic;
    state         : state_t;
    status        : std_ulogic_vector(3 downto 0);
    to_shift_left : integer range 0 to 31;
  end record;

  signal r, rin: regs_t;

  function Ternary_Logic(T : Boolean; X, Y : std_logic) return std_ulogic is
  begin
    if T then return X; else return Y; end if;
  end function;
begin
  reg: process (p_clk)
    begin
    if rising_edge(p_clk) then
      if p_resetn = '0' then
        r.state <= STATE_ROUTE_GET;
      else
        r <= rin;
      end if;
    end if;
  end process;

  transition: process (r, p_in_val, p_out_ack, p_swdio_i)
  begin
    rin <= r;

    case r.state is
      when STATE_ROUTE_GET =>
        if p_in_val.val = '1' then
          rin.data(7 downto 0) <= p_in_val.data(3 downto 0) & p_in_val.data(7 downto 4);
          rin.state <= STATE_ROUTE_PUT;
        end if;

      when STATE_ROUTE_PUT =>
        if p_out_ack.ack = '1' then
          rin.state <= STATE_TAG_GET;
        end if;

      when STATE_TAG_GET =>
        if p_in_val.val = '1' then
          rin.data(7 downto 0) <= p_in_val.data;
          rin.state <= STATE_TAG_PUT;
        end if;

      when STATE_TAG_PUT =>
        if p_out_ack.ack = '1' then
          rin.state <= STATE_CMD_GET;
        end if;

      when STATE_CMD_GET =>
        if p_in_val.val = '1' then
          rin.state <= STATE_CMD_CHECK;
          rin.cmd_reset <= p_in_val.data(5) and not p_in_val.data(4);
          rin.cmd_read <= p_in_val.data(3);
          rin.cmd_ad <= p_in_val.data(2);
          rin.cmd_a <= p_in_val.data(1 downto 0);
          rin.has_more <= p_in_val.more;
        end if;

      when STATE_CMD_CHECK =>
        if r.cmd_reset = '1' then
          rin.state <= STATE_RESET_START;
        elsif r.cmd_read = '1' then
          rin.state <= STATE_CMD_PREPARE;
        elsif p_in_val.val = '1' then
          rin.state <= STATE_CMD_DATA_GET;
        end if;

      when STATE_CMD_DATA_GET =>
        if p_in_val.val = '1' then
          rin.data <= p_in_val.data & r.data(31 downto 8);
          if r.to_shift_left = 0 then
            rin.state <= STATE_CMD_PREPARE;
            rin.has_more <= p_in_val.more;
          end if;
        end if;

      when STATE_CMD_PREPARE =>
        rin.command <= "10" & (((r.cmd_read xor r.cmd_ad) xor r.cmd_a(1)) xor r.cmd_a(0)) & r.cmd_a(1) & r.cmd_a(0) & r.cmd_read & r.cmd_ad & '1';
        rin.data_par <= '0';
        rin.state <= STATE_CMD_SHIFT;

      when STATE_CMD_SHIFT =>
        rin.command <= '0' & r.command(7 downto 1);
        if r.to_shift_left = 0 then
          rin.state <= STATE_R0;
        end if;

      when STATE_R0 =>
        rin.state <= STATE_ACK_OK;

      when STATE_ACK_OK =>
        rin.state <= STATE_ACK_WAIT;

      when STATE_ACK_WAIT =>
        rin.state <= STATE_ACK_FAULT;

      when STATE_ACK_FAULT =>
        if p_swdio_i & r.ack(2 downto 1) = SWD_STATUS_WAIT then
          rin.state <= STATE_CMD_PREPARE;
        elsif p_swdio_i & r.ack(2 downto 1) = SWD_STATUS_ACK and r.cmd_read = '1' then
          rin.state <= STATE_DATA_SHIFT;
        else
          rin.state <= STATE_R1;
        end if;

      when STATE_R1 =>
        -- Return cycle between ACK and WData (only in ACKed write transactions)
        if r.ack = SWD_STATUS_ACK then
          rin.state <= STATE_DATA_SHIFT;
          rin.status <= SWD_RSP_WRITE_OK;
        elsif r.ack = SWD_STATUS_FAULT then
          rin.status <= SWD_RSP_FAULT;
          rin.state <= STATE_RESULT_STATUS;
        else
          rin.status <= SWD_RSP_OTHER;
          rin.state <= STATE_RESULT_STATUS;
        end if;

      when STATE_DATA_SHIFT =>
        rin.data <= p_swdio_i & r.data(31 downto 1);
        if r.cmd_read = '1' then
          rin.data_par <= r.data_par xor p_swdio_i;
        else
          rin.data_par <= r.data_par xor r.data(0);
        end if;

        if r.to_shift_left = 0 then
          rin.state <= STATE_DATA_SHIFT_PAR;
        end if;

      when STATE_DATA_SHIFT_PAR =>
        if r.cmd_read = '1' then
          rin.data_par <= r.data_par xor p_swdio_i;
          rin.state <= STATE_R2;
        else
          rin.state <= STATE_RESULT_STATUS;
        end if;

      when STATE_R2 =>
        -- Return cycle between RData and end of txn (only in ACKed read transactions)
        rin.state <= STATE_RESULT_STATUS;
        if r.ack = SWD_STATUS_ACK then
          if r.data_par /= '0' then
            rin.status <= SWD_RSP_PARITY_ERROR;
          else
            rin.status <= SWD_RSP_READ_OK;
          end if;
        elsif r.ack = SWD_STATUS_FAULT then
          rin.status <= SWD_RSP_FAULT;
        else
          rin.status <= SWD_RSP_OTHER;
        end if;

      when STATE_RESULT_STATUS =>
        if p_out_ack.ack = '1' then
          if (r.cmd_read = '1') and (r.status = SWD_RSP_READ_OK) then
            rin.state <= STATE_DATA_SET;
          elsif r.has_more = '1' then
            rin.state <= STATE_CMD_GET;
          else
            rin.state <= STATE_ROUTE_GET;
          end if;
        end if;

      when STATE_DATA_SET =>
        if p_out_ack.ack = '1' then
          rin.data <= p_in_val.data & r.data(31 downto 8);
          if r.to_shift_left = 0 then
            if r.has_more = '1' then
              rin.state <= STATE_CMD_GET;
            else
              rin.state <= STATE_ROUTE_GET;
            end if;
          end if;
        end if;

      when STATE_RESET_START =>
        rin.status <= SWD_RSP_RESET_DONE;
        rin.state <= STATE_RESET_SHIFT1;

      when STATE_RESET_SHIFT1 =>
        if r.to_shift_left = 0 then
          rin.state <= STATE_RESET_SHIFT2;
        end if;

      when STATE_RESET_SHIFT2 =>
        if r.to_shift_left = 0 then
          rin.state <= STATE_RESULT_STATUS;
        end if;

      when others =>
        null;
    end case;

    case r.state is
      when STATE_CMD_SHIFT | STATE_DATA_SHIFT | STATE_RESET_SHIFT1 | STATE_RESET_SHIFT2
        | STATE_DATA_SET | STATE_CMD_DATA_GET =>
        rin.to_shift_left <= (r.to_shift_left - 1) mod 32;
      when STATE_RESET_START =>
        rin.to_shift_left <= 20;
      when STATE_RESULT_STATUS =>
        rin.to_shift_left <= 3;
      when STATE_CMD_PREPARE =>
        rin.to_shift_left <= 7;
      when STATE_CMD_CHECK =>
        if r.cmd_read = '1' then
          rin.to_shift_left <= 7;
        else
          rin.to_shift_left <= 3;
        end if;
      when STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT | STATE_R1 | STATE_ROUTE_GET | STATE_TAG_GET =>
        rin.to_shift_left <= 31;
      when others =>
        null;
    end case;

    case r.state is
      when STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT =>
        rin.ack <= p_swdio_i & r.ack(2 downto 1);
      when others =>
        null;
    end case;
  end process;
  
  p_swclk <= p_clk;

  swd_moore: process (p_clk) is
  begin
    if falling_edge(p_clk) then
      case r.state is
        when STATE_R0 | STATE_R1 | STATE_R2 | STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT =>
          p_swdio_oe <= '0';

        when STATE_DATA_SHIFT | STATE_DATA_SHIFT_PAR =>
          p_swdio_oe <= not r.cmd_read;

        when others =>
          p_swdio_oe <= '1';
      end case;

      case r.state is
        when STATE_R0 | STATE_R1 | STATE_R2 | STATE_ACK_OK | STATE_ACK_WAIT | STATE_ACK_FAULT =>
          p_swdio_o <= 'X';

        when STATE_CMD_SHIFT =>
          p_swdio_o <= r.command(0);

        when STATE_DATA_SHIFT =>
          if r.cmd_read = '1' then
            p_swdio_o <= 'X';
          else
            p_swdio_o <= r.data(0);
          end if;

        when STATE_DATA_SHIFT_PAR =>
          if r.cmd_read = '1' then
            p_swdio_o <= 'X';
          else
            p_swdio_o <= r.data_par;
          end if;

        when STATE_RESET_SHIFT1 | STATE_RESET_SHIFT2 =>
          p_swdio_o <= '1';

        when others =>
          p_swdio_o <= '0';
      end case;
    end if;
  end process;
  
  noc_moore: process (r) is
  begin
    case r.state is
      when STATE_ROUTE_GET | STATE_TAG_GET | STATE_CMD_GET | STATE_CMD_DATA_GET =>
        p_in_ack.ack <= '1';
      when others =>
        p_in_ack.ack <= '0';
    end case;

    case r.state is
      when STATE_RESULT_STATUS =>
        p_out_val.data <= "0000" & r.status;
        p_out_val.val <= '1';
        if r.cmd_read = '1' and r.ack(0) = '1' then
          p_out_val.more <= '1';
        else
          p_out_val.more <= r.has_more;
        end if;

      when STATE_DATA_SET | STATE_ROUTE_PUT | STATE_TAG_PUT =>
        p_out_val.data <= r.data(7 downto 0);
        p_out_val.val <= '1';
        if r.to_shift_left /= 0 then
          p_out_val.more <= '1';
        else
          p_out_val.more <= r.has_more;
        end if;

      when others =>
        p_out_val.data <= (others => 'X');
        p_out_val.val <= '0';
        p_out_val.more <= 'X';
    end case;
  end process;
end architecture;

