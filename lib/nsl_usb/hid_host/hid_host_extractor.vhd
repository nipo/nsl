library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_usb;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_usb.hid_host.all;

entity hid_host_extractor is
  generic(
    fields_c: field_vector
    );
  port(
    reset_n_i: in std_ulogic;
    clock_i: in std_ulogic;

    report_i: in nsl_amba.axi4_stream.master_t;
    report_o: out nsl_amba.axi4_stream.slave_t;

    values_o: out std_ulogic_vector;
    valid_o: out std_ulogic
    );
begin

  assert fields_c'length <= field_count_max_c
    report "Too many fields"
    severity failure;

  assert values_o'length = fields_width(fields_c)
    report "values_o width must be fields_width(fields_c)"
    severity failure;

end entity;

architecture beh of hid_host_extractor is

  constant values_max_width_c: natural := field_count_max_c * 16;

  type regs_t is
  record
    buf: byte_string(0 to report_length_max_c - 1);
    index: natural range 0 to report_length_max_c;
    values: std_ulogic_vector(values_max_width_c - 1 downto 0);
    valid: std_ulogic;
  end record;

  signal r, rin: regs_t;

  function fields_extract(buf: byte_string) return std_ulogic_vector is
    variable ret: std_ulogic_vector(values_max_width_c - 1 downto 0)
      := (others => '0');
    variable bit_index: natural;
    variable off: natural := 0;
  begin
    for f in fields_c'range loop
      for k in 0 to fields_c(f).width - 1 loop
        bit_index := fields_c(f).byte_offset * 8 + fields_c(f).bit_offset + k;
        if bit_index < report_length_max_c * 8 then
          ret(off + k) := buf(bit_index / 8)(bit_index mod 8);
        end if;
      end loop;
      off := off + fields_c(f).width;
    end loop;
    return ret;
  end function;

begin

  regs: process(reset_n_i, clock_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.index <= 0;
      r.buf <= (others => x"00");
      r.values <= (others => '0');
      r.valid <= '0';
    end if;
  end process;

  transition: process(r, report_i) is
    variable buf: byte_string(0 to report_length_max_c - 1);
  begin
    rin <= r;

    rin.valid <= '0';

    if is_valid(report_cfg_c, report_i) then
      buf := r.buf;
      if r.index < report_length_max_c then
        buf(r.index) := bytes(report_cfg_c, report_i)(0);
        rin.buf <= buf;
        rin.index <= r.index + 1;
      end if;

      if is_last(report_cfg_c, report_i) then
        rin.values <= fields_extract(buf);
        rin.valid <= '1';
        rin.index <= 0;
        rin.buf <= (others => x"00");
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    values_o <= r.values(values_o'length - 1 downto 0);
    valid_o <= r.valid;
  end process;

  report_o <= accept(report_cfg_c, true);

end architecture;
