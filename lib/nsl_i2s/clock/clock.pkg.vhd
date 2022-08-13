library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package clock is

  -- Generates an i2s clock from bit clock division factor and word
  -- bit count.
  component i2s_clock_generator is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_div_m1_i : in unsigned;
      word_width_m1_i    : in unsigned;

      -- Named after original "I2S bus specification" by Philips, February 1986
      sck_o  : out std_ulogic;
      ws_o   : out std_ulogic
      );
  end component;

  -- Generates an i2s clock from bit clock division factor and word
  -- bit count, using main clock as asynchronous oversampled input.
  component i2s_clock_generator_oversampled is
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      sck_div_m1_i : in unsigned;
      word_width_m1_i : in unsigned;

      mclk_i : in std_ulogic;

      -- Named after original "I2S bus specification" by Philips, February 1986
      sck_o  : out std_ulogic;
      ws_o   : out std_ulogic
      );
  end component;

  component i2s_clock_generator_from_tick is
    generic(
      -- Stereo sample implied, means 1 word clock cycle.
      -- Defaults to 128fs
      tick_per_sample_c : natural range 128 to 1024 := 128
      );
    port(
      clock_i    : in std_ulogic;
      reset_n_i : in std_ulogic;

      tick_i : in std_ulogic;

      sck_o : out std_ulogic;
      ws_o  : out std_ulogic
      );
  end component;

end package clock;

