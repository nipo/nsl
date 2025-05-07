library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_logic;
use nsl_amba.axi4_mm.all;
use nsl_logic.bool.all;

entity axi4_mm_master_packer is
  generic (
    config_c: config_t
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
    wstrb : out std_logic_vector((2 ** config_c.data_bus_width_l2) - 1 downto 0);
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

    axi_o : out slave_t;
    axi_i : in master_t
    );
end entity;

architecture rtl of axi4_mm_master_packer is

begin

  awid <= std_logic_vector(id(config_c, axi_i.aw));
  awaddr <= std_logic_vector(address(config_c, axi_i.aw));
  awlen <= std_logic_vector(length_m1(config_c, axi_i.aw, awlen'length));
  awsize <= std_logic_vector(size_l2(config_c, axi_i.aw));
  awburst <= std_logic_vector(to_logic(config_c, burst(config_c, axi_i.aw)));
  awlock <= std_logic_vector(to_logic(config_c, lock(config_c, axi_i.aw)));
  awcache <= std_logic_vector(cache(config_c, axi_i.aw));
  awprot <= std_logic_vector(prot(config_c, axi_i.aw));
  awqos <= std_logic_vector(qos(config_c, axi_i.aw));
  awregion <= std_logic_vector(region(config_c, axi_i.aw));
  awuser <= std_logic_vector(user(config_c, axi_i.aw));
  awvalid <= to_logic(is_valid(config_c, axi_i.aw));
  axi_o.aw <= accept(config_c, awready = '1');
  
  wdata <= std_logic_vector(value(config_c, axi_i.w));
  wstrb <= std_logic_vector(strb(config_c, axi_i.w));
  wlast <= to_logic(is_last(config_c, axi_i.w));
  wuser <= std_logic_vector(user(config_c, axi_i.w));
  wvalid <= to_logic(is_valid(config_c, axi_i.w));
  axi_o.w <= accept(config_c, wready = '1');

  bready <= to_logic(is_ready(config_c, axi_i.b));
  axi_o.b <= write_response(config_c,
                            id => std_ulogic_vector(bid),
                            resp => to_resp(config_c, std_ulogic_vector(bresp)),
                            user => std_ulogic_vector(buser),
                            valid => bvalid = '1');

  arid <= std_logic_vector(id(config_c, axi_i.ar));
  araddr <= std_logic_vector(address(config_c, axi_i.ar));
  arlen <= std_logic_vector(length_m1(config_c, axi_i.ar, arlen'length));
  arsize <= std_logic_vector(size_l2(config_c, axi_i.ar));
  arburst <= std_logic_vector(to_logic(config_c, burst(config_c, axi_i.ar)));
  arlock <= std_logic_vector(to_logic(config_c, lock(config_c, axi_i.ar)));
  arcache <= std_logic_vector(cache(config_c, axi_i.ar));
  arprot <= std_logic_vector(prot(config_c, axi_i.ar));
  arqos <= std_logic_vector(qos(config_c, axi_i.ar));
  arregion <= std_logic_vector(region(config_c, axi_i.ar));
  aruser <= std_logic_vector(user(config_c, axi_i.ar));
  arvalid <= to_logic(is_valid(config_c, axi_i.ar));
  axi_o.ar <= accept(config_c, arready = '1');

  rready <= to_logic(is_ready(config_c, axi_i.r));
  axi_o.r <= read_data(config_c,
                       value => unsigned(rdata),
                       id => std_ulogic_vector(rid),
                       user => std_ulogic_vector(ruser),
                       resp => to_resp(config_c, std_ulogic_vector(rresp)),
                       valid => rvalid = '1',
                       last => rlast = '1');
  
end architecture;
