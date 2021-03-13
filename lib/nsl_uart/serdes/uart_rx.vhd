library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart, nsl_math;
use nsl_uart.serdes.all;

entity uart_rx is
  generic(
    divisor_width : natural range 1 to 20;
    bit_count_c : natural;
    stop_count_c : natural range 1 to 2;
    parity_c : parity_t
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    divisor_i   : in unsigned(divisor_width-1 downto 0);
    
    uart_i      : in std_ulogic;

    data_o      : out std_ulogic_vector(bit_count_c-1 downto 0);
    valid_o     : out std_ulogic;
    parity_ok_o : out std_ulogic;
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
    ST_OUT
    );

  type regs_t is record
    shreg: std_ulogic_vector(bit_count_c-1 downto 0);
    parity: std_ulogic;
    parity_ok: std_ulogic;
    break: std_ulogic;
    state: state_t;
    bit_ctr: integer range 0 to bit_count_c-1;
    divisor: unsigned(divisor_i'range);
    high_count: unsigned(divisor_i'range);
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

  transition: process(r, uart_i)
    variable bit_value : std_ulogic;
    variable new_bit, bit_done : boolean;
  begin
    rin <= r;

    if uart_i = '1' then
      rin.high_count <= r.high_count + 1;
    end if;

    new_bit := false;
    if r.high_count > shift_right(divisor_i, 1) then
      bit_value := '1';
    else
      bit_value := '0';
    end if;

    if r.divisor /= 0 then
      rin.divisor <= r.divisor - 1;
      bit_done := false;
    else
      bit_done := true;
      rin.divisor <= divisor_i;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if uart_i = '0' then
          new_bit := true;
          rin.state <= ST_START;
        end if;

      when ST_START =>
        if bit_done then
          if bit_value = '1' then
            rin.state <= ST_IDLE;
          else
            rin.state <= ST_SHIFT;
            new_bit := true;
            rin.bit_ctr <= bit_count_c-1;
            rin.shreg <= (others => '-');
            case parity_c is
              when PARITY_NONE =>
                null;

              when PARITY_ODD =>
                rin.parity <= '1';

              when PARITY_EVEN =>
                rin.parity <= '0';
            end case;
          end if;
        end if;
        
      when ST_SHIFT =>
        if bit_done then
          rin.shreg <= bit_value & r.shreg(r.shreg'left downto 1);
          rin.parity <= bit_value xor r.parity;
          new_bit := true;
          if r.bit_ctr /= 0 then
            rin.bit_ctr <= r.bit_ctr - 1;
          elsif parity_c = PARITY_NONE then
            rin.state <= ST_STOP;
            rin.break <= '0';
            rin.bit_ctr <= stop_count_c - 1;
          else
            rin.state <= ST_PARITY;
            rin.break <= '0';
            rin.bit_ctr <= stop_count_c - 1;
          end if;
        end if;

      when ST_PARITY =>
        if bit_done then
          rin.parity_ok <= bit_value xnor r.parity;
          new_bit := true;
          rin.state <= ST_STOP;
        end if;

      when ST_STOP =>
        if r.bit_ctr = 0 and bit_value = '1' then
          rin.state <= ST_OUT;
        end if;
        
        if bit_done then
          rin.break <= r.break or not bit_value;
          if r.bit_ctr /= 0 then
            new_bit := true;
            rin.bit_ctr <= r.bit_ctr - 1;
          else
            rin.state <= ST_OUT;
          end if;
        end if;

      when ST_OUT =>
        rin.state <= ST_IDLE;

    end case;

    if new_bit then
      rin.high_count <= (others => '0');
      rin.divisor <= divisor_i;
    end if;
  end process;

  moore: process(r)
  begin
    valid_o <= '0';
    data_o <= (others => '-');
    break_o <= '-';

    if parity_c = PARITY_NONE then
      parity_ok_o <= '1';
    else
      parity_ok_o <= r.parity_ok;
    end if;

    case r.state is
      when ST_OUT =>
        valid_o <= '1';
        data_o <= r.shreg;
        break_o <= r.break;

      when others =>
        null;
    end case;
  end process;
  
end architecture;
