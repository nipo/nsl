library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math, nsl_logic, nsl_memory, nsl_data;
use work.wishbone.all;
use nsl_logic.bool;
use nsl_data.endian.all;

entity wishbone_dpram is
  generic(
    a_wb_config_c : wb_config_t;
    b_wb_config_c : wb_config_t;
    byte_size_l2_c : natural
    );
  port(
    a_clock_i : std_ulogic;
    a_reset_n_i : std_ulogic;
    a_wb_i : in wb_req_t;
    a_wb_o : out wb_ack_t;

    b_clock_i : std_ulogic;
    b_reset_n_i : std_ulogic;
    b_wb_i : in wb_req_t;
    b_wb_o : out wb_ack_t
    );
end entity;

architecture beh of wishbone_dpram is

  signal a_address_s : unsigned(byte_size_l2_c-1 downto wb_address_lsb(a_wb_config_c));
  signal a_wen_s : std_ulogic_vector(wb_sel_width(a_wb_config_c)-1 downto 0);
  signal a_wdata_s, a_rdata_s: std_ulogic_vector(wb_data_width(a_wb_config_c)-1 downto 0);
  signal a_enable_s : std_ulogic;

  signal b_address_s : unsigned(byte_size_l2_c-1 downto wb_address_lsb(b_wb_config_c));
  signal b_wen_s : std_ulogic_vector(wb_sel_width(b_wb_config_c)-1 downto 0);
  signal b_wdata_s, b_rdata_s: std_ulogic_vector(wb_data_width(b_wb_config_c)-1 downto 0);
  signal b_enable_s : std_ulogic;
  
begin

  a_controller: work.memory.wishbone_ram_controller
    generic map(
      wb_config_c => a_wb_config_c,
      ram_byte_size_l2_c => byte_size_l2_c
      )
    port map(
      clock_i => a_clock_i,
      reset_n_i => a_reset_n_i,

      enable_o => a_enable_s,
      address_o => a_address_s,

      write_enable_o => a_wen_s,
      write_data_o => a_wdata_s,
      read_data_i => a_rdata_s,

      wb_i => a_wb_i,
      wb_o => a_wb_o
      );

  b_controller: work.memory.wishbone_ram_controller
    generic map(
      wb_config_c => b_wb_config_c,
      ram_byte_size_l2_c => byte_size_l2_c
      )
    port map(
      clock_i => b_clock_i,
      reset_n_i => b_reset_n_i,

      enable_o => b_enable_s,
      address_o => b_address_s,

      write_enable_o => b_wen_s,
      write_data_o => b_wdata_s,
      read_data_i => b_rdata_s,

      wb_i => b_wb_i,
      wb_o => b_wb_o
      );
  
  memory: nsl_memory.ram.ram_2p
    generic map(
      a_addr_size_c => a_address_s'length,
      a_data_byte_count_c => wb_sel_width(a_wb_config_c),
      b_addr_size_c => b_address_s'length,
      b_data_byte_count_c => wb_sel_width(b_wb_config_c),
      registered_output_c => false
      )
    port map(
      a_clock_i => a_clock_i,
      a_enable_i => a_enable_s,
      a_address_i => a_address_s,
      a_write_en_i => a_wen_s,
      a_data_i => a_wdata_s,
      a_data_o => a_rdata_s,

      b_clock_i => b_clock_i,
      b_enable_i => b_enable_s,
      b_address_i => b_address_s,
      b_write_en_i => b_wen_s,
      b_data_i => b_wdata_s,
      b_data_o => b_rdata_s
      );
  
end architecture;
