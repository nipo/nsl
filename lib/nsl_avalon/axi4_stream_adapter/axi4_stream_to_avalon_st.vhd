library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_avalon, nsl_logic, nsl_data;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;

-- AXI4-Stream master -> Avalon-ST source bridge. Combinational
-- data/control conversion plus a one-bit register that synthesises
-- startofpacket as "first beat after reset or after the previous tlast".
entity axi4_stream_to_avalon_st is
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
begin
  -- Compatibility checks (mirror axi4_stream_adapter.to_avalon_st).
  assert avst_config_c.data_bits_per_symbol = 8
    report "data_bits_per_symbol must be 8"
    severity failure;
  assert avst_config_c.ready_latency = 0 and avst_config_c.ready_allowance = 0
    report "Avalon-ST side must have ready_latency = 0"
    severity failure;
  assert not avst_config_c.first_symbol_in_high_order_bits
    report "Avalon-ST first_symbol_in_high_order_bits must be false"
    severity failure;
  assert avst_config_c.symbols_per_beat = axi_config_c.data_width
    report "symbols_per_beat must equal AXI data_width"
    severity failure;
  assert avst_config_c.channel_width = axi_config_c.dest_width
    report "channel_width must equal AXI dest_width"
    severity failure;
  assert avst_config_c.packet_user_width = axi_config_c.user_width
    report "packet_user_width must equal AXI user_width"
    severity failure;
  assert avst_config_c.has_packet = axi_config_c.has_last
    report "has_packet must equal AXI has_last"
    severity failure;
  assert avst_config_c.has_ready = axi_config_c.has_ready
    report "has_ready must match"
    severity failure;
  assert avst_config_c.error_width = 0
    report "Avalon error has no AXI4-Stream source"
    severity failure;
  assert avst_config_c.symbol_user_width = 0
    report "Avalon symbol_user has no AXI4-Stream source"
    severity failure;
  assert not axi_config_c.has_strobe
    report "AXI has_strobe is unsupported"
    severity failure;
  assert axi_config_c.id_width = 0
    report "AXI id_width must be 0"
    severity failure;
end entity;

architecture beh of axi4_stream_to_avalon_st is

  constant spb_c     : positive := avst_config_c.symbols_per_beat;
  constant dbits_c   : positive := spb_c * 8;
  constant has_pkt_c : boolean  := avst_config_c.has_packet;
  constant has_emp_c : boolean  := avst_config_c.has_empty;

  signal sop_next_s : std_ulogic;

  -- Count trailing zeros in an ascending-indexed tkeep slice (byte 0 at
  -- the low index, byte N-1 at the high index). Internal-zero bytes are
  -- silently treated as data (the count stops at the first '1' from the
  -- top), matching the documented limitation of the adapter.
  function tkeep_to_empty(k: std_ulogic_vector) return natural is
    variable empty_v : natural := 0;
    variable done_v  : boolean := false;
  begin
    for i in k'length-1 downto 0 loop
      if not done_v then
        if k(k'low + i) = '0' then
          empty_v := empty_v + 1;
        else
          done_v := true;
        end if;
      end if;
    end loop;
    return empty_v;
  end function;

begin

  sop_reg: process(clock_i, reset_n_i) is
  begin
    if reset_n_i = '0' then
      sop_next_s <= '1';
    elsif rising_edge(clock_i) then
      if nsl_amba.axi4_stream.is_valid(axi_config_c, in_i)
          and nsl_avalon.avalon_st.is_ready(avst_config_c, out_i) then
        if nsl_amba.axi4_stream.is_last(axi_config_c, in_i, default => true) then
          sop_next_s <= '1';
        else
          sop_next_s <= '0';
        end if;
      end if;
    end if;
  end process;

  drv: process(in_i, sop_next_s) is
    variable beat   : nsl_avalon.avalon_st.source_t;
    variable bytes_v: byte_string(0 to spb_c-1);
    variable keep_v : std_ulogic_vector(0 to spb_c-1);
    variable empty_v: natural;
  begin
    beat := nsl_avalon.avalon_st.transfer_defaults(avst_config_c);

    bytes_v := nsl_amba.axi4_stream.bytes(axi_config_c, in_i);
    for i in 0 to spb_c-1 loop
      beat.data(i*8 + 7 downto i*8) := bytes_v(i);
    end loop;

    beat.valid := to_logic(nsl_amba.axi4_stream.is_valid(axi_config_c, in_i));

    if has_pkt_c then
      beat.startofpacket := sop_next_s;
      beat.endofpacket   := to_logic(nsl_amba.axi4_stream.is_last(axi_config_c, in_i, default => true));
    end if;

    if has_emp_c then
      keep_v  := nsl_amba.axi4_stream.keep(axi_config_c, in_i);
      empty_v := tkeep_to_empty(keep_v);
      beat.empty := to_unsigned(empty_v, beat.empty'length);
    end if;

    if avst_config_c.channel_width /= 0 then
      beat.channel(avst_config_c.channel_width-1 downto 0)
        := nsl_amba.axi4_stream.dest(axi_config_c, in_i);
    end if;

    if avst_config_c.packet_user_width /= 0 then
      beat.packet_user(avst_config_c.packet_user_width-1 downto 0)
        := nsl_amba.axi4_stream.user(axi_config_c, in_i);
    end if;

    out_o <= beat;
  end process;

  in_o <= nsl_amba.axi4_stream.accept(axi_config_c,
                                      nsl_avalon.avalon_st.is_ready(avst_config_c, out_i));

end architecture;
