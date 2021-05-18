library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package receiver is

  -- This is a receiver working on oversampled sck and ws lines.
  -- This block assumes sck, ws and sd are clean from metastability.
  component i2s_receiver is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_i : in std_ulogic;
      ws_i  : in std_ulogic;
      sd_i  : in std_ulogic;

      valid_o : out std_ulogic;
      channel_o : out std_ulogic;
      data_o  : out unsigned
      );
  end component;

  -- This is a receiver for a fixed data width, locally generating
  -- clocks
  component i2s_receiver_master is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_div_m1_i : in unsigned;

      sck_o : out std_ulogic;
      ws_o  : out std_ulogic;
      sd_i  : in std_ulogic;

      valid_o : out std_ulogic;
      channel_o : out std_ulogic;
      data_o  : out unsigned
      );
  end component;

  -- This is a receiver for a fixed data width, receiving generated
  -- clocks
  component i2s_receiver_slave is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_i : in std_ulogic;
      ws_i  : in std_ulogic;
      sd_i  : in std_ulogic;

      valid_o : out std_ulogic;
      channel_o : out std_ulogic;
      data_o  : out unsigned
      );
  end component;

end package receiver;

