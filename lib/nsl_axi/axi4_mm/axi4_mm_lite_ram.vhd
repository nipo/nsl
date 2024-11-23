library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_axi, nsl_data, nsl_memory;
use nsl_axi.axi4_mm.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

entity axi4_mm_lite_ram is
  generic (
    config_c: config_t;
    byte_size_l2_c: natural := 12
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';

    axi_i: in master_t;
    axi_o: out slave_t
    );
end entity;

architecture rtl of axi4_mm_lite_ram is

  signal axi_write_s, axi_read_s, axi_read_done_s, axi_enable_s : std_ulogic;
  signal axi_wmask_s, axi_mem_wmask_s : std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
  signal axi_addr_s : unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);
  signal ram_addr_s : unsigned(byte_size_l2_c-1 downto config_c.data_bus_width_l2);
  signal axi_wbytes_s, axi_rbytes_s : byte_string(0 to 2**config_c.data_bus_width_l2-1);
  signal axi_wdata_s, axi_rdata_s : std_ulogic_vector(8*axi_wbytes_s'length-1 downto 0);

begin

  axi_slave: nsl_axi.axi4_mm.axi4_mm_lite_slave
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      axi_i => axi_i,
      axi_o => axi_o,

      address_o => axi_addr_s,

      w_data_o => axi_wbytes_s,
      w_mask_o => axi_wmask_s,
      w_ready_i => '1',
      w_valid_o => axi_write_s,

      r_data_i => axi_rbytes_s,
      r_ready_o => axi_read_s,
      r_valid_i => axi_read_done_s
      );

  ram: nsl_memory.ram.ram_1p_multi
    generic map(
      addr_size_c => ram_addr_s'length,
      word_size_c => 8,
      data_word_count_c => axi_mem_wmask_s'length
      )
    port map(
      clock_i => clock_i,
      address_i => ram_addr_s,
      enable_i => axi_enable_s,
      write_en_i   => axi_mem_wmask_s,
      write_data_i  => axi_wdata_s,
      read_data_o => axi_rdata_s
      );

  ram_addr_s <= resize(axi_addr_s, ram_addr_s'length);
  axi_wdata_s <= std_ulogic_vector(from_be(axi_wbytes_s));
  axi_rbytes_s <= to_be(unsigned(axi_rdata_s));
  axi_mem_wmask_s <= axi_wmask_s when axi_write_s = '1' else (others => '0');
  axi_enable_s <= axi_read_s or axi_write_s;

  read_done: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      axi_read_done_s <= axi_read_s;
    end if;

    if reset_n_i = '0' then
      axi_read_done_s <= '0';
    end if;
  end process;

end architecture;
