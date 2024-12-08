library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_memory;
use nsl_amba.apb.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

entity apb_ram is
  generic (
    config_c: config_t;
    byte_size_l2_c: positive
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    apb_i: in master_t;
    apb_o: out slave_t
    );
end entity;

architecture rtl of apb_ram is

  signal apb_write_s, apb_read_s, apb_read_done_s, apb_enable_s : std_ulogic;
  signal apb_wmask_s, apb_mem_wmask_s : std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
  signal apb_addr_s : unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);
  signal ram_addr_s : unsigned(byte_size_l2_c-1 downto config_c.data_bus_width_l2);
  signal apb_wbytes_s, apb_rbytes_s : byte_string(0 to 2**config_c.data_bus_width_l2-1);
  signal apb_wdata_s, apb_rdata_s : std_ulogic_vector(8*apb_wbytes_s'length-1 downto 0);

begin

  apb_slave: nsl_amba.apb.apb_slave
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      address_o => apb_addr_s,

      w_data_o => apb_wbytes_s,
      w_mask_o => apb_wmask_s,
      w_ready_i => '1',
      w_valid_o => apb_write_s,

      r_data_i => apb_rbytes_s,
      r_ready_o => apb_read_s,
      r_valid_i => apb_read_done_s
      );

  ram: nsl_memory.ram.ram_1p_multi
    generic map(
      addr_size_c => ram_addr_s'length,
      word_size_c => 8,
      data_word_count_c => apb_mem_wmask_s'length
      )
    port map(
      clock_i => clock_i,
      address_i => ram_addr_s,
      enable_i => apb_enable_s,
      write_en_i   => apb_mem_wmask_s,
      write_data_i  => apb_wdata_s,
      read_data_o => apb_rdata_s
      );

  ram_addr_s <= resize(apb_addr_s, ram_addr_s'length);
  apb_wdata_s <= std_ulogic_vector(from_be(apb_wbytes_s));
  apb_rbytes_s <= to_be(unsigned(apb_rdata_s));
  apb_mem_wmask_s <= apb_wmask_s when apb_write_s = '1' else (others => '0');
  apb_enable_s <= apb_read_s or apb_write_s;

  read_done: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if apb_read_s = '1' and apb_read_done_s = '0' then
        apb_read_done_s <= '1';
      elsif apb_read_done_s = '1' then
        apb_read_done_s <= '0';
      end if;
    end if;

    if reset_n_i = '0' then
      apb_read_done_s <= '0';
    end if;
  end process;

end architecture;
