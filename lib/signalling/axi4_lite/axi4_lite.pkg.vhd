library ieee;
use ieee.std_logic_1164.all;

package axi4_lite is

  type a32_d32_ms is
  record
    awaddr : std_ulogic_vector(31 downto 0);
    awvalid : std_ulogic;

    wdata : std_ulogic_vector(31 downto 0);
    wstrb : std_ulogic_vector(3 downto 0);
    wvalid : std_ulogic;

    bready : std_ulogic;

    araddr : std_ulogic_vector(31 downto 0);
    arvalid : std_ulogic;

    rready : std_ulogic;
  end record;

  type a32_d32_sm is
  record
    awready : std_ulogic;

    wready : std_ulogic;

    bvalid : std_ulogic;
    bresp : std_ulogic_vector(1 downto 0);

    arready : std_ulogic;

    rvalid : std_ulogic;
    rresp : std_ulogic_vector(1 downto 0);
    rdata : std_ulogic_vector(31 downto 0);
  end record;

  type a32_d32 is
  record
    ms: a32_d32_ms;
    sm: a32_d32_sm;
  end record;

end package;
