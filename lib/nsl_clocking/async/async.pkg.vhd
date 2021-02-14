library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package async is

  -- Aligns a transition to a target value after the clock edge.
  -- Typically used to resynchronize reset signals to avoid
  -- uncertainity.
  component async_edge
    generic(
      cycle_count_c : natural range 2 to 8 := 2;
      target_value_c : std_ulogic := '1';
      async_reset_c : boolean := true
      );
    port (
      clock_i : in  std_ulogic;
      data_i  : in  std_ulogic;
      data_o  : out std_ulogic
      );
  end component;

  -- Propagates one asynchronous reset input to multiple clock domains
  -- with the guarantee at least one cycle happens on all clock
  -- domains before starting to deassert reset in any domain.
  component async_multi_reset is
    generic(
      debounce_count_c : natural := 2;
      domain_count_c : natural;
      reset_assert_value_c : std_ulogic := '0'
      );
    port (
      clock_i   : in  std_ulogic_vector(0 to domain_count_c-1);
      master_i : in  std_ulogic;
      slave_o : out std_ulogic_vector(0 to domain_count_c-1)
      );
  end component;

  -- Asynchronous one-bit sampler
  component async_deglitcher
    generic(
      cycle_count_c : natural := 2
      );
    port (
      clock_i : in  std_ulogic;
      data_i  : in  std_ulogic;
      data_o  : out std_ulogic
      );
  end component;

  -- Asynchronous one-bit sampler with edge detection.
  component async_input is
    generic (
      debounce_count_c: integer := 2
      );
    port (
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;
      data_i    : in std_ulogic;
      data_o    : out std_ulogic;
      rising_o  : out std_ulogic;
      falling_o : out std_ulogic
      );
  end component;

  -- Asynchronous bus sampler. Totally ignores the timing of input
  -- port, and tries to cope with metastability.
  component async_sampler is
    generic(
      cycle_count_c : natural range 1 to 40 := 2;
      data_width_c  : integer
      );
    port(
      clock_i  : in std_ulogic;
      data_i   : in std_ulogic_vector(data_width_c-1 downto 0);
      data_o   : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

  -- Samples an asynchronous bus, removes metastability and waits for
  -- /stable_count_c/ cycles with stable input before propagating
  -- changes.
  component async_stabilizer is
    generic(
      stable_count_c : natural range 1 to 10 := 1;
      cycle_count_c : natural range 1 to 40 := 2;
      data_width_c : integer
      );
    port(
      clock_i    : in std_ulogic;
      data_i     : in std_ulogic_vector(data_width_c-1 downto 0);
      data_o     : out std_ulogic_vector(data_width_c-1 downto 0);
      stable_o   : out std_ulogic
      );
  end component;

  component async_recovery is
    generic(
      clock_i_hz_c : natural;
      tick_skip_max_c : natural := 2;
      tick_i_hz_c : natural;
      tick_o_hz_c : natural;
      target_ppm_c : natural
      );
    port (
      clock_i : in  std_ulogic;
      reset_n_i : in std_ulogic;
      tick_valid_i : in std_ulogic := '1';
      tick_i : in std_ulogic;
      tick_o : out std_ulogic
      );
  end component;

end package async;
