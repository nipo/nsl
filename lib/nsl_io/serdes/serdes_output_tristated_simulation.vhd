library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity serdes_output_tristated is
  generic(
    left_first_c : boolean := false;
    ddr_mode_c : boolean := false;
    to_delay_c : boolean := false;
    ratio_c : positive
    );
  port(
    serial_clock_i : in std_ulogic;
    parallel_clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    parallel_i : in std_ulogic_vector(0 to ratio_c-1);
    output_enable_i : in std_ulogic_vector(0 to ratio_c/2-1);

    pad_o : out nsl_io.io.tristated
    );
end entity;

architecture simulation of serdes_output_tristated is

  -- Sent from left to right, always.  The enable is stretched to one
  -- bit per serial bit here so that both shift out together; the pad
  -- logic of a real device holds half as many, which the interface
  -- already reflects.
  signal word_s: std_ulogic_vector(0 to ratio_c-1);
  signal enable_s: std_ulogic_vector(0 to ratio_c-1);

begin

  assert (ratio_c mod 2) = 0
    report "Tristate control covers pairs of bits, so ratio must be even"
    severity failure;

  assert ratio_c >= 4
    report "Serdes is only for parallel >= 4"
    severity failure;

  word_take: process(parallel_clock_i) is
  begin
    if rising_edge(parallel_clock_i) then
      if left_first_c then
        word_s <= parallel_i;
        for i in 0 to ratio_c/2-1
        loop
          enable_s(i * 2) <= output_enable_i(i);
          enable_s(i * 2 + 1) <= output_enable_i(i);
        end loop;
      else
        for i in 0 to ratio_c-1
        loop
          word_s(ratio_c-1-i) <= parallel_i(i);
        end loop;
        for i in 0 to ratio_c/2-1
        loop
          enable_s(ratio_c-2 - i * 2) <= output_enable_i(i);
          enable_s(ratio_c-1 - i * 2) <= output_enable_i(i);
        end loop;
      end if;
    end if;
  end process;

  sdr_mode: if not ddr_mode_c
  generate
    signal shreg_s, enable_shreg_s: std_ulogic_vector(0 to ratio_c-1);
    signal bits_left_s: integer range 0 to ratio_c;
  begin
    shift: process(serial_clock_i, reset_n_i) is
    begin
      if rising_edge(serial_clock_i) then
        pad_o.v <= shreg_s(0);
        pad_o.en <= enable_shreg_s(0);
        shreg_s <= shreg_s(1 to ratio_c-1) & "-";
        enable_shreg_s <= enable_shreg_s(1 to ratio_c-1) & "0";
        if bits_left_s = 0 then
          bits_left_s <= ratio_c-1;
          shreg_s <= word_s;
          enable_shreg_s <= enable_s;
        else
          bits_left_s <= bits_left_s - 1;
        end if;
      end if;

      if reset_n_i = '0' then
        bits_left_s <= 0;
        pad_o.en <= '0';
      end if;
    end process;
  end generate;

  ddr_mode: if ddr_mode_c
  generate
    signal shreg_s, enable_shreg_s: std_ulogic_vector(0 to ratio_c-1);
    signal bits_left_s: integer range 0 to ratio_c;
  begin
    shift: process(serial_clock_i, reset_n_i) is
    begin
      if rising_edge(serial_clock_i) or falling_edge(serial_clock_i) then
        pad_o.v <= shreg_s(0);
        pad_o.en <= enable_shreg_s(0);
        shreg_s <= shreg_s(1 to ratio_c-1) & "-";
        enable_shreg_s <= enable_shreg_s(1 to ratio_c-1) & "0";
        if bits_left_s = 0 then
          bits_left_s <= ratio_c-1;
          shreg_s <= word_s;
          enable_shreg_s <= enable_s;
        else
          bits_left_s <= bits_left_s - 1;
        end if;
      end if;

      if reset_n_i = '0' then
        bits_left_s <= 0;
        pad_o.en <= '0';
      end if;
    end process;
  end generate;

end architecture;
