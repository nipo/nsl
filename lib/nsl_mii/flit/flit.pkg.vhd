library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_bnoc;
use nsl_data.bytestream.all;

package flit is

  type mii_flit_t is record
    data   : std_ulogic_vector(7 downto 0);
    valid  : std_ulogic;
    error  : std_ulogic;
  end record;

  component mii_flit_from_committed is
    generic(
      ipg_c : natural := 96; -- bits
      handle_underrun_c: boolean := true
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      committed_i : in nsl_bnoc.committed.committed_req;
      committed_o : out nsl_bnoc.committed.committed_ack;

      -- Whether we are currently in a packet
      -- When implementing a Phy, this can be mapped to CRS.
      packet_o : out std_ulogic;
      flit_o : out mii_flit_t;
      ready_i : in std_ulogic
      );
  end component;
  
  component mii_flit_to_committed is
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      flit_i : in mii_flit_t;
      valid_i : in std_ulogic;

      committed_o : out nsl_bnoc.committed.committed_req;
      committed_i : in nsl_bnoc.committed.committed_ack
      );
  end component;

end package flit;
