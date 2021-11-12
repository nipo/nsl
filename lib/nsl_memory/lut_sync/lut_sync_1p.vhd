library ieee;
use ieee.std_logic_1164.all;

library nsl_memory;

entity lut_sync_1p is
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
end entity;

architecture beh of lut_sync_1p is

  constant a_zero : std_ulogic_vector(input_width_c-1 downto 0) := (others => '0');
  
begin

  impl: nsl_memory.lut_sync.lut_sync_2p
    generic map(
      input_width_c => input_width_c,
      output_width_c => output_width_c,
      contents_c => contents_c
      )
    port map(
      clock_i => clock_i,

      a_enable_i => enable_i,
      a_i => data_i,
      a_o => data_o,

      b_enable_i => '0',
      b_i => a_zero,
      b_o => open
      );
  
end architecture;
