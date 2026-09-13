library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c, nsl_video, nsl_data, work;
use nsl_data.bytestream.all;

entity ddc_edid_slave is
  generic(
    modes_c : nsl_video.mode.mode_vector;
    manufacturer_c : string := "NSL";
    product_code_c : natural := 0;
    serial_c : natural := 0;
    week_c : natural := 0;
    year_c : natural := 2026;
    name_c : string := "";
    h_size_mm_c : natural := 0;
    v_size_mm_c : natural := 0;
    hdmi_c : boolean := false;
    audio_channels_c : natural := 0;
    address_c : unsigned(7 downto 1) := work.ddc.edid_address_c
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    i2c_i : in nsl_i2c.i2c.i2c_i;
    i2c_o : out nsl_i2c.i2c.i2c_o;

    selected_o : out std_ulogic
    );
end entity;

architecture beh of ddc_edid_slave is

  -- Built once, at elaboration, from the modes the design states.
  -- One block for a DVI sink, two for an HDMI one.
  constant edid_c : byte_string := nsl_video.edid.edid_data(
    modes => modes_c,
    manufacturer => manufacturer_c,
    product_code => product_code_c,
    serial => serial_c,
    week => week_c,
    year => year_c,
    name => name_c,
    h_size_mm => h_size_mm_c,
    v_size_mm => v_size_mm_c,
    hdmi => hdmi_c,
    audio_channels => audio_channels_c);

  -- Concatenation leaves the range up to the type, so it is said here
  alias edid_a : byte_string(0 to edid_c'length-1) is edid_c;

  signal addr_s : unsigned(7 downto 0);
  signal data_s : std_ulogic_vector(7 downto 0);

begin

  controller: nsl_i2c.clocked.clocked_memory_controller
    generic map(
      addr_bytes => 1,
      data_bytes => 1
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      slave_address_i => address_c,

      i2c_i => i2c_i,
      i2c_o => i2c_o,

      start_o => open,
      stop_o => open,
      selected_o => selected_o,

      addr_o => addr_s,

      r_ready_o => open,
      r_data_i => data_s,
      r_valid_i => '1',

      w_valid_o => open,
      w_data_o => open,
      w_ready_i => '1'
      );

  -- A source reads what is there and stops.  Anything past the end
  -- wraps rather than answering nothing, which is what a memory of
  -- this size does.
  data_s <= std_ulogic_vector(edid_a(to_integer(addr_s) mod edid_a'length));

end architecture;
