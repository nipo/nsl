library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_uart, nsl_logic;
use nsl_uart.serdes.all;

entity uart_tx_no_generics is
  generic(
    bit_count_c : natural range 7 to 8
    );
  port(
    clock_i     : in std_ulogic;
    reset_n_i   : in std_ulogic;

    divisor_i   : in unsigned;
    
    uart_o      : out std_ulogic;
    rtr_i       : in std_ulogic := '0';

    data_i      : in std_ulogic_vector(bit_count_c-1 downto 0);
    ready_o     : out std_ulogic;
    valid_i     : in std_ulogic;
    
    stop_count_i: in unsigned(1 downto 0); -- range 1 to 2
    parity_i    : in unsigned(1 downto 0); -- encoded value of parity_t
    rtr_active_i: in std_ulogic := '0'
    );
end entity;

architecture beh of uart_tx_no_generics is

  type state_t is (
    ST_RESET,
    ST_WAIT,
    ST_IDLE,
    ST_PREPARE,
    ST_SHIFT
    );

  constant max_stop_count_c  : natural := 2;
  constant max_shreg_width_c : natural := bit_count_c+max_stop_count_c + 2;
  
  constant start    : std_ulogic_vector(0 downto 0) := (others => '0');
  constant stop_par : std_ulogic_vector(max_stop_count_c + 1 - 1 downto 0) := (others => '1');
  
  type regs_t is record
    shreg: std_ulogic_vector(max_shreg_width_c-1 downto 0);
    bit_ctr: natural range 0 to max_shreg_width_c-1;
    divisor: unsigned(divisor_i'length - 1 downto 0);
    state: state_t;
  end record;
  
  signal r, rin: regs_t;

  signal s_tick: std_ulogic;
  
begin
  
  regs: process (reset_n_i, clock_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.divisor <= (others => '0');
    end if;
  end process;

  transition: process(r, data_i, valid_i, divisor_i, rtr_i, rtr_active_i, stop_count_i, parity_i)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if valid_i = '1' then
          rin.state <= ST_PREPARE;
          -- Use fixed limits for each stop_count case (1 or 2) to avoid
          -- variable-width slices
          if stop_count_i = 1 then
            -- shreg = ['-', stop, par_slot, data, start]
            rin.shreg <= (others => '-');
            rin.shreg(bit_count_c+2 downto 0) <=
              stop_par(1 downto 0) & data_i(bit_count_c-1 downto 0) & start;
            rin.bit_ctr <= 1 + bit_count_c;
          else -- stop_count_i = 2
            -- shreg = [stop2, stop1, par_slot, data, start]
            rin.shreg(max_shreg_width_c-1 downto 0) <=
              stop_par(2 downto 0) & data_i(bit_count_c-1 downto 0) & start;
            rin.bit_ctr <= 2 + bit_count_c;
          end if;
        elsif rtr_active_i = '1' and rtr_i = '0' then
          -- Handshake enabled and receiver not ready - wait for CTS
          rin.state <= ST_WAIT;
        end if;

      when ST_WAIT =>
        if rtr_active_i = '0' or rtr_i = '1' then
          -- Handshake disabled or receiver is ready
          rin.state <= ST_IDLE;
        end if;

      when ST_PREPARE =>
        rin.divisor <= divisor_i;
        case parity_t'val(to_integer(parity_i)) is
          when PARITY_NONE =>
            rin.bit_ctr <= r.bit_ctr;

          when PARITY_EVEN =>
            rin.bit_ctr <= r.bit_ctr + 1;
            rin.shreg(bit_count_c + 1) <= nsl_logic.logic.xor_reduce(r.shreg(bit_count_c downto 1));

          when PARITY_ODD =>
            rin.bit_ctr <= r.bit_ctr + 1;
            rin.shreg(bit_count_c + 1) <= not nsl_logic.logic.xor_reduce(r.shreg(bit_count_c downto 1));
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
          -- Transmission complete, go back to idle (or wait for CTS if handshake enabled)
          if rtr_active_i = '1' and rtr_i = '0' then
            rin.state <= ST_WAIT;
          else
            rin.state <= ST_IDLE;
          end if;
        end if;

    end case;
  end process;

  moore: process(r, rtr_active_i, rtr_i)
  begin
    uart_o <= '1';
    ready_o <= '0';

    case r.state is
      when ST_PREPARE | ST_RESET | ST_WAIT =>
        null;

      when ST_IDLE =>
        -- ready_o <= '1';
        if rtr_active_i = '1' then
          ready_o <= rtr_i;
        else
          ready_o <= '1';
        end if;

      when ST_SHIFT =>
        uart_o <= r.shreg(0);
        ready_o <= '0';
    end case;
  end process;
  
end architecture;
