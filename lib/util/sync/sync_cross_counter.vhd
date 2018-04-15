library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;

entity sync_cross_counter is
  generic(
    cycle_count : natural := 2;
    data_width : integer;
    decode_stage_count : natural := 1
    );
  port(
    p_in_clk : in std_ulogic;
    p_out_clk : in std_ulogic;
    p_in  : in unsigned(data_width-1 downto 0);
    p_out : out unsigned(data_width-1 downto 0)
    );
end sync_cross_counter;

architecture rtl of sync_cross_counter is

  signal s_in_gray, s_in_gray_sync, s_out_gray, s_out_bin: std_ulogic_vector(p_in'range);

begin

  in_gray_enc: util.gray.gray_encoder
    generic map(
      data_width => data_width
      )
    port map(
      p_binary => std_ulogic_vector(p_in),
      p_gray => s_in_gray
      );

  in_sync: util.sync.sync_reg
    generic map(
      cycle_count => 1,
      data_width => data_width
      )
    port map(
      p_clk => p_in_clk,
      p_in => s_in_gray,
      p_out => s_in_gray_sync
      );

  gray_sync: util.sync.sync_reg
    generic map(
      cycle_count => cycle_count,
      data_width => data_width
      )
    port map(
      p_clk => p_out_clk,
      p_in => s_in_gray_sync,
      p_out => s_out_gray
      );

  out_gray_dec: util.gray.gray_decoder
    generic map(
      data_width => data_width
      )
    port map(
      p_binary => s_out_bin,
      p_gray => s_out_gray
      );

  out_sync: util.sync.sync_reg
    generic map(
      cycle_count => decode_stage_count,
      data_width => data_width,
      cross_region => false
      )
    port map(
      p_clk => p_out_clk,
      p_in => s_out_bin,
      unsigned(p_out) => p_out
      );

end rtl;
