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

  component framed_dumper is
    generic(
      name_c: string
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      val_i       : in nsl_bnoc.framed.framed_req;
      ack_i       : in nsl_bnoc.framed.framed_ack
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
                       data : inout byte_stream;
                       duty_nom: natural := 1;
                       duty_denom: natural := 1);

  procedure committed_get(signal req: in nsl_bnoc.committed.committed_req;
                          signal ack: out nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : inout byte_stream;
                          valid : out boolean;
                          duty_nom: natural := 1;
                          duty_denom: natural := 1);

  procedure framed_flit_put(signal req: out nsl_bnoc.framed.framed_req;
                            signal ack: in nsl_bnoc.framed.framed_ack;
                            signal clock: in std_ulogic;
                            data : in byte;
                            last : in boolean;
                            valid : in boolean := true);

  procedure framed_put(signal req: out nsl_bnoc.framed.framed_req;
                       signal ack: in nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       data : in byte_string;
                       duty_nom: natural := 1;
                       duty_denom: natural := 1);

  procedure framed_wait(signal req: out nsl_bnoc.framed.framed_req;
                       signal ack: in nsl_bnoc.framed.framed_ack;
                       signal clock: in std_ulogic;
                       cycles : in integer);

  procedure framed_check(
    log_context: string;
    signal req: in nsl_bnoc.framed.framed_req;
    signal ack: out nsl_bnoc.framed.framed_ack;
    signal clock: in std_ulogic;
    data : in byte_string;
    level : log_level_t := LOG_LEVEL_WARNING;
    duty_nom: natural := 1;
    duty_denom: natural := 1);

  procedure committed_put(signal req: out nsl_bnoc.committed.committed_req;
                          signal ack: in nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : in byte_string;
                          valid : in boolean;
                          duty_nom: natural := 1;
                          duty_denom: natural := 1);

  procedure committed_wait(signal req: out nsl_bnoc.committed.committed_req;
                       signal ack: in nsl_bnoc.committed.committed_ack;
                       signal clock: in std_ulogic;
                       cycles : in integer);

  procedure committed_assert(
    log_context: string;
    rx_data : in byte_string;
    rx_valid : in boolean;
    ref_data : in byte_string;
    ref_valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING);

  procedure committed_check(
    log_context: string;
    signal req: in nsl_bnoc.committed.committed_req;
    signal ack: out nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    data : in byte_string;
    valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING;
    duty_nom: natural := 1;
    duty_denom: natural := 1);
  
  type committed_queue_item;

  type committed_queue is access committed_queue_item;

  type committed_queue_item is
  record
    chain : committed_queue;
    data : byte_stream;
    valid : boolean;
  end record;

  type committed_queue_root is access committed_queue;

  procedure committed_queue_init(
    variable root: inout committed_queue_root);

  procedure committed_queue_master_worker(
    signal req: out nsl_bnoc.committed.committed_req;
    signal ack: in nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    variable root: inout committed_queue_root;
    constant context: string := "");

  procedure committed_queue_slave_worker(
    signal req: in nsl_bnoc.committed.committed_req;
    signal ack: out nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    variable root: inout committed_queue_root);

  procedure committed_queue_put(
    variable root: inout committed_queue_root;
    data : in byte_string;
    valid : in boolean);

  procedure committed_queue_get(
    variable root: inout committed_queue_root;
    data : out byte_stream;
    valid : out boolean;
    dt : in time := 10 ns);

  procedure committed_queue_check(
    log_context: string;
    variable root: inout committed_queue_root;
    data : in byte_string;
    valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING);


  procedure framed_assert(
    log_context: string;
    rx_data : in byte_string;
    ref_data : in byte_string;
    level : log_level_t := LOG_LEVEL_WARNING);
  
  type framed_queue_item;

  type framed_queue is access framed_queue_item;

  type framed_queue_item is
  record
    chain : framed_queue;
    data : byte_stream;
    valid : boolean;
  end record;

  type framed_queue_root is access framed_queue;

  procedure framed_queue_init(
    variable root: inout framed_queue_root);

  procedure framed_queue_master_worker(
    signal req: out nsl_bnoc.framed.framed_req;
    signal ack: in nsl_bnoc.framed.framed_ack;
    signal clock: in std_ulogic;
    variable root: inout framed_queue_root;
    constant context: string := "");

  procedure framed_queue_slave_worker(
    signal req: in nsl_bnoc.framed.framed_req;
    signal ack: out nsl_bnoc.framed.framed_ack;
    signal clock: in std_ulogic;
    variable root: inout framed_queue_root);

  procedure framed_queue_put(
    variable root: inout framed_queue_root;
    data : in byte_string);

  procedure framed_queue_get(
    variable root: inout framed_queue_root;
    data : out byte_stream;
    dt : in time := 10 ns);

  procedure framed_queue_check(
    log_context: string;
    variable root: inout framed_queue_root;
    data : in byte_string;
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
                       data : inout byte_stream;
                       duty_nom: natural := 1;
                       duty_denom: natural := 1)
  is
    variable ret: byte_stream;
    variable item: byte;
    variable last: boolean;
  begin
    ret := new byte_string(1 to 0);

    while true
    loop
      for i in 0 to duty_nom-1
      loop
        framed_flit_get(req, ack, clock, item, last);
        write(ret, item);
        if last then
          data := ret;
          return;
        end if;
      end loop;
      for i in duty_nom to duty_denom-1
      loop
        wait until rising_edge(clock);
        wait until falling_edge(clock);
      end loop;
    end loop;
  end procedure;

  procedure committed_get(signal req: in nsl_bnoc.committed.committed_req;
                          signal ack: out nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : inout byte_stream;
                          valid : out boolean;
                          duty_nom: natural := 1;
                          duty_denom: natural := 1)
  is
    variable frame: byte_stream;
  begin
    framed_get(req, ack, clock, frame,
               duty_nom, duty_denom);

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
                       data : in byte_string;
                       duty_nom: natural := 1;
                       duty_denom: natural := 1)
  is
    variable i: integer range data'left to data'right := data'left;
  begin
    while true
    loop
      for x in 0 to duty_nom-1
      loop
        framed_flit_put(req, ack, clock, data(i), i = data'right);
        if i = data'right then
          return;
        end if;
        i := i + 1;
      end loop;
      for x in duty_nom to duty_denom-1
      loop
        wait until rising_edge(clock);
        wait until falling_edge(clock);
      end loop;
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

  procedure framed_check(
    log_context: string;
    signal req: in nsl_bnoc.framed.framed_req;
    signal ack: out nsl_bnoc.framed.framed_ack;
    signal clock: in std_ulogic;
    data : in byte_string;
    level : log_level_t := LOG_LEVEL_WARNING;
    duty_nom: natural := 1;
    duty_denom: natural := 1)
  is
    variable rx_data: byte_stream;
  begin
    framed_get(req, ack, clock, rx_data,
               duty_nom, duty_denom);

    if rx_data.all'length /= data'length
      or rx_data.all /= data then
      log(LOG_LEVEL_INFO, log_context & ": " &
          " > " & to_string(rx_data.all)
          & " *** BAD");
      log(level, log_context & ": " &
          " * " & to_string(data)
          & " *** Expected");
      return;
    end if;

    log_info(log_context & ": " &
             " > " & to_string(rx_data.all)
             & " OK");

  end procedure;

  procedure committed_put(signal req: out nsl_bnoc.committed.committed_req;
                          signal ack: in nsl_bnoc.committed.committed_ack;
                          signal clock: in std_ulogic;
                          data : in byte_string;
                          valid : in boolean;
                          duty_nom: natural := 1;
                          duty_denom: natural := 1)
  is
  begin
    framed_put(req, ack, clock, data & to_byte(if_else(valid, 1, 0)),
               duty_nom, duty_denom);
  end procedure;

  procedure committed_assert(
    log_context: string;
    rx_data : in byte_string;
    rx_valid : in boolean;
    ref_data : in byte_string;
    ref_valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
  begin
    if ref_valid /= rx_valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data)
          & ", valid: " & to_string(rx_valid)
          & " *** Expected valid = " & to_string(ref_valid));
      return;
    end if;

    if not ref_valid then
      log_info(log_context & ": " &
          " > " & to_string(rx_data)
          & ", not valid, as expected");
      return;
    end if;

    if not rx_valid then
      log(level, log_context & ": " &
          " > " & to_string(rx_data)
          & ", rx valid: " & to_string(rx_valid)
          & " OK");
      return;
    end if;

    if rx_data'length /= ref_data'length
      or rx_data /= ref_data then
      log(LOG_LEVEL_INFO, log_context & ": " &
          " > " & to_string(rx_data)
          & ", valid: " & to_string(rx_valid)
          & " *** BAD");
      log(level, log_context & ": " &
          " * " & to_string(ref_data)
          & ", valid: " & to_string(ref_valid)
          & " *** Expected");
      return;
    end if;

    log_info(log_context & ": " &
             " > " & to_string(rx_data)
             & ", valid: " & to_string(rx_valid)
             & " OK");
  end procedure;

  procedure committed_check(
    log_context: string;
    signal req: in nsl_bnoc.committed.committed_req;
    signal ack: out nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    data : in byte_string;
    valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING;
    duty_nom: natural := 1;
    duty_denom: natural := 1)
  is
    variable rx_data: byte_stream;
    variable rx_valid: boolean;
  begin
    committed_get(req, ack, clock, rx_data, rx_valid,
                  duty_nom, duty_denom);
    committed_assert(log_context, rx_data.all, rx_valid, data, valid, level);
    deallocate(rx_data);
  end procedure;

  procedure committed_wait(signal req: out nsl_bnoc.committed.committed_req;
                       signal ack: in nsl_bnoc.committed.committed_ack;
                       signal clock: in std_ulogic;
                       cycles : in integer)
  is
  begin
    framed_wait(req, ack, clock, cycles);
  end procedure;

  procedure committed_queue_init(
    variable root: inout committed_queue_root)
  is
  begin
    root := new committed_queue;
    root.all := null;
  end procedure;

  procedure committed_queue_master_worker(
    signal req: out nsl_bnoc.committed.committed_req;
    signal ack: in nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    variable root: inout committed_queue_root;
    constant context: string := "")
  is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    while true
    loop
      committed_wait(req, ack, clock, 1);
      committed_queue_get(root, data, valid);
      committed_put(req, ack, clock, data.all, valid);
      deallocate(data);
    end loop;
  end procedure;

  procedure committed_queue_slave_worker(
    signal req: in nsl_bnoc.committed.committed_req;
    signal ack: out nsl_bnoc.committed.committed_ack;
    signal clock: in std_ulogic;
    variable root: inout committed_queue_root)
  is
    variable data: byte_stream;
    variable valid: boolean;
  begin
    while true
    loop
      committed_get(req, ack, clock, data, valid);
      committed_queue_put(root, data.all, valid);
      deallocate(data);
    end loop;
  end procedure;

  procedure committed_queue_put(
    variable root: inout committed_queue_root;
    data : in byte_string;
    valid : in boolean)
  is
    variable item, chain : committed_queue;
  begin
    item := new committed_queue_item;
    item.all.data := new byte_string(0 to data'length-1);
    item.all.data.all := data;
    item.all.valid := valid;
    item.all.chain := null;

    if root.all = null then
      root.all := item;
    else
      chain := root.all;
      while chain.all.chain /= null
      loop
        chain := chain.all.chain;
      end loop;
      chain.all.chain := item;
    end if;
  end procedure;

  procedure committed_queue_get(
    variable root: inout committed_queue_root;
    data : out byte_stream;
    valid : out boolean;
    dt : in time := 10 ns)
  is
    variable item : committed_queue;
  begin
    while true
    loop
      if root.all /= null then
        item := root.all;
        root.all := root.all.chain;
        data := item.data;
        valid := item.valid;
        deallocate(item);
        return;
      end if;
      wait for dt;
    end loop;
  end procedure;

  procedure committed_queue_check(
    log_context: string;
    variable root: inout committed_queue_root;
    data : in byte_string;
    valid : in boolean;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable rx_data: byte_stream;
    variable rx_valid: boolean;
  begin
    committed_queue_get(root, rx_data, rx_valid);
    committed_assert(log_context, rx_data.all, rx_valid, data, valid, level);
    deallocate(rx_data);
  end procedure;

  procedure framed_queue_init(
    variable root: inout framed_queue_root)
  is
  begin
    root := new framed_queue;
    root.all := null;
  end procedure;

  procedure framed_queue_master_worker(
    signal req: out nsl_bnoc.framed.framed_req;
    signal ack: in nsl_bnoc.framed.framed_ack;
    signal clock: in std_ulogic;
    variable root: inout framed_queue_root;
    constant context: string := "")
  is
    variable data: byte_stream;
  begin
    while true
    loop
      framed_wait(req, ack, clock, 1);
      framed_queue_get(root, data);
      framed_put(req, ack, clock, data.all);
      deallocate(data);
    end loop;
  end procedure;

  procedure framed_queue_slave_worker(
    signal req: in nsl_bnoc.framed.framed_req;
    signal ack: out nsl_bnoc.framed.framed_ack;
    signal clock: in std_ulogic;
    variable root: inout framed_queue_root)
  is
    variable data: byte_stream;
  begin
    while true
    loop
      framed_get(req, ack, clock, data);
      framed_queue_put(root, data.all);
      deallocate(data);
    end loop;
  end procedure;

  procedure framed_queue_put(
    variable root: inout framed_queue_root;
    data : in byte_string)
  is
    variable item, chain : framed_queue;
  begin
    item := new framed_queue_item;
    item.all.data := new byte_string(0 to data'length-1);
    item.all.data.all := data;
    item.all.chain := null;

    if root.all = null then
      root.all := item;
    else
      chain := root.all;
      while chain.all.chain /= null
      loop
        chain := chain.all.chain;
      end loop;
      chain.all.chain := item;
    end if;
  end procedure;

  procedure framed_queue_get(
    variable root: inout framed_queue_root;
    data : out byte_stream;
    dt : in time := 10 ns)
  is
    variable item : framed_queue;
  begin
    while true
    loop
      if root.all /= null then
        item := root.all;
        root.all := root.all.chain;
        data := item.data;
        deallocate(item);
        return;
      end if;
      wait for dt;
    end loop;
  end procedure;

  procedure framed_queue_check(
    log_context: string;
    variable root: inout framed_queue_root;
    data : in byte_string;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
    variable rx_data: byte_stream;
  begin
    framed_queue_get(root, rx_data);
    framed_assert(log_context, rx_data.all, data, level);
    deallocate(rx_data);
  end procedure;

  procedure framed_assert(
    log_context: string;
    rx_data : in byte_string;
    ref_data : in byte_string;
    level : log_level_t := LOG_LEVEL_WARNING)
  is
  begin
    if rx_data'length /= ref_data'length
      or rx_data /= ref_data then
      log(LOG_LEVEL_INFO, log_context & ": " &
          " > " & to_string(rx_data)
          & " *** BAD");
      log(level, log_context & ": " &
          " * " & to_string(ref_data)
          & " *** Expected");
      return;
    end if;

    log_info(log_context & ": " &
             " > " & to_string(rx_data)
             & " OK");
  end procedure;

end package body;
