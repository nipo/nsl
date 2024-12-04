library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_axi;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.prbs.all;
use nsl_data.crc.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;

entity tb is
end tb;

architecture arch of tb is
begin

  transfer_serializer: process
    use nsl_axi.axi4_stream.all;

    procedure serializer_torture(cfg: config_t;
                                 elements: string;
                                 loops: integer)
    is
      variable serin_v, serout_v: std_ulogic_vector(vector_length(cfg, elements)-1 downto 0);
      variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    begin
      for i in 0 to loops-1
      loop
        serin_v := prbs_bit_string(state_v, prbs31, serin_v'length);
        serout_v := vector_pack(cfg, elements, vector_unpack(cfg, elements, serin_v));
        if serin_v /= serout_v then
          log_info("Hint: "&to_string(serin_v xor serout_v)&" "&to_string(cfg, vector_unpack(cfg, elements, serin_v xor serout_v)));
        end if;
        assert_equal(to_string(cfg), serin_v, serout_v, failure);

        state_v := prbs_forward(state_v, prbs31, serin_v'length);
      end loop;

      log_info(to_string(cfg) & " stream torture OK");
    end procedure;
  begin
    serializer_torture(config(bytes => 2, user => 3, id => 5, dest => 6, strobe => true, keep => true, last => true), "idskouvl", 128);
    serializer_torture(config(bytes => 2, strobe => true, keep => true, last => true), "idskouvl", 128);
    serializer_torture(config(bytes => 2, strobe => true, keep => true), "idskouv", 128);
    serializer_torture(config(bytes => 2, strobe => true, keep => true), "iskdouv", 128);
    serializer_torture(config(bytes => 2, strobe => true, keep => true), "ouvidsk", 128);

    wait;
  end process;
  
end;
