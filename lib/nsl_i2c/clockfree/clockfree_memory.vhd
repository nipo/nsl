library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_math, hwdep;

entity clockfree_memory is
  generic (
    address: unsigned(7 downto 1);
    addr_width: integer range 1 to 16 := 8;
    granularity: integer range 1 to 4 := 1
  );
  port (
    i2c_o  : out nsl_i2c.i2c.i2c_o;
    i2c_i  : in  nsl_i2c.i2c.i2c_i
  );
end clockfree_memory;

architecture arch of clockfree_memory is

  constant addr_byte_cnt: integer := (addr_width - 1) / 8 + 1;
  constant mem_addr_lsb: integer := nsl_math.arith.log2(granularity);

  signal s_write, s_clk : std_ulogic;
  signal s_rdata, s_wdata : std_ulogic_vector(8*granularity-1 downto 0);
  
  signal s_address : unsigned(8*addr_byte_cnt-1 downto mem_addr_lsb);
  signal s_address_tmp : unsigned(8*addr_byte_cnt-1 downto 0);
  
begin

  slave: nsl_i2c.clockfree.clockfree_memory_controller
    generic map(
      addr_bytes_c => addr_byte_cnt,
      data_bytes_c => granularity
      )
    port map (
      slave_address_c => address,

      clock_o => s_clk,

      i2c_i => i2c_i,
      i2c_o => i2c_o,

      addr_o => s_address_tmp,

      read_data_i => s_rdata,

      write_data_o => s_wdata,
      write_strobe_o => s_write
    );

  s_address <= s_address_tmp(s_address'range);

  ram: hwdep.ram.ram_1p
    generic map (
      addr_size => s_address'length,
      data_size => 8*granularity
    )
    port map (
      p_clk => s_clk,
      p_wen => s_write,
      p_addr => std_ulogic_vector(s_address),
      p_wdata => s_wdata,
      p_rdata => s_rdata
      );

end arch;
