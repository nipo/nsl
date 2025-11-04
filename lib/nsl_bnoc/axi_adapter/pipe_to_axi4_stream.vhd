library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_bnoc, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_bnoc.pipe.all;
use nsl_bnoc.axi_adapter.all;
use nsl_data.bytestream.all;

entity pipe_to_axi4_stream is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    pipe_i : in pipe_req_t;
    pipe_o : out pipe_ack_t;

    axi_o : out master_t;
    axi_i : in slave_t
    );
end entity;

architecture rtl of pipe_to_axi4_stream is
begin

  -- Direct combinatorial mapping (no last signal for pipe)
  axi_o <= transfer(axi4_stream_pipe_config_c,
                   bytes => (0 => pipe_i.data),
                   valid => pipe_i.valid = '1');

  pipe_o <= pipe_accept(is_ready(axi4_stream_pipe_config_c, axi_i));

end architecture;
