library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.hdmi.all;
use work.audio.all;

entity hdmi_audio_receiver is
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    valid_i : in std_ulogic;
    error_i : in std_ulogic;
    packet_i : in work.hdmi.data_island_t;

    acr_valid_o : out std_ulogic;
    cts_o : out unsigned(19 downto 0);
    n_o : out unsigned(19 downto 0);

    valid_o : out std_ulogic;
    a_o, b_o : out channel_sample_t;
    block_start_o : out std_ulogic;
    flat_o : out std_ulogic
    );
end entity;

architecture beh of hdmi_audio_receiver is

  constant subpacket_count_c : natural := 4;

  subtype subpacket_word_t is unsigned(55 downto 0);
  type subpacket_word_vector is array(natural range <>) of subpacket_word_t;

  type regs_t is
  record
    -- Subpacket to hand out next, or subpacket_count_c for none left
    index: natural range 0 to subpacket_count_c;
    word: subpacket_word_vector(0 to subpacket_count_c-1);
    -- Header bits, one per subpacket
    present: std_ulogic_vector(0 to subpacket_count_c-1);
    flat: std_ulogic_vector(0 to subpacket_count_c-1);
    block_start: std_ulogic_vector(0 to subpacket_count_c-1);

    valid: std_ulogic;
    a, b: channel_sample_t;
    frame_block_start: std_ulogic;
    frame_flat: std_ulogic;

    acr_valid: std_ulogic;
    cts, n: unsigned(19 downto 0);
  end record;

  -- Both samples come first and the bits that go with them after, so
  -- a channel's sample and its V, U and C are not next to each other.
  function sample_of(word: subpacket_word_t;
                     channel: natural range 0 to 1) return channel_sample_t
  is
    variable ret: channel_sample_t;
  begin
    if channel = 0 then
      ret.data := word(23 downto 0);
      ret.v := word(48);
      ret.u := word(49);
      ret.c := word(50);
    else
      ret.data := word(47 downto 24);
      ret.v := word(52);
      ret.u := word(53);
      ret.c := word(54);
    end if;

    return ret;
  end function;

  -- CTS then N, each twenty bits in the top of a byte and two whole
  -- ones after it.  Every subpacket of the packet says the same thing,
  -- so the first is enough.
  function cts_of(packet: data_island_t) return unsigned
  is
  begin
    return unsigned(packet.pb(1)(3 downto 0)) & unsigned(packet.pb(2))
      & unsigned(packet.pb(3));
  end function;

  function n_of(packet: data_island_t) return unsigned
  is
  begin
    return unsigned(packet.pb(4)(3 downto 0)) & unsigned(packet.pb(5))
      & unsigned(packet.pb(6));
  end function;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.index <= subpacket_count_c;
      r.valid <= '0';
      r.acr_valid <= '0';
      r.cts <= (others => '0');
      r.n <= (others => '0');
    end if;
  end process;

  transition: process(r, valid_i, error_i, packet_i) is
  begin
    rin <= r;
    rin.valid <= '0';
    rin.acr_valid <= '0';

    if r.index /= subpacket_count_c then
      -- Emptying the packet in hand.  A subpacket the header did not
      -- claim holds nothing, so it is stepped over rather than handed
      -- out.
      if r.present(r.index) = '1' then
        rin.valid <= '1';
        rin.a <= sample_of(r.word(r.index), 0);
        rin.b <= sample_of(r.word(r.index), 1);
        rin.frame_block_start <= r.block_start(r.index);
        rin.frame_flat <= r.flat(r.index);
      end if;

      rin.index <= r.index + 1;

    elsif valid_i = '1' and error_i = '0' then
      if packet_i.packet_type = di_type_audio_sample then
        for i in 0 to subpacket_count_c-1
        loop
          rin.word(i) <= from_le(packet_i.pb(i*7 to i*7+6));
          rin.present(i) <= packet_i.hb(1)(i);
          rin.flat(i) <= packet_i.hb(2)(i);
          rin.block_start(i) <= packet_i.hb(2)(4+i);
        end loop;

        rin.index <= 0;

      elsif packet_i.packet_type = di_type_audio_clock_regen then
        rin.cts <= cts_of(packet_i);
        rin.n <= n_of(packet_i);
        rin.acr_valid <= '1';
      end if;
    end if;
  end process;

  moore: process(r) is
  begin
    valid_o <= r.valid;
    a_o <= r.a;
    b_o <= r.b;
    block_start_o <= r.frame_block_start;
    flat_o <= r.frame_flat;

    acr_valid_o <= r.acr_valid;
    cts_o <= r.cts;
    n_o <= r.n;
  end process;

end architecture;
