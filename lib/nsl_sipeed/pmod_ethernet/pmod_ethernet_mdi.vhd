library ieee;
use ieee.std_logic_1164.all;

library nsl_digilent, nsl_io;

entity pmod_ethernet_mdi is
  generic(
    rx_diff_term_c : boolean := true
    );
  port(
    pmod_io : inout nsl_digilent.pmod.pmod_double_t;

    tx_p_i : in std_ulogic;
    tx_n_i : in std_ulogic;
    tx_en_i : in std_ulogic;

    rx_o : out std_ulogic
    );
end entity;

architecture beh of pmod_ethernet_mdi is

  signal rx_pair_s : nsl_io.diff.diff_pair;

begin

  -- Receive pair, sliced by a differential input buffer used as a
  -- comparator.  These two pads are never driven.
  rx_pair_s.p <= pmod_io(3);
  rx_pair_s.n <= pmod_io(7);

  rx_pad: nsl_io.pad.pad_diff_input
    generic map(
      diff_term => rx_diff_term_c,
      is_clock => false
      )
    port map(
      p_diff => rx_pair_s,
      p_se => rx_o
      );

  -- Transmit pair, released while idle: windings share their
  -- Phy-side center tap, so a driven idle level would clamp the bias
  -- of the whole magnetics, receive pair included.
  pmod_io(4) <= tx_p_i when tx_en_i = '1' else 'Z';
  pmod_io(8) <= tx_n_i when tx_en_i = '1' else 'Z';

  -- Unused pairs are left to the bias network of the constraints.
  pmod_io(1) <= 'Z';
  pmod_io(2) <= 'Z';
  pmod_io(5) <= 'Z';
  pmod_io(6) <= 'Z';

end architecture;
