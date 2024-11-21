library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package counter is

  component event_counter is
    port(
      clock_i    : in  std_ulogic;
      reset_n_i  : in  std_ulogic;

      event_i : in std_ulogic;
      
      count_o   : out unsigned
      );
  end component;

  component event_binned_counter is
    generic(
      event_bin_count_l2_c : natural := 8;
      event_count_width_c : natural := 16
      );
    port(
      event_clock_i    : in  std_ulogic;
      event_reset_n_i  : in  std_ulogic;

      event_valid_i : in std_ulogic;
      event_ready_o : out std_ulogic;
      event_bin_i : in unsigned(event_bin_count_l2_c-1 downto 0);

      -- Statistics read / clear port
      stat_clock_i : in std_ulogic;
      stat_reset_n_i : in std_ulogic;

      -- Select bin to operate on
      stat_bin_i : in unsigned(event_bin_count_l2_c-1 downto 0);
      -- Clear strobe (read is ignored) for a bin
      stat_clear_en_i : in std_ulogic;
      -- Read handshake for a bin
      stat_read_ready_i : in std_ulogic;
      stat_read_count_o : out unsigned(event_count_width_c-1 downto 0);
      stat_read_valid_o : out std_ulogic
      );
  end component;

end package counter;
