library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_logic;
use nsl_amba.axi4_mm.all;
use nsl_logic.bool.all;

entity axi4_mm_slave_packer is
  generic (
    config_c: config_t
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
    wstrb : in std_logic_vector((2 ** config_c.data_bus_width_l2) - 1 downto 0) := (others => '1');
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

    axi_o : out master_t;
    axi_i : in slave_t
    );
end entity;

architecture rtl of axi4_mm_slave_packer is

begin

  axi_o.aw <= address(config_c,
                      id => std_ulogic_vector(awid),
                      addr => unsigned(awaddr),
                      len_m1 => unsigned(awlen),
                      size_l2 => unsigned(awsize),
                      burst => to_burst(config_c, std_ulogic_vector(awburst)),
                      lock => to_lock(config_c, std_ulogic_vector(awlock)),
                      cache => std_ulogic_vector(awcache),
                      prot => std_ulogic_vector(awprot),
                      qos => std_ulogic_vector(awqos),
                      region => std_ulogic_vector(awregion),
                      user => std_ulogic_vector(awuser),
                      valid => awvalid = '1');
  awready <= to_logic(is_ready(config_c, axi_i.aw));

  axi_o.w <= write_data(config_c,
                        value => unsigned(wdata),
                        strb => std_ulogic_vector(wstrb),
                        user => std_ulogic_vector(wuser),
                        last => wlast = '1',
                        valid => wvalid = '1');
  wready <= to_logic(is_ready(config_c, axi_i.w));

  bid <= std_logic_vector(id(config_c, axi_i.b));
  bresp <= std_logic_vector(to_logic(config_c, resp(config_c, axi_i.b)));
  buser <= std_logic_vector(user(config_c, axi_i.b));
  bvalid <= to_logic(is_valid(config_c, axi_i.b));
  axi_o.b <= accept(config_c, ready => bready = '1');

  axi_o.ar <= address(config_c,
                      id => std_ulogic_vector(arid),
                      addr => unsigned(araddr),
                      len_m1 => unsigned(arlen),
                      size_l2 => unsigned(arsize),
                      burst => to_burst(config_c, std_ulogic_vector(arburst)),
                      lock => to_lock(config_c, std_ulogic_vector(arlock)),
                      cache => std_ulogic_vector(arcache),
                      prot => std_ulogic_vector(arprot),
                      qos => std_ulogic_vector(arqos),
                      region => std_ulogic_vector(arregion),
                      user => std_ulogic_vector(aruser),
                      valid => arvalid = '1');
  arready <= to_logic(is_ready(config_c, axi_i.ar));

  rid <= std_logic_vector(id(config_c, axi_i.r));
  rdata <= std_logic_vector(value(config_c, axi_i.r));
  rresp <= std_logic_vector(to_logic(config_c, resp(config_c, axi_i.r)));
  rlast <= to_logic(is_last(config_c, axi_i.r));
  ruser <= std_logic_vector(user(config_c, axi_i.r));
  rvalid <= to_logic(is_valid(config_c, axi_i.r));
  axi_o.r <= accept(config_c, ready => rready = '1');
  
end architecture;
