library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_8n1_rx is
  generic(
    p_clk_rate : natural;
    baud_rate : natural
    );
  port(
    p_resetn    : in std_ulogic;
    p_clk       : in std_ulogic;

    p_uart_rx   : in std_ulogic;

    p_data      : out std_ulogic_vector(7 downto 0);
    p_data_val  : out std_ulogic
    );
end entity;

architecture beh of uart_8n1_rx is

  type state_t is (
    STATE_IDLE,
    STATE_HALF,
    STATE_SHIFT,
    STATE_STOP,
    STATE_OUT
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

  transition: process(r, p_uart_rx)
  begin
    rin <= r;

    if r.state = STATE_IDLE then
      if p_uart_rx = '0' then
        rin.state <= STATE_HALF;
        rin.clk_div <= p_clk_rate / 2;
      end if;
    elsif r.state = STATE_OUT then
      rin.state <= STATE_IDLE;
    elsif r.clk_div < p_clk_rate - baud_rate then
      rin.clk_div <= r.clk_div + baud_rate;
    else
      rin.clk_div <= r.clk_div - p_clk_rate + baud_rate;

      case r.state is
        when STATE_IDLE | STATE_OUT =>
          null;

        when STATE_STOP =>
          rin.state <= STATE_OUT;

        when STATE_HALF =>
          rin.bit_ctr <= 7;
          rin.state <= STATE_SHIFT;

        when STATE_SHIFT =>
          rin.data(7 - r.bit_ctr) <= p_uart_rx;
          
          if r.bit_ctr = 0 then
            rin.state <= STATE_STOP;
          else
            rin.bit_ctr <= r.bit_ctr - 1;
          end if;
      end case;
    end if;
  end process;

  p_data_val <= '1' when r.state = STATE_OUT else '0';
  p_data <= r.data;
  
end architecture;
