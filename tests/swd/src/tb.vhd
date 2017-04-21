library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl;
use nsl.util.all;
use nsl.flit.all;
use nsl.swd.all;

library testing;
use testing.swd.all;
use testing.flit.all;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_clk2 : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_clk2 : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_swclk : std_logic;
  signal s_swdio : std_logic;

  signal s_dap_a : unsigned(1 downto 0);
  signal s_dap_ad : std_logic;
  signal s_dap_rdata : unsigned(31 downto 0);
  signal s_dap_ready : std_logic;
  signal s_dap_ren : std_logic;
  signal s_dap_wdata : unsigned(31 downto 0);
  signal s_dap_wen : std_logic;

  signal s_in_val    : flit_cmd_array(1 downto 0);
  signal s_in_ack    : flit_ack_array(1 downto 0);
  signal s_out_val   : flit_cmd_array(1 downto 0);
  signal s_out_ack   : flit_ack_array(1 downto 0);
  signal s_swdio_o   : std_ulogic;
  signal s_swdio_oe  : std_ulogic;

  signal s_done : std_ulogic;

begin

  reset_sync_clk: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk,
      p_clk => s_clk
      );

  reset_sync_clk2: nsl.util.reset_synchronizer
    port map(
      p_resetn => s_resetn_async,
      p_resetn_sync => s_resetn_clk2,
      p_clk => s_clk2
      );

  swdap: testing.swd.swdap
    port map(
      p_swclk => s_swclk,
      p_swdio => s_swdio,
      p_dap_a => s_dap_a,
      p_dap_ad => s_dap_ad,
      p_dap_rdata => s_dap_rdata,
      p_dap_ready => s_dap_ready,
      p_dap_ren => s_dap_ren,
      p_dap_wdata => s_dap_wdata,
      p_dap_wen => s_dap_wen
      );

  dap: testing.swd.dap_sim
    port map(
      p_clk => s_swclk,
      p_dap_a => s_dap_a,
      p_dap_ad => s_dap_ad,
      p_dap_rdata => s_dap_rdata,
      p_dap_ready => s_dap_ready,
      p_dap_ren => s_dap_ren,
      p_dap_wdata => s_dap_wdata,
      p_dap_wen => s_dap_wen
      );

  swd_master: nsl.swd.swd_flit_master
    port map(
      p_resetn => s_resetn_clk2,
      p_clk => s_clk2,

      p_in_val => s_in_val(1),
      p_in_ack => s_in_ack(1),
      p_out_val => s_out_val(1),
      p_out_ack => s_out_ack(1),

      p_swclk => s_swclk,
      p_swdio_o => s_swdio_o,
      p_swdio_i => s_swdio,
      p_swdio_oe => s_swdio_oe
      );

  s_swdio <= s_swdio_o when s_swdio_oe = '1' else 'Z';

  gen: testing.flit.flit_file_reader
    generic map(
      filename => "swd_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_in_val(0),
      p_out_ack => s_in_ack(0),
      p_done => open
      );

  check0: testing.flit.flit_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_out_val(0),
      p_in_ack => s_out_ack(0),
      p_done => s_done
      );

  cmd_fifo: nsl.flit.flit_fifo_async
    generic map(
      depth => 128
      )
    port map(
      p_resetn => s_resetn_async,

      p_in_clk => s_clk,
      p_in_val => s_in_val(0),
      p_in_ack => s_in_ack(0),

      p_out_clk => s_clk2,
      p_out_val => s_in_val(1),
      p_out_ack => s_in_ack(1)
      );

  rsp_fifo: nsl.flit.flit_fifo_async
    generic map(
      depth => 128
      )
    port map(
      p_resetn => s_resetn_async,

      p_in_clk => s_clk2,
      p_in_val => s_out_val(1),
      p_in_ack => s_out_ack(1),

      p_out_clk => s_clk,
      p_out_val => s_out_val(0),
      p_out_ack => s_out_ack(0)
      );

  process
  begin
    s_resetn_async <= '0';
    wait for 100 ns;
    s_resetn_async <= '1';
    wait;
  end process;

  clock_gen: process(s_clk)
  begin
    if s_done /= '1' then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

  clock_gen2: process(s_clk2)
  begin
    if s_done /= '1' then
      s_clk2 <= not s_clk2 after 83 ns;
    end if;
  end process;

end;
