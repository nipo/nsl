library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_simulation, nsl_transceiver;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

-- Drives one lane_gearbox configuration with a counting byte stream,
-- loops the transceiver side back on itself, and checks the stream
-- comes back in order.
--
-- The two directions are each other's inverse, so a loopback is the
-- property worth asserting: it holds whatever the width ratio and
-- however much latency the conversion costs, and it fails as soon as
-- the two disagree on which end of a word the first byte sits at. The
-- sidebands are derived from the byte they belong to, so a sideband
-- gearbox running a cycle away from the data one fails too.
entity gearbox_bench is
  generic(
    data_byte_count_c : natural;
    interface_width_c : natural;
    word_count_c : natural := 64
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;
    done_o : out std_ulogic
    );
end entity;

architecture beh of gearbox_bench is

  constant interface_byte_count_c : natural := interface_width_c / 8;

  signal tx_data_s : std_ulogic_vector(data_byte_count_c * 8 - 1 downto 0);
  signal tx_charisk_s, tx_disp_frc_s, tx_disp_val_s
    : std_ulogic_vector(data_byte_count_c - 1 downto 0);
  signal rx_data_s : std_ulogic_vector(data_byte_count_c * 8 - 1 downto 0);
  signal rx_charisk_s, rx_disperr_s, rx_codeerr_s
    : std_ulogic_vector(data_byte_count_c - 1 downto 0);

  signal gt_data_s : std_ulogic_vector(interface_width_c - 1 downto 0);
  signal gt_charisk_s, gt_disp_frc_s, gt_disp_val_s
    : std_ulogic_vector(interface_byte_count_c - 1 downto 0);

begin

  dut: nsl_transceiver.transceiver_utils.lane_gearbox
    generic map(
      data_byte_count_c => data_byte_count_c,
      interface_width_c => interface_width_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      tx_data_i => tx_data_s,
      tx_charisk_i => tx_charisk_s,
      tx_disp_frc_i => tx_disp_frc_s,
      tx_disp_val_i => tx_disp_val_s,

      rx_data_o => rx_data_s,
      rx_charisk_o => rx_charisk_s,
      rx_disperr_o => rx_disperr_s,
      rx_codeerr_o => rx_codeerr_s,

      gt_tx_data_o => gt_data_s,
      gt_tx_charisk_o => gt_charisk_s,
      gt_tx_disp_frc_o => gt_disp_frc_s,
      gt_tx_disp_val_o => gt_disp_val_s,

      gt_rx_data_i => gt_data_s,
      gt_rx_charisk_i => gt_charisk_s,
      gt_rx_disperr_i => gt_disp_frc_s,
      gt_rx_codeerr_i => gt_disp_val_s
      );

  -- A byte that counts, with its three sidebands taken from its own
  -- low bits so each one can be checked against the byte it arrived
  -- with.
  feed: process(clock_i, reset_n_i)
    variable next_v : natural range 0 to 255;
    variable byte_v : std_ulogic_vector(7 downto 0);
  begin
    if reset_n_i = '0' then
      next_v := 0;
    end if;

    if rising_edge(clock_i) then
      for i in 0 to data_byte_count_c - 1 loop
        byte_v := std_ulogic_vector(to_unsigned((next_v + i) mod 256, 8));
        tx_data_s((i + 1) * 8 - 1 downto i * 8) <= byte_v;
        tx_charisk_s(i) <= byte_v(0);
        tx_disp_frc_s(i) <= byte_v(1);
        tx_disp_val_s(i) <= byte_v(2);
      end loop;
      next_v := (next_v + data_byte_count_c) mod 256;
    end if;
  end process;

  check: process
    constant ctxt : log_context := "lane gearbox "
      & integer'image(data_byte_count_c) & " bytes on "
      & integer'image(interface_width_c) & " bits";
    variable expected_v, got_v : natural;
  begin
    done_o <= '0';

    wait until reset_n_i = '1';

    -- Enough for the deepest conversion to have filled.
    for i in 0 to 15 loop
      wait until rising_edge(clock_i);
    end loop;

    expected_v := to_integer(unsigned(rx_data_s(7 downto 0)));

    for w in 0 to word_count_c - 1 loop
      for i in 0 to data_byte_count_c - 1 loop
        got_v := to_integer(unsigned(rx_data_s((i + 1) * 8 - 1 downto i * 8)));
        assert_equal(ctxt, "byte arrives in order", got_v, expected_v, FAILURE);
        assert_equal(ctxt, "the k flag stays with its byte",
                     rx_charisk_s(i), rx_data_s(i * 8), FAILURE);
        assert_equal(ctxt, "the forced disparity stays with its byte",
                     rx_disperr_s(i), rx_data_s(i * 8 + 1), FAILURE);
        assert_equal(ctxt, "the disparity value stays with its byte",
                     rx_codeerr_s(i), rx_data_s(i * 8 + 2), FAILURE);
        expected_v := (expected_v + 1) mod 256;
      end loop;

      wait until rising_edge(clock_i);
    end loop;

    log_info(ctxt, "looped " & integer'image(word_count_c)
             & " words back in order");

    done_o <= '1';
    wait;
  end process;

end architecture;
