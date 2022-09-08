library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_bnoc, nsl_clocking;
use work.mii.all;

entity mii_driver is
  generic(
    implementation_c: string := "resync";
    ipg_c : natural := 96 --bits
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    rx_sfd_o: out std_ulogic;
    tx_sfd_o: out std_ulogic;

    mii_o : out mii_m2p;
    mii_i : in  mii_p2m;

    rx_o : out nsl_bnoc.committed.committed_req;
    rx_i : in nsl_bnoc.committed.committed_ack;

    tx_i : in nsl_bnoc.committed.committed_req;
    tx_o : out nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of mii_driver is

begin

  is_resync: if implementation_c = "resync"
  generate
    impl: work.mii.mii_driver_resync
      generic map(
        ipg_c => ipg_c
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,
        rx_sfd_o => rx_sfd_o,
        tx_sfd_o => tx_sfd_o,
        mii_o => mii_o,
        mii_i => mii_i,
        rx_o => rx_o,
        rx_i => rx_i,
        tx_i => tx_i,
        tx_o => tx_o
        );
  end generate;
  
  is_oversampled: if implementation_c = "oversampled"
  generate
    impl: work.mii.mii_driver_oversampled
      generic map(
        ipg_c => ipg_c
        )
      port map(
        reset_n_i => reset_n_i,
        clock_i => clock_i,
        rx_sfd_o => rx_sfd_o,
        tx_sfd_o => tx_sfd_o,
        mii_o => mii_o,
        mii_i => mii_i,
        rx_o => rx_o,
        rx_i => rx_i,
        tx_i => tx_i,
        tx_o => tx_o
        );
  end generate;

end architecture;
