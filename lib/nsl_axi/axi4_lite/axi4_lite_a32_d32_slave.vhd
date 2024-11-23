library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_data;
use nsl_axi.axi4_mm.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_lite_a32_d32_slave is
  generic (
    addr_size : natural range 3 to 32
    );
  port (
    aclk: in std_ulogic;
    aresetn: in std_ulogic := '1';

    p_axi_ms: in nsl_axi.axi4_lite.a32_d32_ms;
    p_axi_sm: out nsl_axi.axi4_lite.a32_d32_sm;

    p_addr : out unsigned(addr_size-1 downto 2);

    p_w_data : out std_ulogic_vector(31 downto 0);
    p_w_mask : out std_ulogic_vector(3 downto 0);
    p_w_ready : in std_ulogic := '1';
    p_w_valid : out std_ulogic;

    p_r_data : in std_ulogic_vector(31 downto 0);
    p_r_ready : out std_ulogic;
    p_r_valid : in std_ulogic := '1'
    );
end entity;

architecture rtl of axi4_lite_a32_d32_slave is

  constant config_c : config_t := config(address_width => addr_size,
                                         data_bus_width => 32);
  signal r_bytes_s, w_bytes_s : byte_string(0 to 2**config_c.data_bus_width_l2-1);
  signal axi_master_s : master_t;
  signal axi_slave_s : slave_t;
  
begin

  axi_master_s.aw <= address(config_c,
                             addr => unsigned(p_axi_ms.awaddr),
                             valid => p_axi_ms.awvalid = '1');
  axi_master_s.w <= write_data(config_c,
                               value => unsigned(p_axi_ms.wdata),
                               strb => p_axi_ms.wstrb,
                               endian => ENDIAN_BIG,
                               valid => p_axi_ms.wvalid = '1');
  axi_master_s.b <= accept(config_c,
                           ready => p_axi_ms.bready = '1');
  axi_master_s.ar <= address(config_c,
                             addr => unsigned(p_axi_ms.araddr),
                             valid => p_axi_ms.arvalid = '1');
  axi_master_s.r <= accept(config_c,
                           ready => p_axi_ms.rready = '1');
  
  p_axi_sm.awready <= '1' when is_ready(config_c, axi_slave_s.aw) else '0';
  p_axi_sm.wready <= '1' when is_ready(config_c, axi_slave_s.w) else '0';
  p_axi_sm.bvalid <= '1' when is_valid(config_c, axi_slave_s.b) else '0';
  p_axi_sm.bresp <= to_logic(config_c, resp(config_c, axi_slave_s.b));
  p_axi_sm.arready <= '1' when is_ready(config_c, axi_slave_s.ar) else '0';
  p_axi_sm.rvalid <= '1' when is_valid(config_c, axi_slave_s.r) else '0';
  p_axi_sm.rdata <= std_ulogic_vector(value(config_c, axi_slave_s.r));
  p_axi_sm.rresp <= to_logic(config_c, resp(config_c, axi_slave_s.r));
  
  p_w_data <= std_ulogic_vector(from_be(w_bytes_s));
  r_bytes_s <= to_be(unsigned(p_r_data));
  
  impl: nsl_axi.axi4_mm.axi4_mm_lite_slave
    generic map(
      config_c => config_c
      )
    port map (
      clock_i => aclk,
      reset_n_i => aresetn,

      axi_i => axi_master_s,
      axi_o => axi_slave_s,

      address_o => p_addr,

      w_data_o => w_bytes_s,
      w_mask_o => p_w_mask,
      w_ready_i => p_w_ready,
      w_valid_o => p_w_valid,

      r_data_i => r_bytes_s,
      r_ready_o => p_r_ready,
      r_valid_i => p_r_valid
      );

end architecture;
