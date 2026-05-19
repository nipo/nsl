library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_avalon, nsl_logic, nsl_data;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;

-- Avalon-ST source -> AXI4-Stream master bridge. Purely combinational
-- (Avalon-ST sop has no AXI equivalent and is dropped). The empty
-- count is translated to a contiguous tkeep mask.
entity avalon_st_to_axi4_stream is
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
begin
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
    report "Avalon error has no AXI4-Stream sink"
    severity failure;
  assert avst_config_c.symbol_user_width = 0
    report "Avalon symbol_user has no AXI4-Stream sink"
    severity failure;
  assert not axi_config_c.has_strobe
    report "AXI has_strobe is unsupported"
    severity failure;
  assert axi_config_c.id_width = 0
    report "AXI id_width must be 0"
    severity failure;
end entity;

architecture beh of avalon_st_to_axi4_stream is

  constant spb_c     : positive := avst_config_c.symbols_per_beat;

  -- Convert an Avalon empty count to a contiguous AXI tkeep mask
  -- (ascending: keep(0) = byte 0, keep(width-1) = byte width-1).
  function empty_to_tkeep(empty: natural; width: natural) return std_ulogic_vector is
    variable keep_v : std_ulogic_vector(0 to width-1);
  begin
    for i in 0 to width-1 loop
      if i < width - empty then
        keep_v(i) := '1';
      else
        keep_v(i) := '0';
      end if;
    end loop;
    return keep_v;
  end function;

begin

  drv: process(in_i) is
    variable bytes_v : byte_string(0 to spb_c-1);
    variable keep_v  : std_ulogic_vector(0 to spb_c-1);
    variable id_dummy : std_ulogic_vector(1 to 0) := (others => '-');
    variable empty_v : natural;
    variable take_v  : natural;
  begin
    -- Pull bytes out of source.data (symbol 0 at low bits).
    for i in 0 to spb_c-1 loop
      bytes_v(i) := std_ulogic_vector(in_i.data(i*8 + 7 downto i*8));
    end loop;

    -- Compute tkeep from empty count: 1s for valid_symbol_count bytes,
    -- then trailing 0s.
    if axi_config_c.has_keep then
      take_v  := nsl_avalon.avalon_st.valid_symbol_count(avst_config_c, in_i);
      empty_v := spb_c - take_v;
      keep_v  := empty_to_tkeep(empty_v, spb_c);
    else
      keep_v := (others => '1');
    end if;

    out_o <= nsl_amba.axi4_stream.transfer(
      cfg    => axi_config_c,
      bytes  => bytes_v,
      keep   => keep_v,
      user   => nsl_avalon.avalon_st.packet_user(avst_config_c, in_i),
      dest   => nsl_avalon.avalon_st.channel    (avst_config_c, in_i),
      valid  => nsl_avalon.avalon_st.is_valid(avst_config_c, in_i),
      last   => nsl_avalon.avalon_st.is_eop  (avst_config_c, in_i, default => true));
  end process;

  in_o <= nsl_avalon.avalon_st.accept(avst_config_c,
                                      nsl_amba.axi4_stream.is_ready(axi_config_c, out_i));

end architecture;
