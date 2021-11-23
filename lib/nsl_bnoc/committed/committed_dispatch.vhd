library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;
use nsl_bnoc.framed.all;
use nsl_bnoc.committed.all;

entity committed_dispatch is
  generic(
    destination_count_c : natural
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    enable_i : in std_ulogic := '1';
    destination_i  : in natural range 0 to destination_count_c - 1;
    
    in_i   : in committed_req;
    in_o   : out committed_ack;

    out_o   : out committed_req_array(0 to destination_count_c - 1);
    out_i   : in committed_ack_array(0 to destination_count_c - 1)
    );
end entity;

architecture beh of committed_dispatch is

  signal out_s : framed_req_array(0 to destination_count_c - 1);

begin

  out_map: for i in out_s'range
  generate
    out_o(i) <= out_s(i);
  end generate;
  
  impl: nsl_bnoc.framed.framed_dispatch
    generic map(
      destination_count_c => destination_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i => clock_i,

      enable_i => enable_i,
      destination_i => destination_i,
      
      in_i => in_i,
      in_o => in_o,

      out_o => out_s,
      out_i => framed_ack_array(out_i)
      );

end architecture;

