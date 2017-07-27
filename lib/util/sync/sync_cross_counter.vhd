library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library util;
use util.gray.gray_encoder;
use util.gray.gray_decoder;
use util.sync.sync_reg;

entity sync_cross_counter is
  generic(
    cycle_count : natural := 2;
    data_width : integer
    );
  port(
    p_in_clk : in std_ulogic;
    p_out_clk : in std_ulogic;
    p_in  : in unsigned(data_width-1 downto 0);
    p_out : out unsigned(data_width-1 downto 0)
    );
end sync_cross_counter;

architecture rtl of sync_cross_counter is

  signal s_in_gray, r_in_gray, r_out_gray, s_out_bin: std_ulogic_vector(p_in'range);

begin

  in_gray_enc: gray_encoder
    generic map(
      data_width => data_width
      )
    port map(
      p_binary => std_ulogic_vector(p_in),
      p_gray => s_in_gray
      );

  in_sync: sync_reg
    generic map(
      cycle_count => 1,
      data_width => data_width
      )
    port map(
      p_clk => p_in_clk,
      p_in => s_in_gray,
      p_out => r_in_gray
      );

  out_sync: sync_reg
    generic map(
      cycle_count => 2,
      data_width => data_width
      )
    port map(
      p_clk => p_out_clk,
      p_in => r_in_gray,
      p_out => r_out_gray
      );

  out_gray_dec: gray_decoder
    generic map(
      data_width => data_width
      )
    port map(
      p_binary => s_out_bin,
      p_gray => r_out_gray
      );

  p_out <= unsigned(s_out_bin);

end rtl;
