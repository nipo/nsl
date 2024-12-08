library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.apb.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;

entity apb_regmap is
  generic (
    config_c: config_t;
    reg_count_l2_c: natural := 10;
    endianness_c: endian_t := ENDIAN_LITTLE
    );
  port (
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic := '1';

    apb_i: in master_t;
    apb_o: out slave_t;

    reg_no_o : out integer range 0 to 2**reg_count_l2_c-1;
    w_value_o : out unsigned(8*(2**config_c.data_bus_width_l2)-1 downto 0);
    w_strobe_o : out std_ulogic;
    r_value_i : in unsigned(8*(2**config_c.data_bus_width_l2)-1 downto 0);
    r_strobe_o : out std_ulogic
    );
end entity;

architecture rtl of apb_regmap is

  signal address_s : unsigned(config_c.address_width-1 downto config_c.data_bus_width_l2);
  signal w_error_s: std_ulogic;
  signal w_data_s, r_data_s : byte_string(0 to 2**config_c.data_bus_width_l2-1);
  signal w_mask_s : std_ulogic_vector(0 to 2**config_c.data_bus_width_l2-1);
  
begin

  slave: nsl_amba.apb.apb_slave
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      address_o => address_s,
      w_data_o => w_data_s,
      w_mask_o => w_mask_s,
      w_valid_o => w_strobe_o,
      w_error_i => w_error_s,
      w_ready_i => '1',

      r_data_i => r_data_s,
      r_ready_o => r_strobe_o,
      r_valid_i => '1'
      );

  reg_no_o <= to_integer(address_s(address_s'right+reg_count_l2_c-1 downto address_s'right));
  w_error_s <= '1' when w_mask_s /= (w_mask_s'range => '1') else '0';
  w_value_o <= from_endian(w_data_s, endianness_c);
  r_data_s <= to_endian(r_value_i, endianness_c);

end architecture;
