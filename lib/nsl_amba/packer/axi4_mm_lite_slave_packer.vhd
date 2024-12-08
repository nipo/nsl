library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_logic;
use nsl_amba.axi4_mm.all;
use nsl_logic.bool.all;

entity axi4_mm_lite_slave_packer is
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
begin
  
  assert is_lite(config_c)
    report "configuration is not an AXI4-Lite subset"
    severity failure;

end entity;

architecture rtl of axi4_mm_lite_slave_packer is

begin

  axi_o.aw <= address(config_c,
                      addr => unsigned(awaddr),
                      valid => awvalid = '1');
  awready <= to_logic(is_ready(config_c, axi_i.aw));

  axi_o.w <= write_data(config_c,
                        value => unsigned(wdata),
                        strb => std_ulogic_vector(wstrb),
                        valid => wvalid = '1');
  wready <= to_logic(is_ready(config_c, axi_i.w));

  axi_o.b <= accept(config_c,
                    ready => bready = '1');
  bresp <= std_logic_vector(to_logic(config_c, resp(config_c, axi_i.b)));
  bvalid <= to_logic(is_valid(config_c, axi_i.b));


  axi_o.ar <= address(config_c,
                      addr => unsigned(araddr),
                      valid => arvalid = '1');
  arready <= to_logic(is_ready(config_c, axi_i.ar));

  axi_o.r <= accept(config_c,
                    ready => rready = '1');
  rresp <= std_logic_vector(to_logic(config_c, resp(config_c, axi_i.r)));
  rvalid <= to_logic(is_valid(config_c, axi_i.r));
  rdata <= std_logic_vector(value(config_c, axi_i.r));
  
end architecture;
