library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.pipe.all;
use nsl_bnoc.axi_adapter.all;
use nsl_data.bytestream.all;

entity axi4_stream_to_pipe is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    axi_i : in master_t;
    axi_o : out slave_t;

    pipe_o : out pipe_req_t;
    pipe_i : in pipe_ack_t
    );
end entity;

architecture rtl of axi4_stream_to_pipe is

  signal data_s : byte_string(0 to 0);

begin

  data_s <= bytes(axi4_stream_pipe_config_c, axi_i);

  -- Direct combinatorial mapping (no last signal for pipe)
  pipe_o <= pipe_flit(data => data_s(0),
                     valid => is_valid(axi4_stream_pipe_config_c, axi_i));

  axi_o <= accept(axi4_stream_pipe_config_c, pipe_i.ready = '1');

end architecture;
