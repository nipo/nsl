library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.spi.all;
use nsl.framed.all;
use nsl.fifo.all;

entity spi_framed_ctrl is
  generic(
    width : natural;
    msb_first : boolean := true
    );
  port(
    p_clk    : in std_ulogic;
    p_resetn : in std_ulogic;

    p_sck    : out std_ulogic;
    p_sck_en : out std_ulogic;
    p_mosi   : out std_ulogic;
    p_miso   : in  std_ulogic;
    p_csn    : out std_ulogic;

    p_cmd_val   : in nsl.framed.framed_req;
    p_cmd_ack   : out nsl.framed.framed_ack;

    p_rsp_val  : out nsl.framed.framed_req;
    p_rsp_ack  : in nsl.framed.framed_ack
    );
end entity;

architecture rtl of spi_framed_ctrl is

  signal s_cmd_ack: std_ulogic;
  signal r_last: std_ulogic;
  signal run: std_ulogic;
  
begin

  master: spi_master
    generic map(
      width => 8,
      msb_first => msb_first
      )
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,

      p_sck => p_sck,
      p_sck_en => p_sck_en,
      p_mosi => p_mosi,
      p_miso => p_miso,
      p_csn => p_csn,

      p_run => run,

      p_miso_data => p_rsp_val.data,
      p_miso_ready => p_rsp_ack.ready,
      p_miso_valid => p_rsp_val.valid,

      p_mosi_data => p_cmd_val.data,
      p_mosi_valid => p_cmd_val.valid,
      p_mosi_ready => s_cmd_ack
      );

  run <= not r_last;
  p_rsp_val.last <= r_last;
  p_cmd_ack.ready <= s_cmd_ack;

  last: process(p_clk)
  begin
    if rising_edge(p_clk) then
      if p_cmd_val.valid = '1' and s_cmd_ack = '1' then
        r_last <= p_cmd_val.last;
      end if;
    end if;
  end process;

end architecture;
