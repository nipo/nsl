library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_8n1_tx is
  generic(
    p_clk_rate : natural;
    baud_rate : natural
    );
  port(
    p_resetn    : in std_ulogic;
    p_clk       : in std_ulogic;

    p_uart_tx   : out std_ulogic;

    p_data      : in std_ulogic_vector(7 downto 0);
    p_ready     : out std_ulogic;
    p_data_val  : in std_ulogic
    );
end entity;

architecture beh of uart_8n1_tx is

  type state_t is (
    STATE_IDLE,
    STATE_START,
    STATE_SHIFT,
    STATE_STOP
    );

  type regs_t is record
    data: std_ulogic_vector(7 downto 0);
    state: state_t;
    bit_ctr: natural range 0 to 7;
    clk_div: natural range 0 to p_clk_rate-1;
  end record;
  
  signal r, rin: regs_t;
  
begin

  regs: process (p_resetn, p_clk)
  begin
    if p_resetn = '0' then
      r.state <= STATE_IDLE;
      r.clk_div <= 0;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_data, p_data_val)
  begin
    rin <= r;

    if r.state = STATE_IDLE then
      if p_data_val = '1' then
        rin.state <= STATE_START;
        rin.data <= p_data;
      end if;
    elsif r.clk_div < p_clk_rate - baud_rate then
      rin.clk_div <= r.clk_div + baud_rate;
    else
      rin.clk_div <= r.clk_div + baud_rate - p_clk_rate;

      case r.state is
        when STATE_IDLE =>
          null;

        when STATE_STOP =>
          rin.bit_ctr <= 7;
          rin.state <= STATE_IDLE;

        when STATE_START =>
          rin.state <= STATE_SHIFT;
          rin.bit_ctr <= 7;

        when STATE_SHIFT =>
          if r.bit_ctr = 0 then
            rin.state <= STATE_STOP;
          else
            rin.bit_ctr <= r.bit_ctr - 1;
          end if;
      end case;
    end if;
  end process;

  moore: process(r, p_resetn)
  begin
    case r.state is
      when STATE_IDLE =>
        p_uart_tx <= '1';
        p_ready <= p_resetn;

      when STATE_STOP =>
        p_uart_tx <= '1';
        p_ready <= '0';

      when STATE_START =>
        p_uart_tx <= '0';
        p_ready <= '0';

      when STATE_SHIFT =>
        p_uart_tx <= r.data(7 - r.bit_ctr);
        p_ready <= '0';

    end case;
  end process;
  
end architecture;
