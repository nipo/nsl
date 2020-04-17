library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package interdomain is

  -- Enforces max skew for the whole bus will not be above the fastest
  -- clock cycle time. Mostly suited for gray-coded data.
  --
  -- If not gray-coded, this register may wait for resynchronized data
  -- to be stable for /stable_count_c/ cycles before forwarding to the
  -- output. If stable_count_c = 0, this is disabled.
  component interdomain_reg is
    generic(
      stable_count_c : natural               := 0;
      cycle_count_c  : natural range 2 to 40 := 2;
      data_width_c   : integer
      );
    port(
      clock_i : in  std_ulogic;
      data_i  : in  std_ulogic_vector(data_width_c-1 downto 0);
      data_o  : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

  -- Makes a 1-stepped counter cross a clock region. Input/output can
  -- optionally be gray-encoded. If not, they'll internally be
  -- converted.
  --
  -- decode_stage_count allows for some timing relaxation of gray decoding
  -- state. It is unused if output is gray-coded.
  --
  -- Total latency:
  -- 1 * in_clock period
  --  + inter-clock jitter
  --  + (cycle_count_c + decode_stage_count) * out_clock period
  component interdomain_counter is
    generic(
      cycle_count_c        : natural := 2;
      data_width_c         : integer;
      decode_stage_count_c : natural := 1;
      input_is_gray_c      : boolean := false;
      output_is_gray_c     : boolean := false
      );
    port(
      clock_in_i  : in  std_ulogic;
      clock_out_i : in  std_ulogic;
      data_i      : in  unsigned(data_width_c-1 downto 0);
      data_o      : out unsigned(data_width_c-1 downto 0)
      );
  end component;

  -- Clocks input data to a register (clock is from the input domain),
  -- and ignores all timing constraints on the output side. This is
  -- mostly for configuration data that is not supposed to change
  -- frequently.
  component interdomain_static_reg is
    generic(
      data_width_c : integer
      );
    port(
      input_clock_i : in  std_ulogic;
      data_i        : in  std_ulogic_vector(data_width_c-1 downto 0);
      data_o        : out std_ulogic_vector(data_width_c-1 downto 0)
      );
  end component;

end package interdomain;
