library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart;
use nsl_uart.serdes.all;

entity uart_rx is
  generic(
    bit_count_c : natural;
    stop_count_c : natural range 1 to 2;
    parity_c : parity_t;
    rts_active_c : std_ulogic := '0'
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    divisor_i   : in unsigned;
    
    uart_i      : in std_ulogic;
    rts_o       : out std_ulogic;

    data_o      : out std_ulogic_vector(bit_count_c-1 downto 0);
    valid_o     : out std_ulogic;
    ready_i     : in std_ulogic := '1';
    parity_error_o : out std_ulogic;
    break_o     : out std_ulogic
    );
end entity;

architecture beh of uart_rx is

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
    div_ctr, divisor: unsigned(divisor_i'length-1 downto 0);

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

  transition: process(r, uart_i, divisor_i, ready_i)
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
        rin.divisor <= divisor_i;
        if uart_i = '0' then
          rin.state <= ST_START;
          rin.div_ctr <= shift_right(r.divisor, 1);
        end if;

      when ST_START =>
        if r.div_ctr /= 0 then
          rin.div_ctr <= r.div_ctr - 1;
        else
          rin.state <= ST_SHIFT;
          rin.div_ctr <= r.divisor;
          rin.bit_ctr <= bit_count_c-1;
          rin.shreg <= (others => '-');
          rin.all_zero <= true;
          case parity_c is
            when PARITY_ODD =>
              rin.parity <= '0';

            when others =>
              rin.parity <= '1';
          end case;
        end if;
        
      when ST_SHIFT =>
        if r.div_ctr /= 0 then
          rin.div_ctr <= r.div_ctr - 1;
        else
          rin.div_ctr <= r.divisor;
          rin.parity <= uart_i xor r.parity;
          rin.shreg <= uart_i & r.shreg(r.shreg'left downto 1);
          
          if r.bit_ctr /= 0 then
            rin.bit_ctr <= r.bit_ctr - 1;
          elsif parity_c /= PARITY_NONE then
            rin.state <= ST_PARITY;
            rin.data <= uart_i & r.shreg(r.shreg'left downto 1);
          else
            rin.state <= ST_STOP;
            rin.parity_ok <= '1';
            rin.valid <= '1';
            rin.data <= uart_i & r.shreg(r.shreg'left downto 1);
          end if;
        end if;

      when ST_PARITY =>
        if r.div_ctr /= 0 then
          rin.div_ctr <= r.div_ctr - 1;
        else
          rin.state <= ST_STOP;
          rin.div_ctr <= r.divisor;
          rin.parity_ok <= uart_i xor r.parity;
          rin.valid <= '1';
          rin.data <= r.shreg;
        end if;

      when ST_STOP =>
        if r.div_ctr /= 0 then
          rin.div_ctr <= r.div_ctr - 1;
        elsif r.all_zero then
          rin.state <= ST_BREAK_WAIT;
        else
          rin.state <= ST_IDLE;
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
  parity_error_o <= '0' when parity_c = PARITY_NONE else not r.parity_ok;
  rts_o <= rts_active_c when (r.ready = '1' or r.valid = '0') else not rts_active_c;

end architecture;
