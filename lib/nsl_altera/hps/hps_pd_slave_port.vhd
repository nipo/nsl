library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_clocking;

entity hps_pd_slave_port is
    generic(
      config_c : nsl_amba.axi4_mm.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;
      reset_n_o : out std_ulogic;

      axi_i : in nsl_amba.axi4_mm.master_t;
      axi_o : out nsl_amba.axi4_mm.slave_t;

      awid : out std_logic_vector(config_c.id_width-1 downto 0);
      awaddr : out std_logic_vector(config_c.address_width-1 downto 0);
      awlen : out std_logic_vector(7 downto 0);
      awsize : out std_logic_vector(2 downto 0);
      awburst : out std_logic_vector(1 downto 0);
      awlock : out std_logic;
      awcache : out std_logic_vector(3 downto 0);
      awprot : out std_logic_vector(2 downto 0);
      awuser : out std_logic_vector(7 downto 0);
      awvalid : out std_logic;
      awready : in std_logic;

      wdata : out std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wstrb : out std_logic_vector((2 ** config_c.data_bus_width_l2) - 1 downto 0);
      wlast : out std_logic;
      wvalid : out std_logic;
      wready : in std_logic;

      bid : in std_logic_vector(config_c.id_width-1 downto 0);
      bresp : in std_logic_vector(1 downto 0);
      bvalid : in std_logic;
      bready : out std_logic;

      arid : out std_logic_vector(config_c.id_width-1 downto 0);
      araddr : out std_logic_vector(config_c.address_width-1 downto 0);
      arlen : out std_logic_vector(7 downto 0);
      arsize : out std_logic_vector(2 downto 0);
      arburst : out std_logic_vector(1 downto 0);
      arlock : out std_logic;
      arcache : out std_logic_vector(3 downto 0);
      arprot : out std_logic_vector(2 downto 0);
      aruser : out std_logic_vector(7 downto 0);
      arvalid : out std_logic;
      arready : in std_logic;

      rid : in std_logic_vector(config_c.id_width-1 downto 0);
      rdata : in std_logic_vector(8 * (2 ** config_c.data_bus_width_l2) - 1 downto 0);
      rresp : in std_logic_vector(1 downto 0);
      rlast : in std_logic;
      rvalid : in std_logic;
      rready : out std_logic
      );
end entity;

architecture rtl of hps_pd_slave_port is

  signal running_s : std_ulogic;
  signal packed_s : nsl_amba.axi4_mm.slave_t;
  signal guarded_s : nsl_amba.axi4_mm.master_t;
  signal len_aw_s, len_ar_s : std_logic_vector(config_c.len_width-1 downto 0);
  signal user_aw_s, user_ar_s : std_logic_vector(config_c.user_width-1 downto 0);

begin

  assert config_c.len_width <= 8 and config_c.user_width <= 8
    report "hps_pd_slave_port: AxLEN and AxUSER are 8-bit wide"
    severity failure;

  assert config_c.data_bus_width_l2 >= 2 and config_c.data_bus_width_l2 <= 5
    report "hps_pd_slave_port: the bridges are 32 to 256-bit wide"
    severity failure;

  reset_sync: nsl_clocking.async.async_edge
    port map(
      clock_i => clock_i,
      data_i => reset_n_i,
      data_o => running_s
      );

  reset_n_o <= running_s;

  -- The master packer has length and user ports of the widths of
  -- config_c.
  extend: process(len_aw_s, len_ar_s, user_aw_s, user_ar_s)
  begin
    awlen <= (others => '0');
    arlen <= (others => '0');
    awuser <= (others => '0');
    aruser <= (others => '0');
    awlen(len_aw_s'range) <= len_aw_s;
    arlen(len_ar_s'range) <= len_ar_s;
    awuser(user_aw_s'range) <= user_aw_s;
    aruser(user_ar_s'range) <= user_ar_s;
  end process;

  packer: nsl_amba.packer.axi4_mm_master_packer
    generic map(
      config_c => config_c
      )
    port map(
      awid => awid,
      awaddr => awaddr,
      awlen => len_aw_s,
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
      arlen => len_ar_s,
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
      awqos => open,
      awregion => open,
      awuser => user_aw_s,
      wid => open,
      wuser => open,
      aruser => user_ar_s,
      arqos => open,
      arregion => open,

      axi_o => packed_s,
      axi_i => guarded_s
      );

  -- Nothing crosses while in reset.
  guard: process(running_s, packed_s, axi_i)
  begin
    axi_o <= packed_s;
    guarded_s <= axi_i;

    if running_s = '0' then
      axi_o.aw.ready <= '0';
      axi_o.w.ready <= '0';
      axi_o.ar.ready <= '0';
      axi_o.b.valid <= '0';
      axi_o.r.valid <= '0';
      guarded_s.aw.valid <= '0';
      guarded_s.w.valid <= '0';
      guarded_s.ar.valid <= '0';
      guarded_s.b.ready <= '0';
      guarded_s.r.ready <= '0';
    end if;
  end process;

end architecture;
