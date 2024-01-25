library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_data, nsl_logic, nsl_simulation, work;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_logic.bool.all;
use work.wishbone.all;

-- Wishbone testing uses a hack from the simulation environment.
-- Using VHDL Shared variables in procedures only updates them when
-- exiting procedure. But if variable is itself a pointer (access),
-- you may have a shared context accross two procedures that does not
-- need to be a package-level global.  This allows to have
-- instantiable context for a simulated bus transactor.
--
-- This is what this package does.
--
-- One process must run the wb_test_queue_worker procedure while one
-- or many processes may queue accesses in parallel. They will be
-- processed as they come.
--
-- See tests/wishbone/base/src/tb.vhd for an example.
package testing is
  
  type wb_test_queue_item;

  type wb_test_queue is access wb_test_queue_item;

  type wb_test_op_t is
  record
    address: wb_addr_t;
    data: wb_data_t;
    sel: wb_sel_t;
    we: boolean;
    term: wb_term_t;
  end record;
    
  type wb_test_op_vector is array (natural range <>) of wb_test_op_t;
  type wb_test_op_stream is access wb_test_op_vector;
  
  type wb_test_queue_item is
  record
    chain : wb_test_queue;
    ops: wb_test_op_stream;
    done: boolean;
  end record;

  -- Type for a shared context between transactor and requestors.
  type wb_test_queue_root is access wb_test_queue;

  -- Initialization for shared context, should be called once before any other
  -- access.
  procedure wb_test_queue_init(
    variable root: inout wb_test_queue_root);

  -- Worker, should live forever in a process. Does not drive the clock.
  procedure wb_test_queue_worker(
    constant config: wb_config_t;
    signal req: out wb_req_t;
    signal ack: in wb_ack_t;
    signal clock: in std_ulogic;
    variable root: inout wb_test_queue_root;
    constant context: string := "");

  -- Queue execution a bunch of operations as a cycle. Poll for update /
  -- completion every dt.
  procedure wb_test_exec(
    variable root: inout wb_test_queue_root;
    variable ops: inout wb_test_op_vector;
    constant dt : in time := 10 ns);

  -- Perform a one-word write asap
  procedure wb_test_write(
    variable root: inout wb_test_queue_root;
    constant config: wb_config_t;
    constant address: in unsigned;
    constant data: in std_ulogic_vector;
    constant sel: in std_ulogic_vector;
    variable term : out wb_term_t;
    constant dt : in time := 10 ns);

  -- Perform a one-word read asap
  procedure wb_test_read(
    variable root: inout wb_test_queue_root;
    constant config: wb_config_t;
    constant address: in unsigned;
    variable data: out std_ulogic_vector;
    variable term : out wb_term_t;
    constant dt : in time := 10 ns);

  -- Perform a one-word read asap and check value against a
  -- constant. Data argument here may contain dontcare bits.
  procedure wb_test_read_check(
    variable root: inout wb_test_queue_root;
    constant config: wb_config_t;
    constant address: in unsigned;
    constant data: in std_ulogic_vector;
    constant context: in string := "";
    constant dt : in time := 10 ns;
    constant sev : in severity_level := warning);

end package testing;

