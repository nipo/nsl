library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking;

entity hps_pd_master_port is
    generic(
      config_c : nsl_amba.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      reset_n_o : out std_ulogic;

      awid : in std_logic_vector(config_c.id_width-1 downto 0) := (others => '0');
      awaddr : in std_logic_vector(config_c.address_width-1 downto 0);
      awlen : in std_logic_vector(7 downto 0) := (others => '0');
      awsize : in std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(config_c.data_bus_width_l2, 3));
      awburst : in std_logic_vector(1 downto 0) := "01";
      awlock : in std_logic := '0';
      awcache : in std_logic_vector(3 downto 0) := (others => '0');
      awprot : in std_logic_vector(2 downto 0) := (others => '0');
      awvalid : in std_logic;
      awready : out std_logic;

      wdata : in std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wstrb : in std_logic_vector((2 ** config_c.data_bus_width_l2) - 1 downto 0) := (others => '1');
      wlast : in std_logic := '1';
      wvalid : in std_logic;
      wready : out std_logic;

      bid : out std_logic_vector(config_c.id_width-1 downto 0);
      bresp : out std_logic_vector(1 downto 0);
      bvalid : out std_logic;
      bready : in std_logic;

      arid : in std_logic_vector(config_c.id_width-1 downto 0) := (others => '0');
      araddr : in std_logic_vector(config_c.address_width-1 downto 0);
      arlen : in std_logic_vector(7 downto 0) := (others => '0');
      arsize : in std_logic_vector(2 downto 0) := std_logic_vector(to_unsigned(config_c.data_bus_width_l2, 3));
      arburst : in std_logic_vector(1 downto 0) := "01";
      arlock : in std_logic := '0';
      arcache : in std_logic_vector(3 downto 0) := (others => '0');
      arprot : in std_logic_vector(2 downto 0) := (others => '0');
      arvalid : in std_logic;
      arready : out std_logic;

      rid : out std_logic_vector(config_c.id_width-1 downto 0);
      rdata : out std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      rresp : out std_logic_vector(1 downto 0);
      rlast : out std_logic;
      rvalid : out std_logic;
      rready : in std_logic;

      axi_o : out nsl_amba.axi4_mm.master_t;
      axi_i : in nsl_amba.axi4_mm.slave_t
      );
end entity;

architecture rtl of hps_pd_master_port is

  signal running_s : std_ulogic;
  signal packed_s : nsl_amba.axi4_mm.master_t;
  signal guarded_s : nsl_amba.axi4_mm.slave_t;

begin

  assert config_c.len_width <= 8
    report "hps_pd_master_port: bursts are 256 beats at most"
    severity failure;

  assert config_c.data_bus_width_l2 >= 2 and config_c.data_bus_width_l2 <= 5
    report "hps_pd_master_port: the bridges are 32 to 256-bit wide"
    severity failure;

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_i,
      data_i => reset_n_i,
      data_o => running_s
      );

  reset_n_o <= running_s;

  packer: nsl_amba.packer.axi4_mm_slave_packer
    generic map(
      config_c => config_c
      )
    port map(
      awid => awid,
      awaddr => awaddr,
      awlen => awlen(config_c.len_width-1 downto 0),
      awsize => awsize,
      awburst => awburst,
      awlock(0) => awlock,
      awcache => awcache,
      awprot => awprot,
      awvalid => awvalid,
      awready => awready,
      wdata => wdata,
      wstrb => wstrb,
      wlast => wlast,
      wvalid => wvalid,
      wready => wready,
      bid => bid,
      bresp => bresp,
      bvalid => bvalid,
      bready => bready,
      arid => arid,
      araddr => araddr,
      arlen => arlen(config_c.len_width-1 downto 0),
      arsize => arsize,
      arburst => arburst,
      arlock(0) => arlock,
      arcache => arcache,
      arprot => arprot,
      arvalid => arvalid,
      arready => arready,
      rid => rid,
      rdata => rdata,
      rresp => rresp,
      rlast => rlast,
      rvalid => rvalid,
      rready => rready,
      buser => open,
      ruser => open,

      axi_o => packed_s,
      axi_i => guarded_s
      );

  -- Nothing crosses while in reset.
  guard: process(running_s, packed_s, axi_i)
  begin
    axi_o <= packed_s;
    guarded_s <= axi_i;

    if running_s = '0' then
      axi_o.aw.valid <= '0';
      axi_o.w.valid <= '0';
      axi_o.ar.valid <= '0';
      axi_o.b.ready <= '0';
      axi_o.r.ready <= '0';
      guarded_s.aw.ready <= '0';
      guarded_s.w.ready <= '0';
      guarded_s.ar.ready <= '0';
      guarded_s.b.valid <= '0';
      guarded_s.r.valid <= '0';
    end if;
  end process;

end architecture;
