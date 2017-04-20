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
    STATE_START,
    STATE_SHIFT,
    STATE_STOP,
    STATE_OUT
    );

  type regs_t is record
    data: std_ulogic_vector(7 downto 0);
    state: state_t;
    bit_ctr: integer range 0 to 7;
    clk_div: integer range 0 to p_clk_rate-1;
    high_count: integer range 0 to p_clk_rate / baud_rate + 1;
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
        rin.state <= STATE_START;
        rin.clk_div <= 0;
      end if;
    elsif r.state = STATE_OUT then
      rin.state <= STATE_IDLE;
    elsif r.clk_div < p_clk_rate - baud_rate then
      rin.clk_div <= r.clk_div + baud_rate;
      if p_uart_rx = '1' then
        rin.high_count <= r.high_count + 1;
      end if;
    else
      rin.clk_div <= r.clk_div - (p_clk_rate - baud_rate);

      case r.state is
        when STATE_IDLE | STATE_OUT =>
          null;

        when STATE_STOP =>
          rin.state <= STATE_OUT;

        when STATE_START =>
          rin.bit_ctr <= 0;
          rin.state <= STATE_SHIFT;
          rin.high_count <= 0;

        when STATE_SHIFT =>
          rin.high_count <= 0;
          if r.high_count > p_clk_rate / baud_rate / 2 then
            rin.data <= "1" & r.data(7 downto 1);
          else
            rin.data <= "0" & r.data(7 downto 1);
          end if;
          
          if r.bit_ctr = 7 then
            rin.state <= STATE_STOP;
            rin.clk_div <= p_clk_rate / 4;
          else
            rin.bit_ctr <= r.bit_ctr + 1;
          end if;
      end case;
    end if;
  end process;

  p_data_val <= '1' when r.state = STATE_OUT else '0';
  p_data <= r.data;
  
end architecture;
