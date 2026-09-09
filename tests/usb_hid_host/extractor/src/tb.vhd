library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_usb, nsl_simulation;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;
use nsl_simulation.control.all;

entity tb is
end entity;

architecture beh of tb is

  constant fields_c: field_vector(0 to 3) := (
    0 => (byte_offset => 0, bit_offset => 0, width => 8),
    1 => (byte_offset => 1, bit_offset => 6, width => 4),
    2 => (byte_offset => 2, bit_offset => 2, width => 3),
    3 => (byte_offset => 4, bit_offset => 0, width => 16)
    );

  signal clock_s: std_ulogic := '0';
  signal reset_n_s: std_ulogic;
  signal report_s: nsl_amba.axi4_stream.bus_t;
  signal values_s: std_ulogic_vector(fields_width(fields_c) - 1 downto 0);
  signal valid_s: std_ulogic;

  signal done_s: boolean := false;

  function field_get(v: std_ulogic_vector; index: natural) return unsigned is
  begin
    return unsigned(
      v(field_offset(fields_c, index) + fields_c(index).width - 1
        downto field_offset(fields_c, index)));
  end function;

begin

  clock_gen: process is
  begin
    while not done_s loop
      clock_s <= '0';
      wait for 5 ns;
      clock_s <= '1';
      wait for 5 ns;
    end loop;
    wait;
  end process;

  reset_n_s <= '0', '1' after 30 ns;

  dut: hid_host_extractor
    generic map(
      fields_c => fields_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,
      report_i => report_s.m,
      report_o => report_s.s,
      values_o => values_s,
      valid_o => valid_s
      );

  stim: process is

    procedure frame_put(data: byte_string) is
    begin
      for i in data'range loop
        wait until falling_edge(clock_s);
        report_s.m <= transfer(report_cfg_c,
                               bytes => data(i to i),
                               last => i = data'high);
      end loop;
      wait until falling_edge(clock_s);
      report_s.m <= transfer_defaults(report_cfg_c);
    end procedure;

    procedure values_check(name: string;
                           f0, f1, f2, f3: natural) is
    begin
      wait until rising_edge(clock_s) and valid_s = '1' for 1 us;
      assert valid_s = '1'
        report name & ": no valid pulse"
        severity failure;
      assert field_get(values_s, 0) = to_unsigned(f0, 8)
        report name & ": field 0 mismatch"
        severity failure;
      assert field_get(values_s, 1) = to_unsigned(f1, 4)
        report name & ": field 1 mismatch"
        severity failure;
      assert field_get(values_s, 2) = to_unsigned(f2, 3)
        report name & ": field 2 mismatch"
        severity failure;
      assert field_get(values_s, 3) = to_unsigned(f3, 16)
        report name & ": field 3 mismatch"
        severity failure;
      wait until rising_edge(clock_s);
      assert valid_s = '0'
        report name & ": valid is not a pulse"
        severity failure;
    end procedure;

  begin
    report_s.m <= transfer_defaults(report_cfg_c);
    wait until reset_n_s = '1';

    frame_put(from_hex("a5805aff34120000"));
    values_check("full frame", 16#a5#, 16#a#, 6, 16#1234#);

    frame_put(from_hex("070004"));
    values_check("short frame zero-fill", 7, 0, 1, 0);

    frame_put(from_hex("ffffffffffffffff"));
    values_check("all ones", 16#ff#, 16#f#, 7, 16#ffff#);

    done_s <= true;
    terminate(0);
    wait;
  end process;

end architecture;
