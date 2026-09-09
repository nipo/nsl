library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_usb;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;
use nsl_usb.hid_program.all;

entity hid_host_mouse is
  generic(
    clock_rate_c: natural := 12_000_000;
    expected_vid_c: unsigned(15 downto 0) := x"0000";
    expected_pid_c: unsigned(15 downto 0) := x"0000"
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    bus_o: out nsl_usb.io.usb_io_c;
    bus_i: in nsl_usb.io.usb_io_s;

    identity_o: out device_identity_t;
    status_o: out hid_host_status_t;
    matched_o: out std_ulogic;

    buttons_o: out byte;
    dx_o: out signed(7 downto 0);
    dy_o: out signed(7 downto 0);
    valid_o: out std_ulogic
    );
end entity;

architecture beh of hid_host_mouse is

  -- Boot-protocol mouse input report: buttons, X delta, Y delta.
  constant fields_c: field_vector(0 to 2) := (
    0 => (byte_offset => 0, bit_offset => 0, width => 8),
    1 => (byte_offset => 1, bit_offset => 0, width => 8),
    2 => (byte_offset => 2, bit_offset => 0, width => 8)
    );

  type regs_t is
  record
    buttons: byte;
    dx: signed(7 downto 0);
    dy: signed(7 downto 0);
    valid: std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal report_s: nsl_amba.axi4_stream.bus_t;
  signal identity_s: device_identity_t;
  signal values_s: std_ulogic_vector(fields_width(fields_c) - 1 downto 0);
  signal extracted_s: std_ulogic;
  signal matched_s: std_ulogic;

begin

  engine: hid_host_engine
    generic map(
      program_c => hid_program(hid_program_config_t'(
        poll_interval_ms => 8,
        report_length => 8,
        configuration_value => 1)),
      clock_rate_c => clock_rate_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      bus_o => bus_o,
      bus_i => bus_i,
      identity_o => identity_s,
      status_o => status_o,
      report_o => report_s.m,
      report_i => report_s.s
      );

  extractor: hid_host_extractor
    generic map(
      fields_c => fields_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,
      report_i => report_s.m,
      report_o => report_s.s,
      values_o => values_s,
      valid_o => extracted_s
      );

  matched_s <= '1' when identity_s.valid
               and identity_s.if_class = x"03"
               and identity_s.if_subclass = x"01"
               and identity_s.if_protocol = x"02"
               and (expected_vid_c = x"0000" or identity_s.vid = expected_vid_c)
               and (expected_pid_c = x"0000" or identity_s.pid = expected_pid_c)
               else '0';

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.buttons <= x"00";
      r.dx <= (others => '0');
      r.dy <= (others => '0');
      r.valid <= '0';
    end if;
  end process;

  transition: process(r, values_s, extracted_s, matched_s) is
  begin
    rin <= r;

    rin.valid <= '0';

    if extracted_s = '1' and matched_s = '1' then
      rin.buttons <= values_s(7 downto 0);
      rin.dx <= signed(values_s(15 downto 8));
      rin.dy <= signed(values_s(23 downto 16));
      rin.valid <= '1';
    end if;
  end process;

  moore: process(r) is
  begin
    buttons_o <= r.buttons;
    dx_o <= r.dx;
    dy_o <= r.dy;
    valid_o <= r.valid;
  end process;

  identity_o <= identity_s;
  matched_o <= matched_s;

end architecture;
