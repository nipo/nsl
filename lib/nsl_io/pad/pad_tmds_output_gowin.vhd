library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_io;
use nsl_io.diff.all;

entity pad_tmds_output is
  generic(
    invert_c : boolean := false;
    driver_mode_c : string := "default"
    );
  port(
    data_i : in std_ulogic;
    pad_o : out diff_pair
    );
end entity;

architecture rtl of pad_tmds_output is

  attribute syn_black_box: boolean ;
  COMPONENT ELVDS_OBUF
    PORT(
      O : OUT std_logic;
      OB : OUT std_logic;
      I : IN std_logic
      );
  end COMPONENT;
  attribute syn_black_box of ELVDS_OBUF : component is true;
  
  COMPONENT TLVDS_OBUF
    PORT(
      O : OUT std_logic;
      OB : OUT std_logic;
      I : IN std_logic
      );
  end COMPONENT;
  attribute syn_black_box of TLVDS_OBUF : component is true;

begin

  tlvds: if driver_mode_c = "tlvds"
  generate
    
    se2diff: TLVDS_OBUF
      port map(
        o => pad_o.p,
        ob => pad_o.n,
        i => data_i
        );

  end generate;
    
  no_tlvds: if driver_mode_c /= "tlvds"
  generate
    
    se2diff: ELVDS_OBUF
      port map(
        o => pad_o.p,
        ob => pad_o.n,
        i => data_i
        );

  end generate;
  
end architecture;
