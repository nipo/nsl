library ieee;
use ieee.std_logic_1164.all;

package lut_sync is

  component lut_sync_2p is
    generic (
      input_width_c : natural;
      output_width_c : natural;
      -- output_width_c * 2 ** input_width_c bits
      contents_c : std_ulogic_vector
      );
    port (
      clock_i : in std_ulogic;

      a_enable_i : in std_ulogic := '1';
      a_i : in std_ulogic_vector(input_width_c-1 downto 0);
      a_o : out std_ulogic_vector(output_width_c-1 downto 0);

      b_enable_i : in std_ulogic := '1';
      b_i : in std_ulogic_vector(input_width_c-1 downto 0);
      b_o : out std_ulogic_vector(output_width_c-1 downto 0)
      );
  end component;

  component lut_sync_1p is
    generic (
      input_width_c : natural;
      output_width_c : natural;
      -- output_width_c * 2 ** input_width_c bits
      contents_c : std_ulogic_vector
      );
    port (
      clock_i : in std_ulogic;

      enable_i : in std_ulogic := '1';
      data_i : in std_ulogic_vector(input_width_c-1 downto 0);
      data_o : out std_ulogic_vector(output_width_c-1 downto 0)
      );
  end component;

end package lut_sync;
