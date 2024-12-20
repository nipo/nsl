library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package packer is

  component axi4_mm_lite_slave_packer is
    generic (
      config_c: nsl_amba.axi4_mm.config_t
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

      axi_o : out nsl_amba.axi4_mm.master_t;
      axi_i : in nsl_amba.axi4_mm.slave_t
      );
  end component;

  component axi4_mm_lite_master_packer is
    generic (
      config_c: nsl_amba.axi4_mm.config_t
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

      axi_o : out nsl_amba.axi4_mm.slave_t;
      axi_i : in nsl_amba.axi4_mm.master_t
      );
  end component;

  component axi4_mm_slave_packer is
    generic (
      config_c: nsl_amba.axi4_mm.config_t
      );
    port (
      awid: in std_logic_vector(config_c.id_width-1 downto 0) := (others => '0');
      awaddr : in std_logic_vector(config_c.address_width-1 downto 0);
      awlen: in std_logic_vector(config_c.len_width-1 downto 0) := (others => '0');
      awsize: in std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(config_c.data_bus_width_l2, 3));
      awburst: in std_logic_vector(1 downto 0) := "01";
      awlock: in std_logic_vector(0 downto 0) := (others => '0');
      awcache: in std_logic_vector(3 downto 0) := (others => '0');
      awprot: in std_logic_vector(2 downto 0) := (others => '0');
      awqos: in std_logic_vector(3 downto 0) := (others => '0');
      awregion: in std_logic_vector(3 downto 0) := (others => '0');
      awuser: in std_logic_vector(config_c.user_width-1 downto 0) := (others => '0');
      awvalid : in std_logic;
      awready : out std_logic;

      wid: in std_logic_vector(config_c.id_width-1 downto 0) := (others => '0');
      wdata : in std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wstrb : in std_logic_vector(3 downto 0) := (others => '1');
      wlast : in std_logic := '1';
      wuser: in std_logic_vector(config_c.user_width-1 downto 0) := (others => '0');
      wvalid : in std_logic;
      wready : out std_logic;

      bid: out std_logic_vector(config_c.id_width-1 downto 0);
      bresp : out std_logic_vector(1 downto 0);
      buser: out std_logic_vector(config_c.user_width-1 downto 0);
      bvalid : out std_logic;
      bready : in std_logic;

      arid: in std_logic_vector(config_c.id_width-1 downto 0) := (others => '0');
      araddr : in std_logic_vector(config_c.address_width-1 downto 0);
      arlen: in std_logic_vector(config_c.len_width-1 downto 0) := (others => '0');
      arsize: in std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(config_c.data_bus_width_l2, 3));
      arburst: in std_logic_vector(1 downto 0) := "01";
      arlock: in std_logic_vector(0 downto 0) := (others => '0');
      arcache: in std_logic_vector(3 downto 0) := (others => '0');
      arprot: in std_logic_vector(2 downto 0) := (others => '0');
      arqos: in std_logic_vector(3 downto 0) := (others => '0');
      arregion: in std_logic_vector(3 downto 0) := (others => '0');
      aruser: in std_logic_vector(config_c.user_width-1 downto 0) := (others => '0');
      arvalid : in std_logic;
      arready : out std_logic;

      rid: out std_logic_vector(config_c.id_width-1 downto 0);
      rdata : out std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      rresp : out std_logic_vector(1 downto 0);
      rlast : out std_logic;
      ruser: out std_logic_vector(config_c.user_width-1 downto 0);
      rvalid : out std_logic;
      rready : in std_logic := '1';

      axi_o : out nsl_amba.axi4_mm.master_t;
      axi_i : in nsl_amba.axi4_mm.slave_t
      );
  end component;

  component axi4_mm_master_packer is
    generic (
      config_c: nsl_amba.axi4_mm.config_t
      );
    port (
      awid: out std_logic_vector(config_c.id_width-1 downto 0);
      awaddr : out std_logic_vector(config_c.address_width-1 downto 0);
      awlen: out std_logic_vector(config_c.len_width-1 downto 0);
      awsize: out std_logic_vector(2 downto 0);
      awburst: out std_logic_vector(1 downto 0);
      awlock: out std_logic_vector(0 downto 0);
      awcache: out std_logic_vector(3 downto 0);
      awprot: out std_logic_vector(2 downto 0);
      awqos: out std_logic_vector(3 downto 0);
      awregion: out std_logic_vector(3 downto 0);
      awuser: out std_logic_vector(config_c.user_width-1 downto 0);
      awvalid : out std_logic;
      awready : in std_logic;

      wid: out std_logic_vector(config_c.id_width-1 downto 0);
      wdata : out std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wstrb : out std_logic_vector(3 downto 0);
      wlast : out std_logic;
      wuser: out std_logic_vector(config_c.user_width-1 downto 0);
      wvalid : out std_logic;
      wready : in std_logic := '1';

      bid: in std_logic_vector(config_c.id_width-1 downto 0);
      bresp : in std_logic_vector(1 downto 0);
      buser: in std_logic_vector(config_c.user_width-1 downto 0) := (others => '0');
      bvalid : in std_logic;
      bready : out std_logic;

      arid: out std_logic_vector(config_c.id_width-1 downto 0);
      araddr : out std_logic_vector(config_c.address_width-1 downto 0);
      arlen: out std_logic_vector(config_c.len_width-1 downto 0);
      arsize: out std_logic_vector(2 downto 0);
      arburst: out std_logic_vector(1 downto 0);
      arlock: out std_logic_vector(0 downto 0);
      arcache: out std_logic_vector(3 downto 0);
      arprot: out std_logic_vector(2 downto 0);
      arqos: out std_logic_vector(3 downto 0);
      arregion: out std_logic_vector(3 downto 0);
      aruser: out std_logic_vector(config_c.user_width-1 downto 0);
      arvalid : out std_logic;
      arready : in std_logic := '1';

      rid: in std_logic_vector(config_c.id_width-1 downto 0);
      rdata : in std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      rresp : in std_logic_vector(1 downto 0);
      rlast : in std_logic := '1';
      ruser: in std_logic_vector(config_c.user_width-1 downto 0) := (others => '0');
      rvalid : in std_logic;
      rready : out std_logic;

      axi_o : out nsl_amba.axi4_mm.slave_t;
      axi_i : in nsl_amba.axi4_mm.master_t
      );
  end component;

  component axi4_stream_master_packer is
    generic (
      config_c: nsl_amba.axi4_stream.config_t
      );
    port (
      tvalid : out std_logic;
      tready : in std_logic := '1';
      tdata : out std_logic_vector(8 * config_c.data_width - 1 downto 0);
      tstrb : out std_logic_vector(config_c.data_width - 1 downto 0);
      tkeep : out std_logic_vector(config_c.data_width - 1 downto 0);
      tlast: out std_logic;
      tid: out std_logic_vector(config_c.id_width - 1 downto 0);
      tdest: out std_logic_vector(config_c.dest_width-1 downto 0);
      tuser: out std_logic_vector(config_c.user_width-1 downto 0);

      stream_o : out nsl_amba.axi4_stream.slave_t;
      stream_i : in nsl_amba.axi4_stream.master_t
      );
  end component;

  component axi4_stream_slave_packer is
    generic (
      config_c: nsl_amba.axi4_stream.config_t
      );
    port (
      tvalid : in std_logic;
      tready : out std_logic;
      tdata : in std_logic_vector(8 * config_c.data_width - 1 downto 0) := (others => '0');
      tstrb : in std_logic_vector(config_c.data_width - 1 downto 0) := (others => '1');
      tkeep : in std_logic_vector(config_c.data_width - 1 downto 0) := (others => '1');
      tlast: in std_logic := '1';
      tid: in std_logic_vector(config_c.id_width - 1 downto 0) := (others => '0');
      tdest: in std_logic_vector(config_c.dest_width-1 downto 0) := (others => '0');
      tuser: in std_logic_vector(config_c.user_width-1 downto 0) := (others => '0');

      stream_i : in nsl_amba.axi4_stream.slave_t;
      stream_o : out nsl_amba.axi4_stream.master_t
      );
  end component;
  
end package;
