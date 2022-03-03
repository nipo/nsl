library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package serdes is

  type parity_t is (
    PARITY_NONE,
    PARITY_EVEN,
    PARITY_ODD
    );
  
  component uart_tx is
    generic(
      bit_count_c : natural;
      stop_count_c : natural range 1 to 2;
      parity_c : parity_t;
      rtr_active_c : std_ulogic := '0'
      );
    port(
      clock_i     : in std_ulogic;
      reset_n_i   : in std_ulogic;

      divisor_i   : in unsigned;

      -- Should be exposed as device TX
      uart_o      : out std_ulogic;
      -- Should be exposed as device /CTS. This is active low by
      -- default, but could be reversed through generics.
      rtr_i       : in std_ulogic := rtr_active_c;

      data_i      : in std_ulogic_vector(bit_count_c-1 downto 0);
      ready_o     : out std_ulogic;
      valid_i     : in std_ulogic
      );
  end component;

  component uart_rx is
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

      -- Should be exposed as device RX
      uart_i      : in std_ulogic;
      -- Should be exposed as device /RTS. This is active low by
      -- default, but could be reversed through generics.
      rts_o       : out std_ulogic;

      data_o      : out std_ulogic_vector(bit_count_c-1 downto 0);
      valid_o     : out std_ulogic;
      ready_i     : in std_ulogic := '1';
      parity_error_o : out std_ulogic;
      break_o     : out std_ulogic
      );
  end component;

end package serdes;
