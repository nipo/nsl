library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, work;
use work.mac.all;

entity mac_receiver is
  generic(
    l1_has_fcs_c : boolean := true;
    l1_header_length_c : integer := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    l1_i : in nsl_bnoc.committed.committed_req;
    l1_o : out nsl_bnoc.committed.committed_ack;

    l2_o : out nsl_bnoc.committed.committed_req;
    l2_i : in nsl_bnoc.committed.committed_ack
    );
end entity;

architecture beh of mac_receiver is

begin

  has_fcs: if l1_has_fcs_c
  generate
    crc: nsl_bnoc.crc.crc_committed_checker
      generic map(
        header_length_c => l1_header_length_c,
        params_c => fcs_params_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        in_i => l1_i,
        in_o => l1_o,
        out_o => l2_o,
        out_i => l2_i
        );
  end generate;

  no_fcs: if not l1_has_fcs_c
  generate
    l2_o <= l1_i;
    l1_o <= l2_i;
  end generate;

end architecture;
