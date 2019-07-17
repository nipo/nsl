library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity sync_cross_counter is
  generic(
    cycle_count : natural := 2;
    data_width : integer;
    decode_stage_count : natural := 1;
    input_is_gray : boolean := false;
    output_is_gray : boolean := false
    );
  port(
    p_in_clk : in std_ulogic;
    p_out_clk : in std_ulogic;
    p_in  : in unsigned(data_width-1 downto 0);
    p_out : out unsigned(data_width-1 downto 0)
    );
end sync_cross_counter;

architecture rtl of sync_cross_counter is

  signal s_in_gray, s_in_gray_sync, s_out_gray: std_ulogic_vector(p_in'range);

begin

  s_in_gray <= std_ulogic_vector(p_in) when input_is_gray else util.gray.bin_to_gray(p_in);

  in_sync: util.sync.sync_multi_reg
    generic map(
      cycle_count => 1,
      data_width => data_width
      )
    port map(
      p_clk => p_in_clk,
      p_in => s_in_gray,
      p_out => s_in_gray_sync
      );

  gray_sync: util.sync.sync_cross_reg
    generic map(
      cycle_count => cycle_count,
      data_width => data_width
      )
    port map(
      p_clk => p_out_clk,
      p_in => s_in_gray_sync,
      p_out => s_out_gray
      );

  out_as_gray: if output_is_gray
  generate
    p_out <= unsigned(s_out_gray);
  end generate;

  out_as_bin: if not output_is_gray
  generate
    signal out_bin: unsigned(p_in'range);
  begin
    out_bin <= util.gray.gray_to_bin(s_out_gray);

    out_sync: util.sync.sync_multi_reg
      generic map(
        cycle_count => decode_stage_count,
        data_width => data_width
        )
      port map(
        p_clk => p_out_clk,
        p_in => std_ulogic_vector(out_bin),
        unsigned(p_out) => p_out
        );
  end generate;

end rtl;
