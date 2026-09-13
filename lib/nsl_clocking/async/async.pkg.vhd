library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Asynchronous input handling (interdomain where sender domain is not knwown).
package async is

  -- Aligns a transition to a target value after the clock edge.
  -- Typically used to resynchronize reset signals to avoid
  -- uncertainity and abide hold times.
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

  -- Cycles a value has to hold still for, for a given clock rate and
  -- settling time.  Rounded down to whole megahertz, which no
  -- settling time is precise enough to care about.
  function debounce_cycle_count(clock_i_hz: natural;
                                stable_us: natural) return natural;

  -- Asynchronous one bit input, taken as true once it has held still
  -- long enough for whatever bounces to be over.  This is
  -- async_input with its time expressed as a time rather than as a
  -- count of cycles, which is the part a board knows and a clock rate
  -- does not.
  --
  -- A mechanical contact settles in a few milliseconds.  Ten is a
  -- usual figure for one a person operates, and a contact wiped by
  -- something being pushed in wants more.
  component async_debouncer is
    generic(
      clock_i_hz_c: natural;
      stable_us_c: natural := 10000;
      -- Value given until the input has held still once
      reset_value_c: std_ulogic := '0'
      );
    port(
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      data_i: in std_ulogic;
      data_o: out std_ulogic
      );
  end component;

  -- Asynchronous one-bit sampler with edge detection.
  component async_input is
    generic (
      sample_count_c: natural := 2;
      debounce_count_c: natural := 2;
      -- Debounced value presented while in reset and until the input
      -- settles for the first time.
      reset_value_c: std_ulogic := '0'
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
  -- port, and tries to cope with metastability when cycle_count_c >= 2.
  -- If cycle_count_c is 0, no retiming is done and this block is an
  -- asynchronous wire.
  component async_sampler is
    generic(
      cycle_count_c : natural := 2;
      data_width_c  : integer
      );
    port(
      clock_i  : in std_ulogic;
      data_i   : in std_ulogic_vector(data_width_c-1 downto 0);
      data_o   : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

  -- Samples an asynchronous bus, removes metastability and waits for
  -- /stable_count_c/ cycles with stable input value before
  -- propagating changes.
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

end package async;

package body async is

  function debounce_cycle_count(clock_i_hz: natural;
                                stable_us: natural) return natural
  is
    constant count_c: natural := clock_i_hz / 1000000 * stable_us;
  begin
    -- A value has to hold still for something, whatever the numbers
    -- say.
    if count_c = 0 then
      return 1;
    else
      return count_c;
    end if;
  end function;

end package body async;
