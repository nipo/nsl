library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.axi_adapter.all;
use nsl_data.bytestream.all;

entity framed_to_axi4_stream is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    framed_i : in framed_req_t;
    framed_o : out framed_ack_t;

    axi_o : out master_t;
    axi_i : in slave_t
    );
end entity;

architecture rtl of framed_to_axi4_stream is
begin

  -- Direct combinatorial mapping
  axi_o <= transfer(axi4_stream_framed_config_c,
                   bytes => (0 => framed_i.data),
                   valid => framed_i.valid = '1',
                   last => framed_i.last = '1');

  framed_o <= framed_accept(is_ready(axi4_stream_framed_config_c, axi_i));

end architecture;
