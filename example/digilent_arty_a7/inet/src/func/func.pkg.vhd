library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_inet, nsl_data, nsl_uart, nsl_mii, nsl_smi;
use nsl_inet.ethernet.all;
use nsl_data.bytestream.all;

package func is
  component func_main is
    generic(
      clock_hz_c : integer
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      net_to_l1_o : out nsl_bnoc.committed.committed_req;
      net_to_l1_i : in nsl_bnoc.committed.committed_ack;
      net_from_l1_i : in nsl_bnoc.committed.committed_req;
      net_from_l1_o : out nsl_bnoc.committed.committed_ack;
      net_smi_o : out nsl_smi.smi.smi_master_o;
      net_smi_i : in nsl_smi.smi.smi_master_i;

      button_i : in std_ulogic_vector(0 to 3);
      led_o : out std_ulogic_vector(0 to 3);

      uart_o : out std_ulogic;
      uart_i : in std_ulogic
      );
  end component;
end package;
