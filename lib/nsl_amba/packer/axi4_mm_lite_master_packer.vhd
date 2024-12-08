library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_logic;
use nsl_amba.axi4_mm.all;
use nsl_logic.bool.all;

entity axi4_mm_lite_master_packer is
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
begin
  
  assert is_lite(config_c)
    report "configuration is not an AXI4-Lite subset"
    severity failure;

end entity;

architecture rtl of axi4_mm_lite_master_packer is

begin

  awvalid <= to_logic(is_valid(config_c, axi_i.aw));
  awaddr <= std_logic_vector(address(config_c, axi_i.aw));
  axi_o.aw <= accept(config_c, awready = '1');
  
  wvalid <= to_logic(is_valid(config_c, axi_i.w));
  wdata <= std_logic_vector(value(config_c, axi_i.w));
  wstrb <= std_logic_vector(strb(config_c, axi_i.w));
  axi_o.w <= accept(config_c, wready = '1');

  bready <= to_logic(is_ready(config_c, axi_i.b));
  axi_o.b <= write_response(config_c,
                            resp => to_resp(config_c, std_ulogic_vector(bresp)),
                            valid => bvalid = '1');

  arvalid <= to_logic(is_valid(config_c, axi_i.ar));
  araddr <= std_logic_vector(address(config_c, axi_i.ar));
  axi_o.ar <= accept(config_c, arready = '1');

  rready <= to_logic(is_ready(config_c, axi_i.r));
  axi_o.r <= read_data(config_c,
                       value => unsigned(rdata),
                       resp => to_resp(config_c, std_ulogic_vector(rresp)),
                       valid => rvalid = '1');
  
end architecture;
