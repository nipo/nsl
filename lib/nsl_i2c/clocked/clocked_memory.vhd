library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_memory;

entity clocked_memory is
  generic (
    address: unsigned(7 downto 1);
    addr_width: integer range 1 to 16 := 8;
    granularity: integer range 1 to 4 := 1
  );
  port (
    reset_n_i : in std_ulogic := '1';
    clock_i : in std_ulogic;

    i2c_o  : out nsl_i2c.i2c.i2c_o;
    i2c_i  : in  nsl_i2c.i2c.i2c_i
  );
end clocked_memory;

architecture arch of clocked_memory is

  constant addr_byte_cnt: integer := (addr_width + 7) / 8;

  signal s_write : std_ulogic;
  signal s_rdata, s_wdata : std_ulogic_vector(8*granularity-1 downto 0);
  signal s_address : unsigned(8*addr_byte_cnt-1 downto 0);
  
begin

  slave: nsl_i2c.clocked.clocked_memory_controller
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

  ram: nsl_memory.ram.ram_1p
    generic map (
      addr_size_c => addr_width,
      data_size_c => 8*granularity
    )
    port map (
      clock_i => clock_i,
      write_en_i => s_write,
      address_i => s_address(addr_width-1 downto 0),
      write_data_i => s_wdata,
      read_data_o => s_rdata
      );

end arch;
