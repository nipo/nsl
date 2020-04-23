library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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

  constant a32_d32_ms_idle : a32_d32_ms := (
    awaddr => (others => '-'),
    awvalid => '0',
    wdata => (others => '-'),
    wstrb => (others => '-'),
    wvalid => '0',
    bready => '0',
    araddr => (others => '-'),
    arvalid => '0',
    rready => '0'
    );

  constant a32_d32_sm_idle : a32_d32_sm := (
    awready => '0',
    wready => '0',
    bvalid => '0',
    bresp => (others => '-'),
    arready => '0',
    rvalid => '0',
    rresp => (others => '-'),
    rdata => (others => '-')
    );
  
  component axi4_lite_a32_d32_slave is
    generic (
      addr_size : natural range 3 to 32
      );
    port (
      aclk: in std_ulogic;
      aresetn: in std_ulogic := '1';

      p_axi_ms: in a32_d32_ms;
      p_axi_sm: out a32_d32_sm;

      p_addr : out unsigned(addr_size-1 downto 2);

      p_w_data : out std_ulogic_vector(31 downto 0);
      p_w_mask : out std_ulogic_vector(3 downto 0);
      p_w_ready : in std_ulogic := '1';
      p_w_valid : out std_ulogic;

      p_r_data : in std_ulogic_vector(31 downto 0);
      p_r_ready : out std_ulogic;
      p_r_valid : in std_ulogic := '1'
      );
  end component;

end package;
