library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_altera, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_altera.hps.all;
use nsl_data.endian.all;

entity hps_slave_bridge is
  generic(
    config_c : nsl_amba.axi4_mm.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in nsl_amba.axi4_mm.master_t;
    axi_o : out nsl_amba.axi4_mm.slave_t;

    ps_o : out hps_slave_fwd_t;
    ps_i : in hps_slave_bwd_t
    );
end entity;

architecture beh of hps_slave_bridge is

  constant dw_c : natural := 8 * 2 ** config_c.data_bus_width_l2;
  constant a_w_c : natural := address_vector_length(config_c);
  constant w_w_c : natural := write_data_vector_length(config_c);
  constant b_w_c : natural := write_response_vector_length(config_c);
  constant r_w_c : natural := read_data_vector_length(config_c);

  function lsbs(v : std_ulogic_vector; w : natural) return std_ulogic_vector
  is
  begin
    return std_ulogic_vector(resize(unsigned(v), w));
  end function;

  signal aw_in_s, aw_out_s, ar_in_s, ar_out_s : std_ulogic_vector(a_w_c-1 downto 0);
  signal w_in_s, w_out_s : std_ulogic_vector(w_w_c downto 0);
  signal b_in_s, b_out_s : std_ulogic_vector(b_w_c-1 downto 0);
  signal b_valid_s : std_ulogic;
  signal r_in_s, r_out_s : std_ulogic_vector(r_w_c downto 0);
  signal r_valid_s : std_ulogic;

begin

  aw_in_s <= vector_pack(config_c, axi_i.aw);

  aw: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => a_w_c,
      to_periphery_c => true,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => axi_i.aw.valid,
      in_data_i => aw_in_s,
      in_ready_o => axi_o.aw.ready,
      out_valid_o => ps_o.awvalid,
      out_data_o => aw_out_s,
      out_ready_i => ps_i.awready
      );

  aw_out: process(aw_out_s)
    variable a : address_t;
  begin
    a := address_vector_unpack(config_c, aw_out_s);
    ps_o.awid <= lsbs(id(config_c, a), ps_o.awid'length);
    ps_o.awaddr <= std_ulogic_vector(resize(address(config_c, a), ps_o.awaddr'length));
    ps_o.awlen <= std_ulogic_vector(length_m1(config_c, a, ps_o.awlen'length));
    ps_o.awsize <= std_ulogic_vector(size_l2(config_c, a));
    ps_o.awburst <= to_logic(config_c, burst(config_c, a));
    ps_o.awlock <= to_logic(config_c, lock(config_c, a))(0);
    ps_o.awcache <= cache(config_c, a);
    ps_o.awprot <= prot(config_c, a);
    ps_o.awqos <= qos(config_c, a);
    ps_o.awregion <= region(config_c, a);
    ps_o.awuser <= lsbs(user(config_c, a), ps_o.awuser'length);
  end process;

  ar_in_s <= vector_pack(config_c, axi_i.ar);

  ar: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => a_w_c,
      to_periphery_c => true,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => axi_i.ar.valid,
      in_data_i => ar_in_s,
      in_ready_o => axi_o.ar.ready,
      out_valid_o => ps_o.arvalid,
      out_data_o => ar_out_s,
      out_ready_i => ps_i.arready
      );

  ar_out: process(ar_out_s)
    variable a : address_t;
  begin
    a := address_vector_unpack(config_c, ar_out_s);
    ps_o.arid <= lsbs(id(config_c, a), ps_o.arid'length);
    ps_o.araddr <= std_ulogic_vector(resize(address(config_c, a), ps_o.araddr'length));
    ps_o.arlen <= std_ulogic_vector(length_m1(config_c, a, ps_o.arlen'length));
    ps_o.arsize <= std_ulogic_vector(size_l2(config_c, a));
    ps_o.arburst <= to_logic(config_c, burst(config_c, a));
    ps_o.arlock <= to_logic(config_c, lock(config_c, a))(0);
    ps_o.arcache <= cache(config_c, a);
    ps_o.arprot <= prot(config_c, a);
    ps_o.arqos <= qos(config_c, a);
    ps_o.arregion <= region(config_c, a);
    ps_o.aruser <= lsbs(user(config_c, a), ps_o.aruser'length);
  end process;

  w_in_s <= '1' & vector_pack(config_c, axi_i.w) when is_last(config_c, axi_i.w)
            else '0' & vector_pack(config_c, axi_i.w);

  w: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => w_w_c + 1,
      to_periphery_c => true,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => axi_i.w.valid,
      in_data_i => w_in_s,
      in_ready_o => axi_o.w.ready,
      out_valid_o => ps_o.wvalid,
      out_data_o => w_out_s,
      out_ready_i => ps_i.wready
      );

  w_out: process(w_out_s)
    variable w : write_data_t;
  begin
    w := write_data_vector_unpack(config_c, w_out_s(w_w_c-1 downto 0));
    ps_o.wdata <= (others => '0');
    ps_o.wdata(dw_c-1 downto 0) <= std_ulogic_vector(value(config_c, w, ENDIAN_LITTLE));
    ps_o.wstrb <= (others => '0');
    ps_o.wstrb(dw_c/8-1 downto 0) <= bitswap(strb(config_c, w));
    ps_o.wuser <= lsbs(user(config_c, w), ps_o.wuser'length);
    ps_o.wlast <= w_out_s(w_w_c);
  end process;

  b_in_s <= vector_pack(config_c,
                        write_response(config_c,
                                       id => lsbs(ps_i.bid, config_c.id_width),
                                       resp => to_resp(config_c, ps_i.bresp),
                                       user => lsbs(ps_i.buser, config_c.user_width)));

  b: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => b_w_c,
      to_periphery_c => false,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => ps_i.bvalid,
      in_data_i => b_in_s,
      in_ready_o => ps_o.bready,
      out_valid_o => b_valid_s,
      out_data_o => b_out_s,
      out_ready_i => axi_i.b.ready
      );

  axi_o.b <= write_response_vector_unpack(config_c, b_out_s, valid => b_valid_s = '1');

  r_in_s <= ps_i.rlast
            & vector_pack(config_c,
                          read_data(config_c,
                                    id => lsbs(ps_i.rid, config_c.id_width),
                                    value => unsigned(ps_i.rdata(dw_c-1 downto 0)),
                                    endian => ENDIAN_LITTLE,
                                    resp => to_resp(config_c, ps_i.rresp),
                                    user => lsbs(ps_i.ruser, config_c.user_width),
                                    last => ps_i.rlast = '1'));

  r: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => r_w_c + 1,
      to_periphery_c => false,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => ps_i.rvalid,
      in_data_i => r_in_s,
      in_ready_o => ps_o.rready,
      out_valid_o => r_valid_s,
      out_data_o => r_out_s,
      out_ready_i => axi_i.r.ready
      );

  axi_o.r <= read_data_vector_unpack(config_c, r_out_s(r_w_c-1 downto 0),
                                     valid => r_valid_s = '1',
                                     last => r_out_s(r_w_c) = '1');

end architecture;
