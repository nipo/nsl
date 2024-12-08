library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.axi4_mm.all;

package packer is

  component axi4_mm_lite_slave_packer is
    generic (
      config_c: config_t
      );
    port (
      awaddr : in std_logic_vector(config_c.address_width-1 downto 0);
      awvalid : in std_logic;
      awready : out std_logic;
      wdata : in std_logic_vector(31 downto 0);
      wstrb : in std_logic_vector(3 downto 0);
      wvalid : in std_logic;
      wready : out std_logic;
      bready : in std_logic;
      bvalid : out std_logic;
      bresp : out std_logic_vector(1 downto 0);
      araddr : in std_logic_vector(config_c.address_width-1 downto 0);
      arvalid : in std_logic;
      arready : out std_logic;
      rready : in std_logic;
      rvalid : out std_logic;
      rresp : out std_logic_vector(1 downto 0);
      rdata : out std_logic_vector(31 downto 0);

      axi_o : out master_t;
      axi_i : in slave_t
      );
  end component;

  component axi4_mm_lite_master_packer is
    generic (
      config_c: config_t
      );
    port (
      awaddr : out std_logic_vector(config_c.address_width-1 downto 0);
      awvalid : out std_logic;
      awready : in std_logic;
      wdata : out std_logic_vector(31 downto 0);
      wstrb : out std_logic_vector(3 downto 0);
      wvalid : out std_logic;
      wready : in std_logic;
      bready : out std_logic;
      bvalid : in std_logic;
      bresp : in std_logic_vector(1 downto 0);
      araddr : out std_logic_vector(config_c.address_width-1 downto 0);
      arvalid : out std_logic;
      arready : in std_logic;
      rready : out std_logic;
      rvalid : in std_logic;
      rresp : in std_logic_vector(1 downto 0);
      rdata : in std_logic_vector(31 downto 0);

      axi_o : out slave_t;
      axi_i : in master_t
      );
  end component;

end package;
