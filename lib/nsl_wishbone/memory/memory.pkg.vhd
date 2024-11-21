library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use work.wishbone.all;

package memory is

  component wishbone_ram_controller is
    generic(
      wb_config_c : wb_config_t;
      ram_byte_size_l2_c : natural
      );
    port(
      clock_i : std_ulogic;
      reset_n_i : std_ulogic;

      enable_o : out std_ulogic;
      address_o : out unsigned(ram_byte_size_l2_c-1 downto wb_address_lsb(wb_config_c));

      write_enable_o : out std_ulogic_vector(wb_sel_width(wb_config_c)-1 downto 0);
      write_data_o : out std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);
      read_data_i : in std_ulogic_vector(wb_data_width(wb_config_c)-1 downto 0);

      wb_i : in wb_req_t;
      wb_o : out wb_ack_t
      );
  end component;

  component wishbone_rom is
    generic(
      wb_config_c : wb_config_t;
      contents_c : nsl_data.bytestream.byte_string
      );
    port(
      clock_i : std_ulogic;
      reset_n_i : std_ulogic;

      wb_i : in wb_req_t;
      wb_o : out wb_ack_t
      );
  end component;

  component wishbone_ram is
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
  end component;

  component wishbone_dpram is
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
  end component;

end package memory;
