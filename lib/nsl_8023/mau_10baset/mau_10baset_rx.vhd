library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_mii, nsl_line_coding, nsl_clocking, nsl_logic;
use nsl_logic.bool.all;

entity mau_10baset_rx is
  generic (
    clock_i_hz_c : natural
    );
  port (
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    rx_i : in std_ulogic;

    flit_o : out nsl_mii.flit.mii_flit_t;
    valid_o : out std_ulogic;

    carrier_o : out std_ulogic;
    link_pulse_o : out std_ulogic;
    frame_o : out std_ulogic;
    polarity_inverted_o : out std_ulogic
    );
end entity;

architecture beh of mau_10baset_rx is

  constant signal_hz_c : natural := 10000000;
  constant bit_cycles_c : natural := clock_i_hz_c / signal_hz_c;

  -- Receive squelch: line activity shorter than this is a link pulse
  -- or noise, not a frame.  Must be longer than a link pulse plus the
  -- settling time of the pair, and way shorter than a preamble.
  constant squelch_cycles_c : natural := 8 * bit_cycles_c;

  -- Last 8 bits of the preamble/SFD sequence, most recent bit first.
  -- SFD is 0xd5, serialized LSB first.
  constant sfd_c : std_ulogic_vector(7 downto 0) := "11010101";

  type state_t is (
    ST_RESET,
    -- Out of frame, hunting for SFD in the recovered bit stream.
    ST_HUNT,
    -- Regenerating preamble and SFD flits for the MAC.
    ST_PRE,
    ST_SFD,
    -- Frame payload.
    ST_DATA
    );

  type regs_t is
  record
    state : state_t;

    -- Most recently recovered bits, newest in MSB.
    sr : std_ulogic_vector(7 downto 0);
    -- Frame byte under assembly, first bit ends up in LSB.
    data_sr : std_ulogic_vector(7 downto 0);
    bit_index : natural range 0 to 7;
    byte_pending : std_ulogic;

    -- Polarity of the pair, resolved from SFD.
    invert : std_ulogic;
    polarity_inverted : std_ulogic;

    -- Duration of current line activity, saturating at squelch point.
    activity_ctr : natural range 0 to squelch_cycles_c;
    active : std_ulogic;

    flit : nsl_mii.flit.mii_flit_t;
    flit_valid : std_ulogic;
    link_pulse : std_ulogic;
    frame : std_ulogic;
  end record;

  signal r, rin : regs_t;

  signal synced_s : std_ulogic;
  signal bit_s, bit_valid_s, active_s : std_ulogic;

begin

  assert clock_i_hz_c mod (2 * signal_hz_c) = 0
    report "clock_i_hz_c must be a multiple of 20 MHz"
    severity failure;

  -- rx_i comes straight from an IO comparator, it is asynchronous to
  -- clock_i and may glitch.
  sampler: nsl_clocking.async.async_input
    generic map(
      sample_count_c => 2,
      debounce_count_c => 2,
      reset_value_c => '0'
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => rx_i,
      data_o => synced_s,
      rising_o => open,
      falling_o => open
      );

  decoder: nsl_line_coding.manchester.manchester_receiver_recovery
    generic map(
      clock_i_hz_c => clock_i_hz_c,
      signal_hz_c => signal_hz_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      data_i => synced_s,

      bit_o => bit_s,
      valid_o => bit_valid_s,

      active_o => active_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.flit_valid <= '0';
      r.link_pulse <= '0';
      r.frame <= '0';
      r.active <= '0';
      r.activity_ctr <= 0;
      r.polarity_inverted <= '0';
    end if;
  end process;

  transition: process(r, bit_s, bit_valid_s, active_s) is
    variable sr_v : std_ulogic_vector(7 downto 0);
  begin
    rin <= r;

    rin.flit_valid <= '0';
    rin.link_pulse <= '0';
    rin.frame <= '0';

    sr_v := bit_s & r.sr(7 downto 1);

    -- Line activity classification
    rin.active <= active_s;
    if active_s = '1' then
      if r.activity_ctr /= squelch_cycles_c then
        rin.activity_ctr <= r.activity_ctr + 1;
      end if;
    else
      rin.activity_ctr <= 0;
      if r.active = '1' and r.activity_ctr /= squelch_cycles_c then
        rin.link_pulse <= '1';
      end if;
    end if;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_HUNT;
        rin.sr <= (others => '0');
        rin.invert <= '0';
        rin.polarity_inverted <= '0';

      when ST_HUNT =>
        if bit_valid_s = '1' then
          rin.sr <= sr_v;

          if sr_v = sfd_c then
            rin.invert <= '0';
            rin.polarity_inverted <= '0';
            rin.state <= ST_PRE;
            rin.frame <= '1';
          elsif sr_v = not sfd_c then
            rin.invert <= '1';
            rin.polarity_inverted <= '1';
            rin.state <= ST_PRE;
            rin.frame <= '1';
          end if;
        end if;

      when ST_PRE =>
        rin.flit.data <= x"55";
        rin.flit.valid <= '1';
        rin.flit.error <= '0';
        rin.flit_valid <= '1';
        rin.state <= ST_SFD;

      when ST_SFD =>
        rin.flit.data <= x"d5";
        rin.flit.valid <= '1';
        rin.flit.error <= '0';
        rin.flit_valid <= '1';
        rin.state <= ST_DATA;
        rin.bit_index <= 0;
        rin.byte_pending <= '0';

      when ST_DATA =>
        if r.byte_pending = '1' then
          rin.byte_pending <= '0';
          rin.flit.data <= r.data_sr;
          rin.flit.valid <= '1';
          rin.flit.error <= '0';
          rin.flit_valid <= '1';
        elsif active_s = '0' then
          -- Carrier is gone, close the frame.  Any bit left in
          -- data_sr is TP_IDL or line settling, not data.
          rin.flit.data <= x"00";
          rin.flit.valid <= '0';
          rin.flit.error <= '0';
          rin.flit_valid <= '1';
          rin.state <= ST_HUNT;
          rin.sr <= (others => '0');
        end if;

        if bit_valid_s = '1' then
          rin.data_sr <= (bit_s xor r.invert) & r.data_sr(7 downto 1);
          if r.bit_index /= 7 then
            rin.bit_index <= r.bit_index + 1;
          else
            rin.bit_index <= 0;
            rin.byte_pending <= '1';
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    flit_o <= r.flit;
    valid_o <= r.flit_valid;
    link_pulse_o <= r.link_pulse;
    frame_o <= r.frame;
    polarity_inverted_o <= r.polarity_inverted;
  end process;

  mealy: process(r, active_s) is
  begin
    carrier_o <= to_logic(active_s = '1' and r.activity_ctr = squelch_cycles_c);
  end process;

end architecture;
