library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_bnoc, nsl_data, nsl_logic, nsl_simulation;
use nsl_simulation.logging.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_logic.bool.all;

package testing is

  component sized_file_reader
    generic (
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_out_val: out nsl_bnoc.sized.sized_req;
      p_out_ack: in nsl_bnoc.sized.sized_ack;
      
      p_done: out std_ulogic
      );
  end component;

  component sized_file_checker
    generic (
      filename: string
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_in_val: in nsl_bnoc.sized.sized_req;
      p_in_ack: out nsl_bnoc.sized.sized_ack;

      p_done     : out std_ulogic
      );
  end component;

  component framed_file_reader is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_val   : out nsl_bnoc.framed.framed_req;
      p_out_ack   : in nsl_bnoc.framed.framed_ack;

      p_done : out std_ulogic
      );
  end component;

  component framed_file_checker is
    generic(
      filename: string
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in nsl_bnoc.framed.framed_req;
      p_in_ack   : out nsl_bnoc.framed.framed_ack;

      p_done     : out std_ulogic
      );
  end component;

  procedure framed_flit_get(signal req: in nsl_bnoc.framed.framed_req;
                            signal ack: out nsl_bnoc.framed.framed_ack;
                            signal clock: in std_ulogic;
                            data : out byte;
                            last : out boolean);

  procedure framed_get(signal req: in nsl_bnoc.framed.framed_req;
                       signal ack: out nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       data : inout byte_stream);

  procedure committed_get(signal req: in nsl_bnoc.committed.committed_req;
                          signal ack: out nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : inout byte_stream;
                          valid : out boolean);

  procedure framed_flit_put(signal req: out nsl_bnoc.framed.framed_req;
                            signal ack: in nsl_bnoc.framed.framed_ack;
                            signal clock: in std_ulogic;
                            data : in byte;
                            last : in boolean;
                            valid : in boolean := true);

  procedure framed_put(signal req: out nsl_bnoc.framed.framed_req;
                       signal ack: in nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       data : in byte_string);

  procedure framed_wait(signal req: out nsl_bnoc.framed.framed_req;
                       signal ack: in nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       cycles : in integer);

  procedure committed_put(signal req: out nsl_bnoc.committed.committed_req;
                          signal ack: in nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : in byte_string;
                          valid : in boolean);

  procedure committed_wait(signal req: out nsl_bnoc.committed.committed_req;
                       signal ack: in nsl_bnoc.committed.committed_ack;
                       signal clock: in std_ulogic;
                       cycles : in integer);

  procedure committed_check(
    log_context: string;
    signal req: in nsl_bnoc.committed.committed_req;
    signal ack: out nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    data : in byte_string;
    valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING);
  
end package testing;

package body testing is

  procedure framed_flit_get(signal req: in nsl_bnoc.framed.framed_req;
                            signal ack: out nsl_bnoc.framed.framed_ack;
                            signal clock: in std_ulogic;
                            data : out byte;
                            last : out boolean)
  is
  begin
    while true
    loop
      ack.ready <= '1';

      wait until rising_edge(clock);

      if req.valid = '1' then
        data := req.data;
        last := req.last = '1';
        wait until falling_edge(clock);
        ack.ready <= '0';
        return;
      end if;
    end loop;
  end procedure;

  procedure framed_get(signal req: in nsl_bnoc.framed.framed_req;
                       signal ack: out nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       data : inout byte_stream)
  is
    variable ret: byte_stream;
    variable item: byte;
    variable last: boolean;
  begin
    ret := new byte_string(1 to 0);
    last := false;

    while not last
    loop
      framed_flit_get(req, ack, clock, item, last);
      write(ret, item);
    end loop;

    data := ret;
  end procedure;

  procedure committed_get(signal req: in nsl_bnoc.committed.committed_req;
                          signal ack: out nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : inout byte_stream;
                          valid : out boolean)
  is
    variable frame: byte_stream;
  begin
    framed_get(req, ack, clock, frame);

    data := new byte_string(0 to frame.all'length-2);
    data.all := frame.all(frame.all'left to frame.all'right-1);
    valid := frame.all(frame.all'length-1) = x"01";

    deallocate(frame);
  end procedure;

  procedure framed_flit_put(signal req: out nsl_bnoc.framed.framed_req;
                            signal ack: in nsl_bnoc.framed.framed_ack;
                            signal clock: in std_ulogic;
                            data : in byte;
                            last : in boolean;
                            valid : in boolean := true)
  is
  begin
    while true
    loop
      req.valid <= to_logic(valid);
      req.data <= data;
      req.last <= to_logic(last);

      wait until rising_edge(clock);

      if ack.ready = '1' or not valid then
        wait until falling_edge(clock);
        req.valid <= '0';
        return;
      end if;
    end loop;
  end procedure;

  procedure framed_put(signal req: out nsl_bnoc.framed.framed_req;
                       signal ack: in nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       data : in byte_string)
  is
  begin
    for i in data'range
    loop
      framed_flit_put(req, ack, clock, data(i), i = data'right);
    end loop;
  end procedure;

  procedure framed_wait(signal req: out nsl_bnoc.framed.framed_req;
                       signal ack: in nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       cycles : in integer)
  is
  begin
    for i in 0 to cycles-1
    loop
      framed_flit_put(req, ack, clock, "--------", false, false);
    end loop;
  end procedure;

  procedure committed_put(signal req: out nsl_bnoc.committed.committed_req;
                          signal ack: in nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : in byte_string;
                          valid : in boolean)
  is
  begin
    framed_put(req, ack, clock, data & to_byte(if_else(valid, 1, 0)));
  end procedure;

  procedure committed_check(
    log_context: string;
    signal req: in nsl_bnoc.committed.committed_req;
    signal ack: out nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    data : in byte_string;
    valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable rx_data: byte_stream;
    variable rx_valid: boolean;
  begin
    committed_get(req, ack, clock, rx_data, rx_valid);

    if valid /= rx_valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** Expected valid = " & to_string(valid));
      return;
    end if;

    if not valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", not valid, as expected");
      return;
    end if;

    if not rx_valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", rx valid: " & to_string(rx_valid)
          & " OK");
      return;
    end if;

    if rx_data.all'length /= data'length
      or rx_data.all /= data then
      log(level, log_context & ": " &
          " > " & to_string(rx_data.all)
          & ", valid: " & to_string(rx_valid)
          & " *** BAD");
      log(level, log_context & ": " &
          " * " & to_string(data)
          & ", valid: " & to_string(valid)
          & " *** Expected");
      return;
    end if;

    log_info(log_context & ": " &
             " > " & to_string(rx_data.all)
             & ", valid: " & to_string(rx_valid)
             & " OK");

  end procedure;

  procedure committed_wait(signal req: out nsl_bnoc.committed.committed_req;
                       signal ack: in nsl_bnoc.committed.committed_ack;
                       signal clock: in std_ulogic;
                       cycles : in integer)
  is
  begin
    framed_wait(req, ack, clock, cycles);
  end procedure;

end package body;
