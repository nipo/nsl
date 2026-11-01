library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_transceiver, nsl_data, nsl_amba, nsl_clocking;
use nsl_data.bytestream.all;
use nsl_transceiver.lane.all;
use nsl_transceiver.prbs.all;

entity prbs_adapter is
  generic(
    config_c : nsl_amba.apb.config_t;
    lane_count_c : natural
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    apb_i : in nsl_amba.apb.master_t;
    apb_o : out nsl_amba.apb.slave_t;

    lane_clock_i : in std_ulogic_vector(0 to lane_count_c-1);

    tx_m_o : out tx_master_vector(0 to lane_count_c-1);
    tx_s_i : in tx_slave_vector(0 to lane_count_c-1);
    rx_m_i : in rx_master_vector(0 to lane_count_c-1);
    rx_s_o : out rx_slave_vector(0 to lane_count_c-1)
    );
end entity;

architecture beh of prbs_adapter is

  constant count_width_c : natural := 32;
  constant reg_per_lane_c : natural := 4;
  constant reg_count_l2_c : natural := 10;

  constant control_reg_c : natural := 0;
  constant status_reg_c : natural := 1;
  constant errors_reg_c : natural := 2;
  constant words_reg_c : natural := 3;

  constant tx_select_lsb_c : natural := 0;
  constant rx_select_lsb_c : natural := 8;
  constant force_error_bit_c : natural := 16;
  constant restart_bit_c : natural := 17;

  -- What crosses into a lane's own clock domain: the two selections,
  -- and one toggle for each of the two requests. A request arrives as
  -- a toggle so that one write makes one pulse however the two clocks
  -- are related. All of it moves only on a register write, so
  -- insisting it sits still for a couple of cycles is what keeps a
  -- selection from being taken half changed.
  constant control_width_c : natural := 2 * mode_width_c + 2;

  subtype word_t is unsigned(count_width_c-1 downto 0);
  type word_vector is array (natural range <>) of word_t;

  type regs_t is
  record
    tx_select : word_vector(0 to lane_count_c-1);
    rx_select : word_vector(0 to lane_count_c-1);
    force_toggle : std_ulogic_vector(0 to lane_count_c-1);
    restart_toggle : std_ulogic_vector(0 to lane_count_c-1);
  end record;

  signal r, rin : regs_t;

  signal reg_no_s : integer range 0 to 2**reg_count_l2_c-1;
  signal w_value_s, r_value_s : word_t;
  signal w_strobe_s, r_strobe_s : std_ulogic;
  signal bad_address_s : std_ulogic;

  signal locked_s : std_ulogic_vector(0 to lane_count_c-1);
  signal error_count_s, word_count_s : word_vector(0 to lane_count_c-1);

