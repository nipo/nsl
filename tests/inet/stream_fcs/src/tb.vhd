library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.crc.all;
use nsl_data.prbs.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_simulation.control.all;
use nsl_inet.mac.all;

entity tb is
end tb;

architecture arch of tb is
begin

  -- The mac layer folds the FCS over multiple bytes per cycle when
  -- the stream is wider than one byte.  Check that folding the FCS
  -- CRC by chunks of any stream width gives the same result as the
  -- byte-serial fold, for any packet length (including lengths that
  -- leave a partial chunk on the last beat).
  checker: process
    variable state_v : prbs_state(30 downto 0) := x"deadbee"&"111";
    variable ref_v, chunked_v: crc_state_t;
    variable idx_v, chunk_v: integer;
    variable data_v: byte_string(0 to 95);
  begin
    for len in 1 to data_v'length
    loop
      data_v(0 to len-1) := prbs_byte_string(state_v, prbs31, len);
      state_v := prbs_forward(state_v, prbs31, len * 8);

      ref_v := crc_update(fcs_params_c, crc_init(fcs_params_c),
                          data_v(0 to len-1));

      for wl2 in 0 to 2
      loop
        chunked_v := crc_init(fcs_params_c);
        idx_v := 0;
        while idx_v < len
        loop
          chunk_v := 2 ** wl2;
          if idx_v + chunk_v > len then
            chunk_v := len - idx_v;
          end if;
          chunked_v := crc_update(fcs_params_c, chunked_v,
                                  data_v(idx_v to idx_v + chunk_v - 1));
          idx_v := idx_v + chunk_v;
        end loop;

        assert_equal("length " & to_string(len)
                     & " chunk " & to_string(2 ** wl2),
                     crc_spill(fcs_params_c, chunked_v),
                     crc_spill(fcs_params_c, ref_v),
                     failure);
      end loop;
    end loop;

    log_info("FCS chunked folding OK");
    terminate(0);
  end process;

end;
