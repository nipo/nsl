library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_clocking, nsl_i2c, nsl_simulation;

entity tb is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    cmd_i_data : in std_ulogic_vector(7 downto 0);
    cmd_i_valid : in std_ulogic;
    cmd_i_last : in std_ulogic;
    cmd_o_ready : out std_ulogic;
    rsp_o_data : out std_ulogic_vector(7 downto 0);
    rsp_o_valid : out std_ulogic;
    rsp_o_last : out std_ulogic;
    rsp_i_ready : in std_ulogic
    );
    
end tb;

architecture arch of tb is

  signal s_resetn_clk : std_ulogic;

  signal s_i2c : nsl_i2c.i2c.i2c_i;
  signal s_i2c_slave, s_i2c_master : nsl_i2c.i2c.i2c_o;

  signal s_i2c_cmd, s_i2c_rsp : nsl_bnoc.framed.framed_bus;

begin

  reset_sync_clk: nsl_clocking.async.async_edge
    port map(
      data_i => reset_n_i,
      data_o => s_resetn_clk,
      clock_i => clock_i
      );

  i2c_endpoint: nsl_bnoc.routed.routed_endpoint
    port map(
      p_resetn => s_resetn_clk,
      p_clk => clock_i,

      p_cmd_in_val.data => cmd_i_data,
      p_cmd_in_val.valid => cmd_i_valid,
      p_cmd_in_val.last => cmd_i_last,
      p_cmd_in_ack.ready => cmd_o_ready,
      p_rsp_out_val.data => rsp_o_data,
      p_rsp_out_val.valid => rsp_o_valid,
      p_rsp_out_val.last => rsp_o_last,
      p_rsp_out_ack.ready => rsp_i_ready,
      
      p_cmd_out_val => s_i2c_cmd.req,
      p_cmd_out_ack => s_i2c_cmd.ack,
      p_rsp_in_val => s_i2c_rsp.req,
      p_rsp_in_ack => s_i2c_rsp.ack
      );

  master: nsl_i2c.transactor.transactor_framed_controller
    port map(
      clock_i  => clock_i,
      reset_n_i => s_resetn_clk,
      
      cmd_i => s_i2c_cmd.req,
      cmd_o => s_i2c_cmd.ack,
      rsp_o => s_i2c_rsp.req,
      rsp_i => s_i2c_rsp.ack,
      
      i2c_i => s_i2c,
      i2c_o => s_i2c_master
      );

  i2c_mem: nsl_i2c.clockfree.clockfree_memory
    generic map(
      address => "0100110",
      addr_width => 16
      )
    port map(
      i2c_i => s_i2c,
      i2c_o => s_i2c_slave
      );

  resolver: nsl_i2c.i2c.i2c_resolver
    generic map(
      port_count => 2
      )
    port map(
      bus_i(0) => s_i2c_slave,
      bus_i(1) => s_i2c_master,
      bus_o => s_i2c
      );

end;
