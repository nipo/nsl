library ieee;
use ieee.std_logic_1164.all;

library nsl;
use nsl.ftdi.all;
use nsl.fifo.all;

library util;
use util.sync.all;

library testing;
use testing.fifo.all;

entity tb is
end tb;

architecture arch of tb is

   signal s_ftdi_clk  : std_ulogic;
   signal s_ftdi_data : std_logic_vector(7 downto 0);
   signal s_ftdi_rxfn : std_ulogic;
   signal s_ftdi_txen : std_ulogic;
   signal s_ftdi_rdn  : std_ulogic;
   signal s_ftdi_wrn  : std_ulogic;
   signal s_ftdi_oen  : std_ulogic;

  constant width : integer := 8;

  type fifo is
  record 
    ready : std_ulogic;
    valid : std_ulogic;
    data : std_ulogic_vector(width-1 downto 0);
  end record;

  signal
    s_slave_gen_out,
    s_slave_gate_in,
    s_slave_check_in,
    s_slave_gate_out,
    s_master_gen_out,
    s_master_gate_in,
    s_master_check_in,
    s_master_gate_out: fifo;
  
  signal s_clk_master : std_ulogic;
  signal s_clk_slave : std_ulogic := '0';
  signal s_resetn_master_clk : std_ulogic;
  signal s_resetn_slave_clk : std_ulogic;
  signal s_resetn_master : std_ulogic;
  signal s_resetn_slave : std_ulogic;

  shared variable simend : boolean := false;

begin

  slave_reset_sync: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_slave,
      p_out => s_resetn_slave_clk,
      p_clk => s_clk_slave
      );

  slave_gen: testing.fifo.fifo_counter_generator
    generic map(
      width => width
      )
    port map(
      p_resetn => s_resetn_slave_clk,
      p_clk => s_clk_slave,

      p_valid => s_slave_gen_out.valid,
      p_ready => s_slave_gen_out.ready,
      p_data => s_slave_gen_out.data
      );

  slave_gen_fifo: nsl.fifo.fifo_sync
    generic map(
      data_width => width,
      depth => 128
      )
    port map(
      p_resetn => s_resetn_slave_clk,
      p_clk => s_clk_slave,

      p_in_data => s_slave_gen_out.data,
      p_in_valid => s_slave_gen_out.valid,
      p_in_ready => s_slave_gen_out.ready,

      p_out_data => s_slave_gate_out.data,
      p_out_ready => s_slave_gate_out.ready,
      p_out_valid => s_slave_gate_out.valid
      );

  slave_check: testing.fifo.fifo_counter_checker
    generic map(
      width => width
      )
    port map(
      p_resetn => s_resetn_slave_clk,
      p_clk => s_clk_slave,
      
      p_ready => s_slave_check_in.ready,
      p_valid => s_slave_check_in.valid,
      p_data => s_slave_check_in.data
      );

  slave_check_fifo: nsl.fifo.fifo_sync
    generic map(
      data_width => width,
      depth => 128
      )
    port map(
      p_resetn => s_resetn_slave_clk,
      p_clk => s_clk_slave,

      p_in_data => s_slave_gate_in.data,
      p_in_valid => s_slave_gate_in.valid,
      p_in_ready => s_slave_gate_in.ready,

      p_out_data => s_slave_check_in.data,
      p_out_ready => s_slave_check_in.ready,
      p_out_valid => s_slave_check_in.valid
      );

  slave_gate: nsl.ftdi.ft245_sync_fifo_slave
    port map(
      p_clk => s_clk_slave,

      p_ftdi_clk => s_ftdi_clk,
      p_ftdi_data => s_ftdi_data,
      p_ftdi_rxfn => s_ftdi_rxfn,
      p_ftdi_txen => s_ftdi_txen,
      p_ftdi_rdn => s_ftdi_rdn,
      p_ftdi_wrn => s_ftdi_wrn,
      p_ftdi_oen => s_ftdi_oen,

      p_out_data => s_slave_gate_out.data,
      p_out_valid => s_slave_gate_out.valid,
      p_out_ready => s_slave_gate_out.ready,

      p_in_data => s_slave_gate_in.data,
      p_in_ready => s_slave_gate_in.ready,
      p_in_valid => s_slave_gate_in.valid
      );

  master_reset_sync: util.sync.sync_rising_edge
    port map(
      p_in => s_resetn_master,
      p_out => s_resetn_master_clk,
      p_clk => s_clk_master
      );

  master_gen: testing.fifo.fifo_counter_generator
    generic map(
      width => width
      )
    port map(
      p_resetn => s_resetn_master_clk,
      p_clk => s_clk_master,

      p_valid => s_master_gen_out.valid,
      p_ready => s_master_gen_out.ready,
      p_data => s_master_gen_out.data
      );

  master_gen_fifo: nsl.fifo.fifo_sync
    generic map(
      data_width => width,
      depth => 128
      )
    port map(
      p_resetn => s_resetn_master_clk,
      p_clk => s_clk_master,

      p_in_data => s_master_gen_out.data,
      p_in_valid => s_master_gen_out.valid,
      p_in_ready => s_master_gen_out.ready,

      p_out_data => s_master_gate_out.data,
      p_out_ready => s_master_gate_out.ready,
      p_out_valid => s_master_gate_out.valid
      );

  master_check: testing.fifo.fifo_counter_checker
    generic map(
      width => width
      )
    port map(
      p_resetn => s_resetn_master_clk,
      p_clk => s_clk_master,
      
      p_ready => s_master_check_in.ready,
      p_valid => s_master_check_in.valid,
      p_data => s_master_check_in.data
      );

  master_check_fifo: nsl.fifo.fifo_sync
    generic map(
      data_width => width,
      depth => 128
      )
    port map(
      p_resetn => s_resetn_master_clk,
      p_clk => s_clk_master,
      
      p_in_data => s_master_gate_in.data,
      p_in_valid => s_master_gate_in.valid,
      p_in_ready => s_master_gate_in.ready,

      p_out_data => s_master_check_in.data,
      p_out_ready => s_master_check_in.ready,
      p_out_valid => s_master_check_in.valid
      );

  master_gate: nsl.ftdi.ft245_sync_fifo_master
    port map(
      p_clk => s_clk_master,
      p_resetn => s_resetn_master_clk,

      p_ftdi_clk => s_ftdi_clk,
      p_ftdi_data => s_ftdi_data,
      p_ftdi_rxfn => s_ftdi_rxfn,
      p_ftdi_txen => s_ftdi_txen,
      p_ftdi_rdn => s_ftdi_rdn,
      p_ftdi_wrn => s_ftdi_wrn,
      p_ftdi_oen => s_ftdi_oen,

      p_out_data => s_master_gate_out.data,
      p_out_valid => s_master_gate_out.valid,
      p_out_ready => s_master_gate_out.ready,

      p_in_data => s_master_gate_in.data,
      p_in_ready => s_master_gate_in.ready,
      p_in_valid => s_master_gate_in.valid
      );

  process
  begin
    s_resetn_master <= '0';
    s_resetn_slave <= '0';
    wait for 10 ns;
    s_resetn_slave <= '1';
    wait for 15 ns;
    s_resetn_master <= '1';
    wait for 2 us;
    simend := true;
    wait;
  end process;

  clock_gen: process(s_clk_slave)
  begin
    if not simend then
      s_clk_slave <= not s_clk_slave after 7 ns;
    end if;
  end process;

end;
