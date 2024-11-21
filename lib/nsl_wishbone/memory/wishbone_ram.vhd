library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_logic, nsl_memory, nsl_data;
use work.wishbone.all;
use nsl_logic.bool;
use nsl_data.endian.all;

entity wishbone_ram is
  generic(
    wb_config_c : wb_config_t;
    byte_size_l2_c : natural
    );
  port(
    clock_i : std_ulogic;
    reset_n_i : std_ulogic;

    wb_i : in wb_req_t;
    wb_o : out wb_ack_t
    );
end entity;

architecture beh of wishbone_ram is

  signal ram_address_s : unsigned(byte_size_l2_c-1 downto wb_address_lsb(wb_config_c));
  signal ram_wen_s : std_ulogic_vector(wb_sel_width(wb_config_c)-1 downto 0);
  signal ram_wdata_s, ram_rdata_s: std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
  signal ram_enable_s : std_ulogic;
  
begin

  controller: work.memory.wishbone_ram_controller
    generic map(
      wb_config_c => wb_config_c,
      ram_byte_size_l2_c => byte_size_l2_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      enable_o => ram_enable_s,
      address_o => ram_address_s,

      write_enable_o => ram_wen_s,
      write_data_o => ram_wdata_s,
      read_data_i => ram_rdata_s,

      wb_i => wb_i,
      wb_o => wb_o
      );
  
  memory: nsl_memory.ram.ram_1p_multi
    generic map(
      addr_size_c => ram_address_s'length,
      word_size_c => 2**wb_config_c.port_granularity_l2,
      data_word_count_c => wb_sel_width(wb_config_c)
      )
    port map(
      clock_i => clock_i,

      address_i => ram_address_s,
      enable_i => ram_enable_s,
      write_en_i => ram_wen_s,
      write_data_i => ram_wdata_s,
      read_data_o => ram_rdata_s
      );
  
end architecture;
