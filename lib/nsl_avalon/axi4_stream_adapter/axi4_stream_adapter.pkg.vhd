library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_avalon, nsl_amba;

-- Compatibility bridge between nsl_amba.axi4_stream and nsl_avalon.avalon_st.
--
-- Supported subset:
--   * Avalon-ST data_bits_per_symbol = 8 (byte-oriented stream).
--   * Avalon-ST ready_latency = ready_allowance = 0
--     (AXI4-Stream's native same-cycle handshake).
--   * Avalon-ST first_symbol_in_high_order_bits = false
--     (matches NSL's internal canonical and AXI's byte_string indexing).
--   * AXI4-Stream has_strobe = false (no Avalon equivalent).
--   * AXI4-Stream id_width = 0 (only tdest is mapped; to channel).
--   * Avalon-ST error and symbol_user widths = 0 (no AXI counterpart).
--
-- Field mapping:
--   tdata    <-> data
--   tvalid   <-> valid
--   tready   <-> ready
--   tlast    <-> endofpacket
--   (synth)  <-> startofpacket (synthesised on AXI->Avalon from "next beat after reset or after tlast")
--   tkeep    <-> empty  (assumes trailing-only zeros in tkeep; internal zeros are silently dropped)
--   tdest    <-> channel
--   tuser    <-> packet_user
package axi4_stream_adapter is

  -- Build the closest Avalon-ST config corresponding to a given
  -- AXI4-Stream config. Asserts compatibility at elaboration.
  function to_avalon_st(axi: nsl_amba.axi4_stream.config_t)
    return nsl_avalon.avalon_st.config_t;

  -- Build the closest AXI4-Stream config corresponding to a given
  -- Avalon-ST config. Asserts compatibility at elaboration.
  function to_axi4_stream(avst: nsl_avalon.avalon_st.config_t)
    return nsl_amba.axi4_stream.config_t;

  -- AXI4-Stream master -> Avalon-ST source bridge.
  component axi4_stream_to_avalon_st is
    generic(
      axi_config_c  : nsl_amba.axi4_stream.config_t;
      avst_config_c : nsl_avalon.avalon_st.config_t
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i  : in  nsl_amba.axi4_stream.master_t;
      in_o  : out nsl_amba.axi4_stream.slave_t;

      out_o : out nsl_avalon.avalon_st.source_t;
      out_i : in  nsl_avalon.avalon_st.sink_t
      );
  end component;

  -- Avalon-ST source -> AXI4-Stream master bridge.
  component avalon_st_to_axi4_stream is
    generic(
      avst_config_c : nsl_avalon.avalon_st.config_t;
      axi_config_c  : nsl_amba.axi4_stream.config_t
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      in_i  : in  nsl_avalon.avalon_st.source_t;
      in_o  : out nsl_avalon.avalon_st.sink_t;

      out_o : out nsl_amba.axi4_stream.master_t;
      out_i : in  nsl_amba.axi4_stream.slave_t
      );
  end component;

end package;

package body axi4_stream_adapter is

  function to_avalon_st(axi: nsl_amba.axi4_stream.config_t)
    return nsl_avalon.avalon_st.config_t is
    variable spb : positive;
  begin
    assert not axi.has_strobe
      report "to_avalon_st: AXI has_strobe is unsupported"
      severity failure;
    assert axi.id_width = 0
      report "to_avalon_st: AXI id_width must be 0 (only tdest is mapped)"
      severity failure;
    assert axi.data_width >= 1
      report "to_avalon_st: AXI data_width must be >= 1"
      severity failure;

    spb := axi.data_width;
    return nsl_avalon.avalon_st.config(
      symbols_per_beat                => spb,
      data_bits_per_symbol            => 8,
      channel                         => axi.dest_width,
      error                           => 0,
      packet_user                     => axi.user_width,
      symbol_user                     => 0,
      has_ready                       => axi.has_ready,
      has_packet                      => axi.has_last,
      has_empty                       => axi.has_keep and spb > 1,
      ready_latency                   => 0,
      ready_allowance                 => 0,
      first_symbol_in_high_order_bits => false);
  end function;

  function to_axi4_stream(avst: nsl_avalon.avalon_st.config_t)
    return nsl_amba.axi4_stream.config_t is
  begin
    assert avst.data_bits_per_symbol = 8
      report "to_axi4_stream: data_bits_per_symbol must be 8"
      severity failure;
    assert avst.ready_latency = 0 and avst.ready_allowance = 0
      report "to_axi4_stream: ready_latency / ready_allowance must be 0"
      severity failure;
    assert avst.error_width = 0
      report "to_axi4_stream: Avalon error has no AXI4-Stream equivalent"
      severity failure;
    assert avst.symbol_user_width = 0
      report "to_axi4_stream: Avalon symbol_user has no AXI4-Stream equivalent"
      severity failure;
    assert not avst.first_symbol_in_high_order_bits
      report "to_axi4_stream: first_symbol_in_high_order_bits must be false"
      severity failure;

    return nsl_amba.axi4_stream.config(
      bytes  => avst.symbols_per_beat,
      user   => avst.packet_user_width,
      id     => 0,
      dest   => avst.channel_width,
      keep   => avst.has_empty,
      strobe => false,
      ready  => avst.has_ready,
      last   => avst.has_packet);
  end function;

end package body;
