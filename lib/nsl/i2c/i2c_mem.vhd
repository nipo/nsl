library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, hwdep, signalling;

entity i2c_mem is
  generic (
    address: std_ulogic_vector(7 downto 1);
    addr_width: integer range 1 to 16 := 8;
    granularity: integer range 1 to 4 := 1
  );
  port (
    p_i2c_o  : out signalling.i2c.i2c_o;
    p_i2c_i  : in  signalling.i2c.i2c_i
  );
end i2c_mem;

architecture arch of i2c_mem is

  constant addr_byte_cnt: integer := (addr_width - 1) / 8 + 1;

  signal s_write, s_clk : std_ulogic;
  signal s_rdata, s_wdata : std_ulogic_vector(8*granularity-1 downto 0);
  signal s_address : std_ulogic_vector(8*addr_byte_cnt-1 downto 0);
  
begin

  slave: nsl.i2c.i2c_mem_ctrl
    generic map(
      addr_bytes => addr_byte_cnt,
      data_bytes => granularity
      )
    port map (
      slave_address => address,

      p_clk => s_clk,

      p_i2c_i => p_i2c_i,
      p_i2c_o => p_i2c_o,

      p_addr => s_address,

      p_r_data => s_rdata,

      p_w_data => s_wdata,
      p_w_strobe => s_write
    );

  ram: hwdep.ram.ram_1p
    generic map (
      addr_size => addr_width,
      data_size => 8*granularity
    )
    port map (
      p_clk => s_clk,
      p_wen => s_write,
      p_addr => s_address(addr_width-1 downto 0),
      p_wdata => s_wdata,
      p_rdata => s_rdata
      );

end arch;
