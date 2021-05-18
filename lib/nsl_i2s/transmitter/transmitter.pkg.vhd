library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package transmitter is

  -- This is a transmitter working on oversampled sck and ws lines.
  -- This block assumes sck, ws and sd are clean from metastability.
  component i2s_transmitter is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_i : in  std_ulogic;
      ws_i  : in  std_ulogic;
      sd_o  : out std_ulogic;

      ready_o : out std_ulogic;
      channel_o : out std_ulogic;
      data_i  : in unsigned
      );
  end component;

  -- This is a transmitter for a fixed data width, locally generating
  -- clocks
  component i2s_transmitter_master is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_div_m1_i : in unsigned;

      sck_o : out std_ulogic;
      ws_o  : out std_ulogic;
      sd_o  : out std_ulogic;

      ready_o : out std_ulogic;
      channel_o : out std_ulogic;
      data_i  : in unsigned
      );
  end component;

  -- This is a transmitter for a fixed data width, receiving generated
  -- clocks
  component i2s_transmitter_slave is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_o : out std_ulogic;
      ws_o  : out std_ulogic;
      sd_o  : out std_ulogic;

      ready_o : out std_ulogic;
      channel_o : out std_ulogic;
      data_i  : in unsigned
      );
  end component;

end package transmitter;

