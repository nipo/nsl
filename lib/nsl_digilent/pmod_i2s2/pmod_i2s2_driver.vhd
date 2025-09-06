library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_i2s;

entity pmod_i2s2_driver is
  generic(
    line_in_slave_c: boolean := false
    );
  port(
    pmod_io: work.pmod.pmod_double_t;

    clock_i   : in std_ulogic;
    reset_n_i : in std_ulogic;

    rx_mclk_i : in std_ulogic;
    rx_sck_div_m1_i : in unsigned;
    rx_valid_o : out std_ulogic;
    rx_channel_o : out std_ulogic;
    rx_data_o  : out unsigned;

    tx_mclk_i : in std_ulogic;
    tx_sck_div_m1_i : in unsigned;
    tx_ready_o : out std_ulogic;
    tx_channel_o : out std_ulogic;
    tx_data_i  : in unsigned
    );
end entity;

architecture beh of pmod_i2s2_driver is

begin

  tx: nsl_i2s.transmitter.i2s_transmitter_master
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      sck_div_m1_i => tx_sck_div_m1_i,
      sck_o => pmod_io(3),
      ws_o => pmod_io(2),
      sd_o => pmod_io(4),

      ready_o => tx_ready_o,
      channel_o => tx_channel_o,
      data_i => tx_data_i
      );

  pmod_io(1) <= tx_mclk_i;
  
  rx_slave: if line_in_slave_c
  generate
    rx: nsl_i2s.receiver.i2s_receiver_slave
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        sck_i => pmod_io(7),
        ws_i => pmod_io(6),
        sd_i => pmod_io(8),

        valid_o => rx_valid_o,
        channel_o => rx_channel_o,
        data_o => rx_data_o
        );
  end generate;

  rx_master: if not line_in_slave_c
  generate
    rx: nsl_i2s.receiver.i2s_receiver_master
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        sck_o => pmod_io(7),
        ws_o => pmod_io(6),
        sd_i => pmod_io(8),

        valid_o => rx_valid_o,
        channel_o => rx_channel_o,
        data_o => rx_data_o
        );
  end generate;

  pmod_io(5) <= rx_mclk_i;

end architecture;
