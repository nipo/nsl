library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart, nsl_math;
use nsl_uart.serdes.all;

entity uart_tx is
  generic(
    divisor_width : natural range 1 to 20;
    bit_count_c : natural;
    stop_count_c : natural;
    parity_c : parity_t
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    divisor_i   : in unsigned(divisor_width-1 downto 0);
    
    uart_o      : out std_ulogic;

    data_i      : in std_ulogic_vector(bit_count_c-1 downto 0);
    ready_o     : out std_ulogic;
    valid_i     : in std_ulogic
    );
end entity;

architecture beh of uart_tx is

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_PREPARE,
    ST_SHIFT
    );

  constant shreg_width: natural := bit_count_c+stop_count_c + 2;
  constant stop_par: std_ulogic_vector(stop_count_c + 1 - 1 downto 0) := (others => '1');
  constant parity_bit: natural := bit_count_c + 1;
  constant start: std_ulogic_vector(0 downto 0) := (others => '0');
  
  type regs_t is record
    shreg: std_ulogic_vector(shreg_width-1 downto 0);
    bit_ctr: natural range 0 to shreg_width-1;
    divisor: unsigned(divisor_i'range);
    state: state_t;
  end record;
  
  signal r, rin: regs_t;

  signal s_tick: std_ulogic;
  
begin
  
  regs: process (reset_n_i, clock_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.divisor <= (others => '0');
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition: process(r, data_i, valid_i, divisor_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if valid_i = '1' then
          rin.state <= ST_PREPARE;
          rin.shreg <= stop_par & data_i & start;
        end if;

      when ST_PREPARE =>
        rin.divisor <= divisor_i;
        case parity_c is
          when PARITY_NONE =>
            rin.bit_ctr <= bit_count_c + stop_count_c;

          when PARITY_EVEN =>
            rin.bit_ctr <= bit_count_c + stop_count_c + 1;
            rin.shreg(parity_bit) <= nsl_math.logic.xor_reduce(r.shreg(parity_bit-1 downto 1));

          when PARITY_ODD =>
            rin.bit_ctr <= bit_count_c + stop_count_c + 1;
            rin.shreg(parity_bit) <= not nsl_math.logic.xor_reduce(r.shreg(parity_bit-1 downto 1));
        end case;
        rin.state <= ST_SHIFT;
        
      when ST_SHIFT =>
        if r.divisor /= 0 then
          rin.divisor <= r.divisor - 1;
        elsif r.bit_ctr /= 0 then
          rin.divisor <= divisor_i;
          rin.state <= ST_SHIFT;
          rin.bit_ctr <= r.bit_ctr - 1;
          rin.shreg <= "-" & r.shreg(r.shreg'left downto 1);
        else
          rin.state <= ST_IDLE;
        end if;

    end case;
  end process;

  moore: process(r)
  begin
    uart_o <= '1';
    ready_o <= '0';

    case r.state is
      when ST_PREPARE | ST_RESET =>
        null;

      when ST_IDLE =>
        ready_o <= '1';

      when ST_SHIFT =>
        uart_o <= r.shreg(0);
        ready_o <= '0';
    end case;
  end process;
  
end architecture;
