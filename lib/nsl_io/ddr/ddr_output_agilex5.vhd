library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity ddr_output is
  port(
    clock_i : in nsl_io.diff.diff_pair;
    d_i   : in std_ulogic_vector(1 downto 0);
    dd_o  : out std_ulogic
    );
end entity;

architecture alteran_tennm of ddr_output is

  component tennm_ph2_ddio_out is
    generic(
      mode      : string := "MODE_DDR";
      asclr_ena : string := "ASCLR_ENA_NONE";
      sclr_ena  : string := "SCLR_ENA_NONE"
      );
    port(
      areset   : in  std_logic := '0';
      sreset   : in  std_logic := '0';
      ena      : in  std_logic := '1';
      clk      : in  std_logic;
      datainlo : in  std_logic;
      datainhi : in  std_logic;
      dataout  : out std_logic
      );
  end component;

  -- component tennm_ph2_io_obuf is
  --   generic(
  --     open_drain              : string := "OPEN_DRAIN_OFF";
  --     buffer_usage            : string := "REGULAR";
  --     dynamic_pull_up_enabled : string := "FALSE";
  --     equalization            : string := "EQUALIZATION_OFF";
  --     io_standard             : string := "IO_STANDARD_IOSTD_OFF";
  --     rzq_id                  : string := "RZQ_ID_RZQ0";
  --     slew_rate               : string := "SLEW_RATE_SLOW";
  --     termination             : string := "TERMINATION_SERIES_OFF";
  --     toggle_speed            : string := "TOGGLE_SPEED_SLOW";
  --     usage_mode              : string := "USAGE_MODE_GPIO"
  --     );
  --   port(
  --     i  : in  std_logic;
  --     oe : in  std_logic := '1';
  --     o  : out std_logic
  --     );
  -- end component;

  signal ddio_out_s : std_logic;

begin

  ddio: tennm_ph2_ddio_out
    generic map(
      mode      => "MODE_DDR",
      asclr_ena => "ASCLR_ENA_NONE",
      sclr_ena  => "SCLR_ENA_NONE"
      )
    port map(
      clk      => clock_i.p,
      datainlo => d_i(0),
      datainhi => d_i(1),
      dataout  => dd_o, -- ddio_out_s,
      areset   => '0',
      sreset   => '0',
      ena      => '1'
      );

  -- obuf: tennm_ph2_io_obuf
  --   port map(
  --     i  => ddio_out_s,
  --     oe => '1',
  --     o  => dd_o
  --     );

end architecture;
