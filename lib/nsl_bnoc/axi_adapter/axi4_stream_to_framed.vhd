library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.axi_adapter.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

entity axi4_stream_to_framed is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t;

    framed_o : out framed_req_t;
    framed_i : in framed_ack_t
    );
end entity;

architecture rtl of axi4_stream_to_framed is

  signal data_s : byte_string(0 to 0);

begin

  data_s <= bytes(axi4_stream_framed_config_c, axi_i);

  -- Direct combinatorial mapping
  framed_o <= framed_flit(data => data_s(0),
                         last => is_last(axi4_stream_framed_config_c, axi_i),
                         valid => is_valid(axi4_stream_framed_config_c, axi_i));

  axi_o <= accept(axi4_stream_framed_config_c, framed_i.ready = '1');

end architecture;