begin

  assert config_c.data_bus_width_l2 = 2
    report "nsl_transceiver.prbs.prbs_adapter: the register map is four"
    & " 32 bit words per lane, so the bus has to be 32 bits wide"
    severity failure;

  csr: nsl_amba.apb.apb_regmap
    generic map(
      config_c => config_c,
      reg_count_l2_c => reg_count_l2_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      apb_i => apb_i,
      apb_o => apb_o,

      reg_no_o => reg_no_s,

      w_value_o => w_value_s,
      w_strobe_o => w_strobe_s,

      r_value_i => r_value_s,
      r_strobe_o => r_strobe_s,
      r_error_i => bad_address_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.tx_select <= (others => (others => '0'));
      r.rx_select <= (others => (others => '0'));
      r.force_toggle <= (others => '0');
      r.restart_toggle <= (others => '0');
    end if;
  end process;

  transition: process(r, reg_no_s, w_value_s, w_strobe_s) is
    variable lane_v : natural;
    variable reg_v : natural;
  begin
    rin <= r;

    lane_v := reg_no_s / reg_per_lane_c;
    reg_v := reg_no_s mod reg_per_lane_c;

    if w_strobe_s = '1' and lane_v < lane_count_c
      and reg_v = control_reg_c then
      rin.tx_select(lane_v) <= resize(
        w_value_s(tx_select_lsb_c + mode_width_c - 1 downto tx_select_lsb_c),
        count_width_c);
      rin.rx_select(lane_v) <= resize(
        w_value_s(rx_select_lsb_c + mode_width_c - 1 downto rx_select_lsb_c),
        count_width_c);

      -- The requests are events, so they are remembered only as the
      -- edge that carries them across.
      if w_value_s(force_error_bit_c) = '1' then
        rin.force_toggle(lane_v) <= not r.force_toggle(lane_v);
      end if;

      if w_value_s(restart_bit_c) = '1' then
        rin.restart_toggle(lane_v) <= not r.restart_toggle(lane_v);
      end if;
    end if;
  end process;

  -- An access outside the map is answered rather than left to stall
  -- whoever asked for it.
  mealy: process(r, reg_no_s, locked_s, error_count_s, word_count_s) is
    variable lane_v : natural;
    variable reg_v : natural;
    variable value_v : word_t;
  begin
    lane_v := reg_no_s / reg_per_lane_c;
    reg_v := reg_no_s mod reg_per_lane_c;

    value_v := (others => '0');

    if lane_v < lane_count_c then
      bad_address_s <= '0';

      case reg_v is
        when control_reg_c =>
          value_v(tx_select_lsb_c + mode_width_c - 1 downto tx_select_lsb_c)
            := r.tx_select(lane_v)(mode_width_c-1 downto 0);
          value_v(rx_select_lsb_c + mode_width_c - 1 downto rx_select_lsb_c)
            := r.rx_select(lane_v)(mode_width_c-1 downto 0);
        when status_reg_c =>
          value_v(0) := locked_s(lane_v);
        when errors_reg_c =>
          value_v := error_count_s(lane_v);
        when others =>
          value_v := word_count_s(lane_v);
      end case;
    else
      bad_address_s <= '1';
    end if;

    r_value_s <= value_v;
  end process;

  lanes: for i in 0 to lane_count_c-1 generate

    signal control_s, crossed_s : std_ulogic_vector(control_width_c-1 downto 0);

    signal tx_mode_s, rx_mode_s : prbs_mode_t;
    signal force_error_s, restart_s : std_ulogic;

    signal lane_locked_s : std_ulogic_vector(0 downto 0);
    signal lane_error_count_s, lane_word_count_s : word_t;
    signal crossed_error_s, crossed_word_s : word_t;

  begin

    control_s <= r.restart_toggle(i) & r.force_toggle(i)
                 & std_ulogic_vector(r.rx_select(i)(mode_width_c-1 downto 0))
                 & std_ulogic_vector(r.tx_select(i)(mode_width_c-1 downto 0));

    control_cross: nsl_clocking.interdomain.interdomain_reg
      generic map(
        data_width_c => control_width_c,
        stable_count_c => 2
        )
      port map(
        clock_i => lane_clock_i(i),
        data_i => control_s,
        data_o => crossed_s
        );

    tx_mode_s <= to_prbs_mode(crossed_s(mode_width_c-1 downto 0));
    rx_mode_s <= to_prbs_mode(crossed_s(2*mode_width_c-1 downto mode_width_c));

    requests: block
      signal seen_s : std_ulogic_vector(1 downto 0);
    begin

      edge: process(lane_clock_i(i), reset_n_i) is
      begin
        if rising_edge(lane_clock_i(i)) then
          seen_s <= crossed_s(control_width_c-1 downto control_width_c-2);
        end if;

        if reset_n_i = '0' then
          seen_s <= "00";
        end if;
      end process;

      force_error_s <= crossed_s(control_width_c-2) xor seen_s(0);
      restart_s <= crossed_s(control_width_c-1) xor seen_s(1);

    end block;

    tx_m_o(i) <= (
      data => (others => (others => '-')),
      aux => (others => (others => '-')),
      valid => '0',
      pcs_reset_n => '1',
      control => (others => '0'),
      control_h => (others => '0'),
      c2i_clock => '0',
      prbs_select => tx_mode_s,
      prbs_force_error => force_error_s
      );

    rx_s_o(i) <= (
      ready => '1',
      pcs_reset_n => '1',
      align_trigger => '0',
      chbond_start => '0',
      control => (others => '0'),
      prbs_select => rx_mode_s,
      prbs_error_reset => restart_s
      );

    -- The counters live where the reports do. They run free and
    -- wrap: a reader differences two reads, which is also what makes
    -- them safe to carry out of this domain, since a gray coded
    -- crossing is only sound for a value moving one step at a time.
    counters: process(lane_clock_i(i), reset_n_i) is
    begin
      if rising_edge(lane_clock_i(i)) then
        if rx_m_i(i).prbs_locked = '1' then
          lane_word_count_s <= lane_word_count_s + 1;

          if rx_m_i(i).prbs_error = '1' then
            lane_error_count_s <= lane_error_count_s + 1;
          end if;
        end if;
      end if;

      if reset_n_i = '0' then
        lane_word_count_s <= (others => '0');
        lane_error_count_s <= (others => '0');
      end if;
    end process;

    error_cross: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => count_width_c
        )
      port map(
        clock_in_i => lane_clock_i(i),
        clock_out_i => clock_i,
        data_i => lane_error_count_s,
        data_o => crossed_error_s
        );

    word_cross: nsl_clocking.interdomain.interdomain_counter
      generic map(
        data_width_c => count_width_c
        )
      port map(
        clock_in_i => lane_clock_i(i),
        clock_out_i => clock_i,
        data_i => lane_word_count_s,
        data_o => crossed_word_s
        );

    error_count_s(i) <= crossed_error_s;
    word_count_s(i) <= crossed_word_s;

    lane_locked_s(0) <= rx_m_i(i).prbs_locked;

    locked_cross: nsl_clocking.interdomain.interdomain_reg
      generic map(
        data_width_c => 1
        )
      port map(
        clock_i => clock_i,
        data_i => lane_locked_s,
        data_o => locked_s(i to i)
        );

  end generate;

end architecture;
