library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_amba, nsl_uart, nsl_clocking;

package transactor is

  component uart8 is
    generic(
      stop_count_c : natural range 1 to 2 := 1;
      parity_c : nsl_uart.serdes.parity_t := nsl_uart.serdes.PARITY_NONE;
      handshake_active_c : std_ulogic := '0'
      );
    port(
      reset_n_i    : in std_ulogic;
      clock_i      : in std_ulogic;

      divisor_i   : in unsigned;
      
      tx_o   : out std_ulogic;
      cts_i  : in  std_ulogic := handshake_active_c;
      rx_i   : in  std_ulogic;
      rts_o  : out std_ulogic;

      -- Resync/deglitched raw signals
      cts_o  : out std_ulogic;
      rx_o   : out std_ulogic;

      tx_data_i  : in  nsl_bnoc.pipe.pipe_req_t;
      tx_data_o  : out nsl_bnoc.pipe.pipe_ack_t;
      rx_data_i  : in  nsl_bnoc.pipe.pipe_ack_t;
      rx_data_o  : out nsl_bnoc.pipe.pipe_req_t;

      parity_error_o : out std_ulogic;
      break_o     : out std_ulogic
      );
  end component;

  component uart8_no_generics is
    port(
      reset_n_i    : in std_ulogic;
      clock_i      : in std_ulogic;

      divisor_i   : in unsigned;
      
      tx_o   : out std_ulogic;
      cts_i  : in  std_ulogic := '0';
      rx_i   : in  std_ulogic;
      rts_o  : out std_ulogic;

      -- Resync/deglitched raw signals
      cts_o  : out std_ulogic;
      rx_o   : out std_ulogic;

      tx_data_i  : in  nsl_bnoc.pipe.pipe_req_t;
      tx_data_o  : out nsl_bnoc.pipe.pipe_ack_t;
      rx_data_i  : in  nsl_bnoc.pipe.pipe_ack_t;
      rx_data_o  : out nsl_bnoc.pipe.pipe_req_t;

      parity_error_o : out std_ulogic;
      break_o        : out std_ulogic;

      stop_count_i       : in unsigned(1 downto 0);
      parity_i           : in unsigned(1 downto 0);
      handshake_active_i : in std_ulogic := '0'
      );
  end component;

  component cbor_controller is
    generic(
      system_clock_c     : natural;
      axi_s_cfg_c        : nsl_amba.axi4_stream.config_t;
      stop_count_c       : natural range 1 to 2 := 1;
      parity_c           : nsl_uart.serdes.parity_t := nsl_uart.serdes.PARITY_NONE;
      handshake_active_c : std_ulogic := '0';
      divisor_c          : unsigned(31 downto 0);
      timeout_c          : unsigned(31 downto 0);
      bstr_max_size_c    : natural range 0 to 511
      );
    port (
      reset_n_i    : in std_ulogic;
      clock_i      : in std_ulogic;

      tx_o   : out std_ulogic;
      cts_i  : in std_ulogic := handshake_active_c;
      rx_i   : in  std_ulogic;
      rts_o  : out std_ulogic;

      cmd_i  : in  nsl_amba.axi4_stream.master_t;
      cmd_o  : out nsl_amba.axi4_stream.slave_t;
      rsp_i  : in  nsl_amba.axi4_stream.slave_t;
      rsp_o  : out nsl_amba.axi4_stream.master_t
      );
  end component;

end package transactor;
