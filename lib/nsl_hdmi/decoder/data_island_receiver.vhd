library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_data, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_dvi.dvi.all;
use work.hdmi.all;

entity data_island_receiver is
  port(
    reset_n_i : in std_ulogic;
    pixel_clock_i : in std_ulogic;

    period_i : in nsl_dvi.dvi.period_t;
    di_hdr_i : in std_ulogic_vector(1 downto 0);
    di_data_i : in std_ulogic_vector(7 downto 0);

    valid_o : out std_ulogic;
    packet_o : out work.hdmi.data_island_t;
    error_o : out std_ulogic
    );
end entity;

architecture beh of data_island_receiver is

  -- Symbols a packet is spread over
  constant packet_symbol_count_c : natural := 32;
  -- Of those, the ones carrying data rather than parity.  The header
  -- takes one bit a symbol and a subpacket two, so they run out at
  -- different points.
  constant header_data_symbol_c : natural := 24;
  constant subpacket_data_symbol_c : natural := 28;

  -- Twenty four bits of header then eight of parity, and fifty six
  -- bits of subpacket then eight of parity.
  subtype header_t is std_ulogic_vector(0 to 31);
  subtype subpacket_t is std_ulogic_vector(0 to 63);
  type subpacket_vector_t is array(natural range <>) of subpacket_t;
  type bch_vector_t is array(natural range <>) of di_bch_t;

  type regs_t is
  record
    -- Where in its packet the symbol arriving now sits
    index: natural range 0 to packet_symbol_count_c-1;

    -- What has arrived so far, oldest bit first
    header: header_t;
    subpacket: subpacket_vector_t(0 to 3);

    -- The remainder over the data bits, which is what the parity
    -- following them should turn out to be
    header_bch: di_bch_t;
    subpacket_bch: bch_vector_t(0 to 3);

    valid: std_ulogic;
    error: std_ulogic;
    packet: data_island_t;
  end record;

  -- Bits arrive least significant first, on the header and on every
  -- subpacket alike, and a subpacket is seven bytes least significant
  -- byte first.
  function to_packet(header: header_t;
                     subpacket: subpacket_vector_t) return data_island_t
  is
    variable ret: data_island_t;
  begin
    ret.packet_type := bitswap(header(0 to 7));
    ret.hb(1) := bitswap(header(8 to 15));
    ret.hb(2) := bitswap(header(16 to 23));

    for i in 0 to 3
    loop
      ret.pb(i*7 to i*7+6) := to_le(unsigned(bitswap(subpacket(i)(0 to 55))));
    end loop;

    return ret;
  end function;

  -- What arrived against what it should have been.  One failure
  -- anywhere condemns the packet: there is no telling which part of
  -- it a reader will care about.
  function bch_failed(header: header_t;
                      subpacket: subpacket_vector_t;
                      header_bch: di_bch_t;
                      subpacket_bch: bch_vector_t) return std_ulogic
  is
  begin
    if header(24 to 31) /= header_bch then
      return '1';
    end if;

    for i in 0 to 3
    loop
      if subpacket(i)(56 to 63) /= subpacket_bch(i) then
        return '1';
      end if;
    end loop;

    return '0';
  end function;

  signal r, rin: regs_t;

begin

  regs: process(pixel_clock_i, reset_n_i) is
  begin
    if rising_edge(pixel_clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.index <= 0;
      r.valid <= '0';
      r.error <= '0';
    end if;
  end process;

  transition: process(r, period_i, di_hdr_i, di_data_i) is
    variable at: natural range 0 to packet_symbol_count_c-1;
    variable header_v: header_t;
    variable subpacket_v: subpacket_vector_t(0 to 3);
    variable header_bch_v: di_bch_t;
    variable subpacket_bch_v: bch_vector_t(0 to 3);
  begin
    rin <= r;
    rin.valid <= '0';

    -- An island's first symbol is its first packet's first symbol,
    -- whatever came before it.  Packets after that one follow on
    -- immediately, so the count simply wraps.
    if period_i /= nsl_dvi.dvi.PERIOD_DI_DATA or di_hdr_i(1) = '0' then
      at := 0;
    else
      at := r.index;
    end if;

    header_v := r.header(1 to 31) & di_hdr_i(0);

    for i in 0 to 3
    loop
      subpacket_v(i) := r.subpacket(i)(2 to 63)
                        & di_data_i(i) & di_data_i(4+i);
    end loop;

    if at = 0 then
      header_bch_v := di_bch(di_bch_init_c,
                             std_ulogic_vector'(0 => di_hdr_i(0)));
    elsif at < header_data_symbol_c then
      header_bch_v := di_bch(r.header_bch,
                             std_ulogic_vector'(0 => di_hdr_i(0)));
    else
      header_bch_v := r.header_bch;
    end if;

    for i in 0 to 3
    loop
      if at = 0 then
        subpacket_bch_v(i) := di_bch(
          di_bch_init_c,
          std_ulogic_vector'(0 => di_data_i(i), 1 => di_data_i(4+i)));
      elsif at < subpacket_data_symbol_c then
        subpacket_bch_v(i) := di_bch(
          r.subpacket_bch(i),
          std_ulogic_vector'(0 => di_data_i(i), 1 => di_data_i(4+i)));
      else
        subpacket_bch_v(i) := r.subpacket_bch(i);
      end if;
    end loop;

    if period_i = nsl_dvi.dvi.PERIOD_DI_DATA then
      rin.header <= header_v;
      rin.subpacket <= subpacket_v;
      rin.header_bch <= header_bch_v;
      rin.subpacket_bch <= subpacket_bch_v;

      if at = packet_symbol_count_c-1 then
        rin.index <= 0;
        rin.valid <= '1';
        rin.packet <= to_packet(header_v, subpacket_v);
        rin.error <= bch_failed(header_v, subpacket_v,
                                header_bch_v, subpacket_bch_v);
      else
        rin.index <= at + 1;
      end if;
    else
      rin.index <= 0;
    end if;
  end process;

  moore: process(r) is
  begin
    valid_o <= r.valid;
    packet_o <= r.packet;
    error_o <= r.error;
  end process;

end architecture;
