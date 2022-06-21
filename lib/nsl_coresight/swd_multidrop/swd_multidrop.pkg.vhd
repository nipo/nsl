library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.swd.all;

package swd_multidrop is

  type swd_master_o_vector is array (integer range <>) of swd_master_o;
  type swd_master_i_vector is array (integer range <>) of swd_master_i;
  
  component swd_multidrop_router is
    generic(
      target_count_c: natural range 1 to 16;
      targetsel_base_c: std_ulogic_vector(27 downto 0)
      );
    port(
      reset_n_i: in std_ulogic;

      active_o: out std_ulogic;
      reset_o: out std_ulogic;
      selected_o: out std_ulogic;
      index_o: out natural range 0 to target_count_c-1;

      muxed_i: in swd_slave_i;
      muxed_o: out swd_slave_o;

      target_o: out swd_master_o_vector(0 to target_count_c-1);
      target_i: in swd_master_i_vector(0 to target_count_c-1)
      );
  end component;
    
end package swd_multidrop;
