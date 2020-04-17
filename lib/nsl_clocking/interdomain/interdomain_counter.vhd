library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math, nsl_clocking;

entity interdomain_counter is
  generic(
    cycle_count_c : natural := 2;
    data_width_c : integer;
    decode_stage_count_c : natural := 1;
    input_is_gray_c : boolean := false;
    output_is_gray_c : boolean := false
    );
  port(
    clock_in_i : in std_ulogic;
    clock_out_i : in std_ulogic;
    data_i  : in unsigned(data_width_c-1 downto 0);
    data_o : out unsigned(data_width_c-1 downto 0)
    );
end interdomain_counter;

architecture rtl of interdomain_counter is

  signal gray_in_s, gray_in_resync_s, s_out_gray: std_ulogic_vector(data_i'range);

begin

  gray_in_s <= std_ulogic_vector(data_i) when input_is_gray_c else nsl_math.gray.bin_to_gray(data_i);

  in_sync: nsl_clocking.intradomain.intradomain_multi_reg
    generic map(
      cycle_count_c => 1,
      data_width_c => data_width_c
      )
    port map(
      clock_i => clock_in_i,
      data_i => gray_in_s,
      data_o => gray_in_resync_s
      );

  gray_sync: nsl_clocking.interdomain.interdomain_reg
    generic map(
      cycle_count_c => cycle_count_c,
      data_width_c => data_width_c
      )
    port map(
      clock_i => clock_out_i,
      data_i => gray_in_resync_s,
      data_o => s_out_gray
      );

  out_as_gray: if output_is_gray_c
  generate
    data_o <= unsigned(s_out_gray);
  end generate;

  out_as_bin: if not output_is_gray_c
  generate
    signal out_bin: unsigned(data_i'range);
  begin
    out_bin <= nsl_math.gray.gray_to_bin(s_out_gray);

    out_sync: nsl_clocking.intradomain.intradomain_multi_reg
      generic map(
        cycle_count_c => decode_stage_count_c,
        data_width_c => data_width_c
        )
      port map(
        clock_i => clock_out_i,
        data_i => std_ulogic_vector(out_bin),
        unsigned(data_o) => data_o
        );
  end generate;

end rtl;
