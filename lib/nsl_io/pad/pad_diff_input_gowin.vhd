library ieee;
use ieee.std_logic_1164.all;

library nsl_io;
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

architecture gowin of pad_diff_input is

  signal unbuffered_s, inverted_s : std_ulogic;

  COMPONENT BUFG
    PORT(
      O:OUT std_logic;
      I:IN std_logic
      );
  END COMPONENT;

  COMPONENT TLVDS_IBUF
    PORT (
      O:OUT std_logic;
      I:IN std_logic;
      IB:IN std_logic
      );
  END COMPONENT;

  COMPONENT ELVDS_IBUF
    PORT (
      O:OUT std_logic;
      I:IN std_logic;
      IB:IN std_logic
      );
  END COMPONENT;

begin

  if_diff_term: if diff_term
  generate
    iobuf_inst: TLVDS_IBUF
      port map(
        i => p_diff.p,
        ib => p_diff.n,
        o => unbuffered_s
        );
  end generate;
  
  if_no_diff_term: if not diff_term
  generate
    iobuf_inst: ELVDS_IBUF
      port map(
        i => p_diff.p,
        ib => p_diff.n,
        o => unbuffered_s
        );
  end generate;
  
  inverted_s <= unbuffered_s when not invert else (not unbuffered_s);

  if_clk: if is_clock
  generate
    ck_buf: bufg
      port map(
        i => inverted_s,
        o => p_se
        );
  end generate;

  if_data: if not is_clock
  generate
    p_se <= inverted_s;
  generate
  
end architecture;
