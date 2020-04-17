library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb is
end tb;

library nsl_clocking, nsl_bnoc, nsl_coresight, util, signalling;

architecture arch of tb is

  signal s_clk : std_ulogic := '0';
  signal s_resetn_clk : std_ulogic;
  signal s_resetn_async : std_ulogic;

  signal s_swd_master_o : nsl_coresight.swd.swd_master_o;
  signal s_swd_master_i : nsl_coresight.swd.swd_master_i;
  signal s_swd_slave_o : nsl_coresight.swd.swd_slave_o;
  signal s_swd_slave_i : nsl_coresight.swd.swd_slave_i;
  signal s_srst : std_logic;

  signal s_ap_resetn : std_ulogic;
  signal s_ap_sel : unsigned(7 downto 0);
  signal s_ap_a : unsigned(5 downto 0);
  signal s_ap_rdata : unsigned(31 downto 0);
  signal s_ap_ready : std_ulogic;
  signal s_ap_rok : std_ulogic;
  signal s_ap_ren : std_ulogic;
  signal s_ap_wdata : unsigned(31 downto 0);
  signal s_ap_wen : std_ulogic;

  signal s_done : std_ulogic_vector(0 to 1);

  signal s_cmd_val_fifo, s_rsp_val_fifo : nsl_bnoc.framed.framed_req;
  signal s_cmd_ack_fifo, s_rsp_ack_fifo : nsl_bnoc.framed.framed_ack;
  signal s_swd_cmd_val, s_swd_rsp_val : nsl_bnoc.framed.framed_req;
  signal s_swd_cmd_ack, s_swd_rsp_ack : nsl_bnoc.framed.framed_ack;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => s_resetn_async,
      data_o => s_resetn_clk,
      clock_i => s_clk
      );

  swdio: process (s_swd_master_o, s_swd_slave_o)
    variable dio : std_logic;
  begin
    dio := '1';

    if s_swd_master_o.dio.en = '1' and s_swd_slave_o.dio.en = '1' then
      assert false
        report "Write conflict on SWDIO line"
        severity warning;
      dio := 'L';
    elsif s_swd_master_o.dio.en = '1' and s_swd_slave_o.dio.en = '0' then
      dio := s_swd_master_o.dio.v;
    elsif s_swd_slave_o.dio.en = '1' and s_swd_master_o.dio.en = '0' then
      dio := s_swd_slave_o.dio.v;
    else
      dio := 'H';
    end if;

    s_swd_slave_i.clk <= s_swd_master_o.clk;
    s_swd_slave_i.dio <= dio;
    s_swd_master_i.dio <= dio;
  end process;

  swdap: nsl_coresight.testing.swdap
    port map(
      p_swd_c => s_swd_slave_o,
      p_swd_s => s_swd_slave_i,

      p_swd_resetn => s_ap_resetn,
      p_ap_sel => s_ap_sel,
      p_ap_a => s_ap_a,
      p_ap_rdata => s_ap_rdata,
      p_ap_ready => s_ap_ready,
      p_ap_ren => s_ap_ren,
      p_ap_rok => s_ap_rok,
      p_ap_wdata => s_ap_wdata,
      p_ap_wen => s_ap_wen
      );

  ap: nsl_coresight.testing.ap_sim
    port map(
      p_clk => s_swd_slave_i.clk,
      p_resetn => s_ap_resetn,
      p_ap => s_ap_sel,
      p_a => s_ap_a,
      p_rdata => s_ap_rdata,
      p_ready => s_ap_ready,
      p_ren => s_ap_ren,
      p_rok => s_ap_rok,
      p_wdata => s_ap_wdata,
      p_wen => s_ap_wen
      );

  swd_endpoint: nsl_bnoc.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,

      p_cmd_in_val => s_cmd_val_fifo,
      p_cmd_in_ack => s_cmd_ack_fifo,
      p_rsp_out_val => s_rsp_val_fifo,
      p_rsp_out_ack => s_rsp_ack_fifo,
      
      p_cmd_out_val => s_swd_cmd_val,
      p_cmd_out_ack => s_swd_cmd_ack,
      p_rsp_in_val => s_swd_rsp_val,
      p_rsp_in_ack => s_swd_rsp_ack
      );

  dp: nsl_coresight.dp.dp_framed_swdp
    port map(
      p_clk  => s_clk,
      p_resetn => s_resetn_clk,
      
      p_cmd_val => s_swd_cmd_val,
      p_cmd_ack => s_swd_cmd_ack,

      p_rsp_val => s_swd_rsp_val,
      p_rsp_ack => s_swd_rsp_ack,

      p_swd_o => s_swd_master_o,
      p_swd_i => s_swd_master_i
      );

  gen: nsl_bnoc.testing.framed_file_reader
    generic map(
      filename => "swd_commands.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_out_val => s_cmd_val_fifo,
      p_out_ack => s_cmd_ack_fifo,
      p_done => s_done(0)
      );

  check0: nsl_bnoc.testing.framed_file_checker
    generic map(
      filename => "swd_responses.txt"
      )
    port map(
      p_resetn => s_resetn_clk,
      p_clk => s_clk,
      p_in_val => s_rsp_val_fifo,
      p_in_ack => s_rsp_ack_fifo,
      p_done => s_done(1)
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
    if s_done /= "11" then
      s_clk <= not s_clk after 5 ns;
    end if;
  end process;

end;
