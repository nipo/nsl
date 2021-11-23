library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;

entity committed_funnel is
  generic(
    source_count_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    enable_i : in std_ulogic := '1';
    selected_o  : out natural range 0 to source_count_c - 1;
    
    in_i   : in committed_req_array(0 to source_count_c - 1);
    in_o   : out committed_ack_array(0 to source_count_c - 1);

    out_o   : out committed_req;
    out_i   : in committed_ack
    );
end entity;

architecture beh of committed_funnel is

  signal in_s : framed_ack_array(0 to source_count_c - 1);
  
begin

  in_map: for i in in_s'range
  generate
    in_o(i) <= in_s(i);
  end generate;

  impl: nsl_bnoc.framed.framed_funnel
    generic map(
      source_count_c => source_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      enable_i => enable_i,
      selected_o => selected_o,
      
      in_i => framed_req_array(in_i),
      in_o => in_s,

      out_o => out_o,
      out_i => out_i
      );

end architecture;
