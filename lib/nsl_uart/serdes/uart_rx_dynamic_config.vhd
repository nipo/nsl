library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart;
use nsl_uart.serdes.all;

entity uart_rx_dynamic_config is
  generic(
    bit_count_c : natural
    );
  port(
    clock_i        : in std_ulogic;
    reset_n_i      : in std_ulogic;

    tick_i         : in std_ulogic;

    uart_i         : in std_ulogic;
    rts_o          : out std_ulogic;

    data_o         : out std_ulogic_vector(bit_count_c-1 downto 0);
    valid_o        : out std_ulogic;
    ready_i        : in std_ulogic := '1';
    parity_error_o : out std_ulogic;
    break_o        : out std_ulogic;
    
    stop_count_i   : in natural range 1 to 2;
    parity_i       : in parity_t;
    rts_active_i   : in std_ulogic := '0'
    );
end entity;

architecture beh of uart_rx_dynamic_config is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_START,
    ST_SHIFT,
    ST_PARITY,
    ST_STOP,
    ST_BREAK_WAIT
    );

  type regs_t is record
    shreg: std_ulogic_vector(bit_count_c-1 downto 0);
    parity: std_ulogic;
    all_zero: boolean;
    state: state_t;
    bit_ctr: integer range 0 to bit_count_c-1;
    tick_ctr: unsigned(0 downto 0);

    ready: std_ulogic;
    valid: std_ulogic;
    data: std_ulogic_vector(bit_count_c-1 downto 0);
    parity_ok: std_ulogic;
  end record;
  
  signal r, rin: regs_t;
  
begin

  regs: process (reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, uart_i, tick_i, ready_i, parity_i)
  begin
    rin <= r;

    rin.ready <= ready_i;
    if ready_i = '1' then
      rin.valid <= '0';
    end if;

    if uart_i = '1' then
      rin.all_zero <= false;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if uart_i = '0' then
          -- Start bit detected, wait 1 tick (half bit at 2x baud) to sample at mid-bit
          rin.state <= ST_START;
        end if;

      when ST_START =>
        if tick_i = '1' then
          -- After 1 tick at 2x baud, we're at mid-start-bit
          rin.state <= ST_SHIFT;
          rin.tick_ctr <= "1";
          rin.bit_ctr <= bit_count_c-1;
          rin.shreg <= (others => '-');
          rin.all_zero <= true;
          case parity_i is
            when PARITY_ODD =>
              rin.parity <= '0';

            when others =>
              rin.parity <= '1';
          end case;
        end if;

      when ST_SHIFT =>
        if tick_i = '1' then
          if r.tick_ctr /= 0 then
            rin.tick_ctr <= r.tick_ctr - 1;
          else
            rin.tick_ctr <= "1";
            rin.parity <= uart_i xor r.parity;
            rin.shreg <= uart_i & r.shreg(r.shreg'left downto 1);

            if r.bit_ctr /= 0 then
              rin.bit_ctr <= r.bit_ctr - 1;
            elsif parity_i /= PARITY_NONE then
              rin.state <= ST_PARITY;
              rin.data <= uart_i & r.shreg(r.shreg'left downto 1);
            else
              rin.state <= ST_STOP;
              rin.parity_ok <= '1';
              rin.valid <= '1';
              rin.data <= uart_i & r.shreg(r.shreg'left downto 1);
            end if;
          end if;
        end if;

      when ST_PARITY =>
        if tick_i = '1' then
          if r.tick_ctr /= 0 then
            rin.tick_ctr <= r.tick_ctr - 1;
          else
            rin.tick_ctr <= "1";
            rin.state <= ST_STOP;
            rin.parity_ok <= uart_i xor r.parity;
            rin.valid <= '1';
            rin.data <= r.shreg;
          end if;
        end if;

      when ST_STOP =>
        if tick_i = '1' then
          if r.tick_ctr /= 0 and uart_i /= '1' then
            rin.tick_ctr <= r.tick_ctr - 1;
          elsif r.all_zero then
            rin.state <= ST_BREAK_WAIT;
          else
            rin.state <= ST_IDLE;
          end if;
        end if;

      when ST_BREAK_WAIT =>
        if uart_i = '1' then
          rin.state <= ST_IDLE;
        end if;

    end case;
  end process;

  valid_o <= r.valid;
  data_o <= r.data;
  break_o <= '1' when r.state = ST_BREAK_WAIT else '0';
  parity_error_o <= '0' when parity_i = PARITY_NONE else not r.parity_ok;
  rts_o <= rts_active_i when (r.ready = '1' or r.valid = '0') else not rts_active_i;

end architecture;