package body testing is

  procedure wb_test_queue_init(
    variable root: inout wb_test_queue_root)
  is
  begin
    root := new wb_test_queue;
    root.all := null;
  end procedure;

  procedure wb_test_queue_get(
    variable root: inout wb_test_queue_root;
    variable item : out wb_test_queue;
    constant dt : in time := 10 ns)
  is
    variable ret : wb_test_queue;
  begin
    while true
    loop
      if root.all /= null then
        ret := root.all;
        root.all := root.all.chain;
        exit;
      end if;
      wait for dt;
    end loop;

    item := ret;
  end procedure;

  procedure wb_test_queue_get(
    variable root: inout wb_test_queue_root;
    variable item : out wb_test_queue;
    signal clock: in std_ulogic)
  is
    variable ret : wb_test_queue;
  begin
    while true
    loop
      if root.all /= null then
        ret := root.all;
        root.all := root.all.chain;
        exit;
      end if;
      wait until rising_edge(clock);
    end loop;

    item := ret;
  end procedure;

  procedure wb_test_queue_pushback(
    variable root: inout wb_test_queue_root;
    variable item: wb_test_queue)
  is
    variable chain : wb_test_queue;
  begin
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

  procedure wb_test_run(
    constant config: wb_config_t;
    signal req: out wb_req_t;
    signal ack: in wb_ack_t;
    signal clock: in std_ulogic;
    variable ops: inout wb_test_op_stream)
  is
    variable xops: wb_test_op_vector(0 to ops.all'length-1);
    variable req_index, ack_index: natural;
    variable term: wb_term_t;
  begin
    xops := ops.all;
    req_index := 0;
    ack_index := 0;

    while req_index < xops'length or ack_index < xops'length
    loop
      if req_index >= xops'length then
        req <= wbc_cycle(config);
      elsif xops(req_index).we then
        req <= wbc_write(config,
                         xops(req_index).address(wb_address_msb(config) downto 0),
                         xops(req_index).sel(wb_sel_width(config)-1 downto 0),
                         xops(req_index).data(wb_data_width(config)-1 downto 0));
      else
        req <= wbc_read(config,
                        xops(req_index).address(wb_address_msb(config) downto 0));
      end if;

      wait until falling_edge(clock);

      if req_index < xops'length and wbc_is_accepted(config, ack) then
        req_index := req_index + 1;
      end if;

      if ack_index < xops'length then
        term := wbc_term(config, ack);
        if term /= WB_TERM_NONE then
          xops(ack_index).term := term;
          ack_index := ack_index + 1;
        end if;
      end if;
      
      wait until rising_edge(clock);
    end loop;

    req <= wbc_req_idle(config);
    wait until rising_edge(clock);

    ops.all := xops;
  end procedure;

  procedure wb_test_queue_worker(
    constant config: wb_config_t;
    signal req: out wb_req_t;
    signal ack: in wb_ack_t;
    signal clock: in std_ulogic;
    variable root: inout wb_test_queue_root;
    constant context: string := "")
  is
    variable item : wb_test_queue;
  begin
    assert config.bus_type /= WB_REGISTERED
      report "Registered bus unsupported"
      severity failure;

    req <= wbc_req_idle(config);

    while true
    loop
      wb_test_queue_get(root, item, clock);

      wb_test_run(config, req, ack, clock, item.all.ops);
      item.all.done := true;
    end loop;
  end procedure;

  procedure wb_test_exec(
    variable root: inout wb_test_queue_root;
    variable ops: inout wb_test_op_vector;
    constant dt : in time := 10 ns)
  is
    variable item, chain : wb_test_queue;
  begin
    item := new wb_test_queue_item;
    item.all.chain := null;
    item.all.ops := new wb_test_op_vector(0 to ops'length-1);
    item.all.ops.all := ops;
    item.all.done := false;
    wb_test_queue_pushback(root, item);

    while not item.all.done
    loop
      wait for dt;
    end loop;

    ops := item.all.ops.all;
    deallocate(item.all.ops);
    deallocate(item);
  end procedure;

  procedure wb_test_write(
    variable root: inout wb_test_queue_root;
    constant config: wb_config_t;
    constant address: in unsigned;
    constant data: in std_ulogic_vector;
    constant sel: in std_ulogic_vector;
    variable term : out wb_term_t;
    constant dt : in time := 10 ns)
  is
    variable ops : wb_test_op_vector(0 to 0);
  begin
    ops(0).address := (others => '-');
    ops(0).data := (others => '-');
    ops(0).sel := (others => '-');
    ops(0).address(address'length-1 downto 0) := address;
    ops(0).data(data'length-1 downto 0) := data;
    ops(0).sel(sel'length-1 downto 0) := sel;
    ops(0).we := true;

    wb_test_exec(root, ops, dt);

    term := ops(0).term;
  end procedure;

  procedure wb_test_read(
    variable root: inout wb_test_queue_root;
    constant config: wb_config_t;
    constant address: in unsigned;
    variable data: out std_ulogic_vector;
    variable term : out wb_term_t;
    constant dt : in time := 10 ns)
  is
    variable ops : wb_test_op_vector(0 to 0);
  begin
    ops(0).address := (others => '-');
    ops(0).data := (others => '-');
    ops(0).sel := (others => '-');
    ops(0).address(address'length-1 downto 0) := address;
    ops(0).we := false;

    wb_test_exec(root, ops, dt);

    data := ops(0).data(data'length-1 downto 0);
    term := ops(0).term;
  end procedure;

  procedure wb_test_read_check(
    variable root: inout wb_test_queue_root;
    constant config: wb_config_t;
    constant address: in unsigned;
    constant data: in std_ulogic_vector;
    constant context: in string := "";
    constant dt : in time := 10 ns;
    constant sev : in severity_level := warning)
  is
    variable ops : wb_test_op_vector(0 to 0);
    variable rdata: std_ulogic_vector(data'length-1 downto 0);
    variable term : wb_term_t;
  begin
    wb_test_read(root, config, address, rdata, term, dt);

    assert_match(context & " at address " & to_string(address), data, rdata, sev);

  end procedure;

end package body;
