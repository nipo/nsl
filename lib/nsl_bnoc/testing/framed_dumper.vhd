library ieee;
use ieee.std_logic_1164.all;

library work, nsl_data, nsl_simulation, nsl_bnoc;
use nsl_simulation.logging.all;
use nsl_data.text.all;
use nsl_data.bytestream.all;
use nsl_bnoc.framed.all;

entity framed_dumper is
  generic(
    name_c: string
    );
  port(
    reset_n_i   : in  std_ulogic;
    clock_i     : in  std_ulogic;

    val_i       : in nsl_bnoc.framed.framed_req;
    ack_i       : in nsl_bnoc.framed.framed_ack
    );
end entity;

architecture rtl of framed_dumper is

begin

  c: process(reset_n_i, clock_i) is
    variable v_current: byte_stream;
  begin
    if rising_edge(clock_i) then
      if val_i.valid = '1' and ack_i.ready = '1' then
        write(v_current, val_i.data);

        if val_i.last = '1' then
          log_info(name_c & ": " & to_string(v_current.all));
          clear(v_current);
        end if;
      end if;
    end if;

    if reset_n_i = '0' then
      clear(v_current);
    end if;
  end process;
  
end architecture;
