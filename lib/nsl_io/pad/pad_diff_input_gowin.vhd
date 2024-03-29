library ieee;
use ieee.std_logic_1164.all;

library nsl_io, gowin;
use nsl_io.diff.all;

entity pad_diff_input is
  generic(
    diff_term : boolean := true;
    is_clock  : boolean := false;
    invert    : boolean := false
    );
  port(
    p_diff : in diff_pair;
    p_se   : out std_ulogic
    );
end entity;

architecture gw1n of pad_diff_input is

  signal unbuffered_s, inverted_s : std_ulogic;

begin

  if_diff_term: if diff_term
  generate
    iobuf_inst: gowin.components.tlvds_ibuf
      port map(
        i => p_diff.p,
        ib => p_diff.n,
        o => unbuffered_s
        );
  end generate;
  
  if_no_diff_term: if not diff_term
  generate
    iobuf_inst: gowin.components.elvds_ibuf
      port map(
        i => p_diff.p,
        ib => p_diff.n,
        o => unbuffered_s
        );
  end generate;
  
  inverted_s <= unbuffered_s when not invert else (not unbuffered_s);

  if_clk: if is_clock
  generate
    ck_buf: gowin.components.bufg
      port map(
        i => inverted_s,
        o => p_se
        );
  end generate;

  if_data: if not is_clock
  generate
    p_se <= inverted_s;
  end generate;

end architecture;
