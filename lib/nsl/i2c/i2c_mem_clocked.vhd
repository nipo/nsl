library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, hwdep, signalling;

entity i2c_mem_clocked is
  generic (
    address: unsigned(7 downto 1);
    addr_width: integer range 1 to 16 := 8;
    granularity: integer range 1 to 4 := 1
  );
  port (
    reset_n_i : in std_ulogic := '1';
    clock_i : in std_ulogic;

    i2c_o  : out signalling.i2c.i2c_o;
    i2c_i  : in  signalling.i2c.i2c_i
  );
end i2c_mem_clocked;

architecture arch of i2c_mem_clocked is

  constant addr_byte_cnt: integer := (addr_width + 7) / 8;

  signal s_write : std_ulogic;
  signal s_rdata, s_wdata : std_ulogic_vector(8*granularity-1 downto 0);
  signal s_address : unsigned(8*addr_byte_cnt-1 downto 0);
  signal s_addr : std_ulogic_vector(addr_width-1 downto 0);
  
begin

  slave: nsl.i2c.i2c_mem_ctrl_clocked
    generic map(
      addr_bytes => addr_byte_cnt,
      data_bytes => granularity
      )
    port map (
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      slave_address_i => address,

      i2c_i => i2c_i,
      i2c_o => i2c_o,

      addr_o => s_address,

      r_data_i => s_rdata,

      w_data_o => s_wdata,
      w_valid_o => s_write
    );

  s_addr <= std_ulogic_vector(s_address(addr_width-1 downto 0));

  ram: hwdep.ram.ram_1p
    generic map (
      addr_size => addr_width,
      data_size => 8*granularity
    )
    port map (
      p_clk => clock_i,
      p_wen => s_write,
      p_addr => s_addr,
      p_wdata => s_wdata,
      p_rdata => s_rdata
      );

end arch;
