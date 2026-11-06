library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_altera, nsl_data;
use nsl_amba.axi4_mm.all;
use nsl_altera.hps.all;
use nsl_data.endian.all;

entity hps_master_bridge is
  generic(
    config_c : nsl_amba.axi4_mm.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    ps_i : in hps_master_fwd_t;
    ps_o : out hps_master_bwd_t;

    axi_o : out nsl_amba.axi4_mm.master_t;
    axi_i : in nsl_amba.axi4_mm.slave_t
    );
end entity;

architecture beh of hps_master_bridge is

  constant dw_c : natural := 8 * 2 ** config_c.data_bus_width_l2;
  constant a_w_c : natural := address_vector_length(config_c);
  constant w_w_c : natural := write_data_vector_length(config_c);
  constant b_w_c : natural := write_response_vector_length(config_c);
  constant r_w_c : natural := read_data_vector_length(config_c);

  function to_address(id, addr, len, size, burst : std_ulogic_vector;
                      lock : std_ulogic;
                      cache, prot : std_ulogic_vector;
                      valid : std_ulogic) return address_t
  is
  begin
    return address(config_c,
                   id => std_ulogic_vector(resize(unsigned(id), config_c.id_width)),
                   addr => resize(unsigned(addr), config_c.address_width),
                   len_m1 => resize(unsigned(len), config_c.len_width),
                   size_l2 => unsigned(size),
                   burst => to_burst(config_c, burst),
                   lock => to_lock(config_c, lock_t'(0 => lock)),
                   cache => cache,
                   prot => prot,
                   valid => valid = '1');
  end function;

  signal aw_in_s, aw_out_s, ar_in_s, ar_out_s : std_ulogic_vector(a_w_c-1 downto 0);
  signal aw_valid_s, ar_valid_s : std_ulogic;
  signal w_in_s, w_out_s : std_ulogic_vector(w_w_c downto 0);
  signal w_valid_s : std_ulogic;
  signal b_in_s, b_out_s : std_ulogic_vector(b_w_c-1 downto 0);
  signal r_in_s, r_out_s : std_ulogic_vector(r_w_c downto 0);

begin

  aw_in_s <= vector_pack(config_c, to_address(ps_i.awid, ps_i.awaddr, ps_i.awlen,
                                              ps_i.awsize, ps_i.awburst, ps_i.awlock,
                                              ps_i.awcache, ps_i.awprot, '1'));

  aw: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => a_w_c,
      to_periphery_c => false,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => ps_i.awvalid,
      in_data_i => aw_in_s,
      in_ready_o => ps_o.awready,
      out_valid_o => aw_valid_s,
      out_data_o => aw_out_s,
      out_ready_i => axi_i.aw.ready
      );

  axi_o.aw <= address_vector_unpack(config_c, aw_out_s, valid => aw_valid_s = '1');

  ar_in_s <= vector_pack(config_c, to_address(ps_i.arid, ps_i.araddr, ps_i.arlen,
                                              ps_i.arsize, ps_i.arburst, ps_i.arlock,
                                              ps_i.arcache, ps_i.arprot, '1'));

  ar: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => a_w_c,
      to_periphery_c => false,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => ps_i.arvalid,
      in_data_i => ar_in_s,
      in_ready_o => ps_o.arready,
      out_valid_o => ar_valid_s,
      out_data_o => ar_out_s,
      out_ready_i => axi_i.ar.ready
      );

  axi_o.ar <= address_vector_unpack(config_c, ar_out_s, valid => ar_valid_s = '1');

  w_in_s <= ps_i.wlast
            & vector_pack(config_c,
                          write_data(config_c,
                                     value => unsigned(ps_i.wdata(dw_c-1 downto 0)),
                                     strb => ps_i.wstrb(dw_c/8-1 downto 0),
                                     endian => ENDIAN_LITTLE,
                                     last => ps_i.wlast = '1'));

  w: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => w_w_c + 1,
      to_periphery_c => false,
      fifo_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => ps_i.wvalid,
      in_data_i => w_in_s,
      in_ready_o => ps_o.wready,
      out_valid_o => w_valid_s,
      out_data_o => w_out_s,
      out_ready_i => axi_i.w.ready
      );

  axi_o.w <= write_data_vector_unpack(config_c, w_out_s(w_w_c-1 downto 0),
                                      valid => w_valid_s = '1',
                                      last => w_out_s(w_w_c) = '1');

  b_in_s <= vector_pack(config_c, axi_i.b);

  b: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => b_w_c,
      to_periphery_c => true,
      fifo_c => false
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => axi_i.b.valid,
      in_data_i => b_in_s,
      in_ready_o => axi_o.b.ready,
      out_valid_o => ps_o.bvalid,
      out_data_o => b_out_s,
      out_ready_i => ps_i.bready
      );

  b_out: process(b_out_s)
    variable b : write_response_t;
  begin
    b := write_response_vector_unpack(config_c, b_out_s);
    -- The slave only answers with IDs it got, truncation is lossless.
    ps_o.bid <= std_ulogic_vector(resize(unsigned(id(config_c, b)), ps_o.bid'length));
    ps_o.bresp <= to_logic(config_c, resp(config_c, b));
  end process;

  r_in_s <= '1' & vector_pack(config_c, axi_i.r) when is_last(config_c, axi_i.r)
            else '0' & vector_pack(config_c, axi_i.r);

  r: nsl_altera.hps.hps_bridge_channel
    generic map(
      width_c => r_w_c + 1,
      to_periphery_c => true,
      fifo_c => false
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_valid_i => axi_i.r.valid,
      in_data_i => r_in_s,
      in_ready_o => axi_o.r.ready,
      out_valid_o => ps_o.rvalid,
      out_data_o => r_out_s,
      out_ready_i => ps_i.rready
      );

  r_out: process(r_out_s)
    variable r : read_data_t;
  begin
    r := read_data_vector_unpack(config_c, r_out_s(r_w_c-1 downto 0));
    ps_o.rid <= std_ulogic_vector(resize(unsigned(id(config_c, r)), ps_o.rid'length));
    ps_o.rdata <= (others => '0');
    ps_o.rdata(dw_c-1 downto 0) <= std_ulogic_vector(value(config_c, r, ENDIAN_LITTLE));
    ps_o.rresp <= to_logic(config_c, resp(config_c, r));
    ps_o.rlast <= r_out_s(r_w_c);
  end process;

end architecture;
