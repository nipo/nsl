library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

package pad is

  -- Signalling standard a memory bus pin is constrained to.  DDR2 runs
  -- at 1.8V, DDR3 at 1.5V and DDR3L at 1.35V; the logic behind the pin
  -- is the same, what changes is the constraint the pin carries and,
  -- on some vendors, which primitive drives it.
  type sstl_standard_t is (
    SSTL18,
    SSTL15,
    SSTL135
    );

  -- Clock and strobe pairs of a memory bus.  On a vendor whose pads
  -- pair up by themselves this is one primitive; elsewhere it is two
  -- pins driven against each other, and the standard reaches the pins
  -- through constraints.
  component pad_sstl_diff_output is
    generic(
      standard_c: sstl_standard_t
      );
    port(
      v_i: in std_ulogic;
      pad_o: out nsl_io.diff.diff_pair
      );
  end component;

  -- A strobe is driven on writes and listened to on reads, so its pair
  -- goes both ways.
  component pad_sstl_diff_io is
    generic(
      standard_c: sstl_standard_t
      );
    port(
      v_i: in nsl_io.io.tristated;
      v_o: out std_ulogic;
      pad_o: out nsl_io.io.tristated_vector(0 to 1);
      pad_i: in std_ulogic_vector(0 to 1)
      );
  end component;

  -- Single ended data pin, read against the bank's reference voltage.
  component pad_sstl_input is
    generic(
      standard_c: sstl_standard_t
      );
    port(
      pad_i: in std_ulogic;
      v_o: out std_ulogic
      );
  end component;


  component pad_diff_clock_input
    generic(
      diff_term : boolean := true;
      invert    : boolean := false
      );
    port(
      p_pad : in  diff_pair;
      p_clk : out diff_pair
      );
  end component;

  component pad_diff_input
    generic(
      diff_term : boolean := true;
      is_clock : boolean := false;
      invert : boolean := false
      );
    port(
      p_diff : in diff_pair;
      p_se : out std_ulogic
      );
  end component;

  component pad_diff_output
    generic(
      is_clock : boolean := false
      );
    port(
      p_se : in std_ulogic;
      p_diff : out diff_pair
      );
  end component;

  component pad_tmds_output
    generic(
      invert_c : boolean := false;
      driver_mode_c : string := "default"
      );
    port(
      data_i : in std_ulogic;
      pad_o : out diff_pair
      );
  end component;

  component pad_tmds_input
    generic(
      invert_c : boolean := false
      );
    port(
      data_o : out std_ulogic;
      pad_i : in diff_pair
      );
  end component;

end package pad;
