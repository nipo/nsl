library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_bnoc, nsl_jtag, nsl_simulation, nsl_data, nsl_amba;
use nsl_jtag.jtag.all;
use nsl_jtag.transactor.all;
use nsl_jtag.apb_master.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

-- An ATE (framed transactor) drives a simulation TAP, whose first user
-- register is a jtag_apb_master, on a register map. The host writes
-- registers, reads them back, retries operations shifted too early, and
-- reads the error of an access out of the map.
entity tb is
end entity;

architecture arch of tb is

  constant idcode_c : std_ulogic_vector(31 downto 0) := x"87654321";
  constant idcode_instruction_c : std_ulogic_vector(3 downto 0) := x"2";
  constant user0_instruction_c : std_ulogic_vector(3 downto 0) := x"8";

  constant apb_config_c : nsl_amba.apb.config_t := nsl_amba.apb.apb3_config(
    address_width => 16,
    data_bus_width => 32,
    ready => true,
    err => true
    );
  constant width_c : natural := register_width(apb_config_c);
  -- Bits shifted before the command.
  constant pad_c : natural := 2;

  signal done_s : std_ulogic_vector(0 to 0);

  type framed_io is
  record
    cmd, rsp : nsl_bnoc.framed.framed_bus;
  end record;

  shared variable command_q, response_q : framed_queue_root;

  signal ate_o : nsl_jtag.jtag.jtag_ate_o;
  signal ate_i : nsl_jtag.jtag.jtag_ate_i;
  signal tap_o : nsl_jtag.jtag.jtag_tap_o;
  signal tap_i : nsl_jtag.jtag.jtag_tap_i;

begin

  host: process
    procedure do_io(response : out byte_stream; command : in byte_string) is
      variable rsp : byte_stream;
    begin
      framed_queue_put(command_q, command);
      framed_queue_get(response_q, rsp);
      response := rsp;
    end procedure;

    procedure chain_reset(div : integer range 1 to 256) is
      variable response : byte_stream;
    begin
      do_io(response, cmd_reset(5) & cmd_divisor(div) & cmd_reset(5) & cmd_run(1));
    end procedure;

    procedure ir_set(ir : std_ulogic_vector) is
      variable command, response : byte_stream;
    begin
      command := null;
      write(command, cmd_capture_ir);
      write(command, cmd_shift(ir, false));
      write(command, cmd_run(1));
      do_io(response, command.all);
      rsp(response);
      rsp_shift(response, ir'length);
      rsp(response);
    end procedure;

    -- One scan: shifts the command, returns the outcome captured, then
    -- spends idle_cycles in Run-Test/Idle.
    procedure scan(op : std_ulogic_vector(1 downto 0);
                   address : natural;
                   wdata : std_ulogic_vector(31 downto 0);
                   idle_cycles : natural;
                   done : out boolean;
                   error : out boolean;
                   rdata : out std_ulogic_vector(31 downto 0)) is
      variable command, response : byte_stream;
      variable tdi, tdo : std_ulogic_vector(pad_c + width_c - 1 downto 0);
    begin
      tdi := (others => '0');
      tdi(pad_c + 1 downto pad_c) := op;
      tdi(pad_c + 17 downto pad_c + 2) := std_ulogic_vector(to_unsigned(address, 16));
      tdi(pad_c + 49 downto pad_c + 18) := wdata;
      command := null;
      write(command, cmd_capture_dr);
      write(command, cmd_shift(tdi, true));
      for i in 1 to idle_cycles loop
        write(command, cmd_run(1));
      end loop;
      if idle_cycles = 0 then
        write(command, cmd_run(1));
      end if;
      do_io(response, command.all);
      rsp(response);
      rsp_shift(response, tdo);
      for i in 1 to idle_cycles loop
        rsp(response);
      end loop;
      if idle_cycles = 0 then
        rsp(response);
      end if;
      assert_equal("sync", tdo(7 downto 0), sync_c, failure);
      done := tdo(8) = '1';
      error := tdo(9) = '1';
      rdata := tdo(41 downto 10);
    end procedure;

    -- Shifts the operation until taken, then reads its outcome.
    procedure access_reg(op : std_ulogic_vector(1 downto 0);
                         address : natural;
                         wdata : std_ulogic_vector(31 downto 0);
                         error : out boolean;
                         rdata : out std_ulogic_vector(31 downto 0)) is
      variable done : boolean;
      variable e : boolean;
      variable d : std_ulogic_vector(31 downto 0);
    begin
      loop
        scan(op, address, wdata, 8, done, e, d);
        exit when done;
      end loop;
      loop
        scan("00", 0, x"00000000", 1, done, e, d);
        exit when done;
      end loop;
      error := e;
      rdata := d;
    end procedure;

    procedure write_reg(address : natural; value : std_ulogic_vector(31 downto 0)) is
      variable error : boolean;
      variable rdata : std_ulogic_vector(31 downto 0);
    begin
      access_reg(op_write_c, address, value, error, rdata);
      assert not error report "write error" severity failure;
    end procedure;

    procedure check_reg(address : natural; value : std_ulogic_vector(31 downto 0)) is
      variable error : boolean;
      variable rdata : std_ulogic_vector(31 downto 0);
    begin
      access_reg(op_read_c, address, x"00000000", error, rdata);
      assert not error report "read error" severity failure;
      assert_equal("register " & integer'image(address), rdata, value, failure);
    end procedure;

    variable done, error : boolean;
    variable rdata : std_ulogic_vector(31 downto 0);
  begin
    done_s(0) <= '0';
    framed_queue_init(command_q);
    framed_queue_init(response_q);
    wait for 40 ns;
    chain_reset(3);
    ir_set(user0_instruction_c);

    write_reg(16#04#, x"deadbeef");
    write_reg(16#08#, x"01234567");
    check_reg(16#04#, x"deadbeef");
    check_reg(16#08#, x"01234567");

    -- A second operation shifted right after a write, while it is
    -- pending, is ignored.
    scan(op_write_c, 16#04#, x"cafef00d", 0, done, error, rdata);
    assert done report "idle master not done" severity failure;
    scan(op_write_c, 16#08#, x"55555555", 0, done, error, rdata);
    assert not done report "write not pending right after it is taken" severity failure;
    check_reg(16#04#, x"cafef00d");
    check_reg(16#08#, x"01234567");

    -- The map answers an error out of its registers.
    access_reg(op_read_c, 16#40#, x"00000000", error, rdata);
    assert error report "no error out of the map" severity failure;
    check_reg(16#04#, x"cafef00d");

    log_info("jtag_apb_master OK");
    done_s(0) <= '1';
    wait;
  end process;

  ate: block is
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;
    signal ate_io_s : framed_io;
  begin
    master_q: process is
    begin
      ate_io_s.cmd.req <= framed_req_idle_c;
      wait for 40 ns;
      framed_queue_master_worker(ate_io_s.cmd.req, ate_io_s.cmd.ack, clock_s, command_q);
    end process;

    slave_q: process is
    begin
      ate_io_s.rsp.ack <= framed_ack_idle_c;
      wait for 40 ns;
      framed_queue_slave_worker(ate_io_s.rsp.req, ate_io_s.rsp.ack, clock_s, response_q);
    end process;

    reset_sync_clk: nsl_clocking.async.async_edge
      port map(
        data_i => async_reset_n_s,
        data_o => clock_reset_n_s,
        clock_i => clock_s
        );

    ate_impl: nsl_jtag.transactor.framed_ate
      port map(
        clock_i => clock_s,
        reset_n_i => clock_reset_n_s,
        cmd_i => ate_io_s.cmd.req,
        cmd_o => ate_io_s.cmd.ack,
        rsp_o => ate_io_s.rsp.req,
        rsp_i => ate_io_s.rsp.ack,
        jtag_o => ate_o,
        jtag_i => ate_i
        );

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => 5 ns,
        reset_duration(0) => 5 ns,
        reset_n_o(0) => async_reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

  ate_i <= transport to_ate(tap_o);
  tap_i <= transport to_tap(ate_o);

  dut: block is
    signal clock_s : std_ulogic := '0';
    signal clock_reset_n_s : std_ulogic;
    signal async_reset_n_s : std_ulogic;
    signal apb_s : nsl_amba.apb.bus_t;
    signal reg_no_s : integer range 0 to 15;
    signal w_value_s, r_value_s : unsigned(31 downto 0);
    signal w_strobe_s : std_ulogic;
    type regs_t is array(0 to 15) of unsigned(31 downto 0);
    signal regs_s : regs_t := (others => (others => '0'));
  begin
    reset_sync_clk: nsl_clocking.async.async_edge
      port map(
        data_i => async_reset_n_s,
        data_o => clock_reset_n_s,
        clock_i => clock_s
        );

    tap: nsl_simulation.jtag.jtag_sim_tap
      generic map(
        idcode_c => idcode_c,
        idcode_instruction_c => idcode_instruction_c,
        user0_instruction_c => user0_instruction_c
        )
      port map(
        tck_i => tap_i.tck,
        tms_i => tap_i.tms,
        tdi_i => tap_i.tdi,
        tdo_o => tap_o.tdo.v
        );
    tap_o.tdo.en <= '1';

    master: nsl_jtag.apb_master.jtag_apb_master_tap
      generic map(
        config_c => apb_config_c
        )
      port map(
        clock_i => clock_s,
        reset_n_i => clock_reset_n_s,
        apb_o => apb_s.m,
        apb_i => apb_s.s
        );

    -- Registers at 0x00 to 0x3c, errors above.
    slave: process(apb_s.m, regs_s) is
      variable index : natural;
    begin
      index := to_integer(nsl_amba.apb.address(apb_config_c, apb_s.m)(15 downto 2));
      if index < 16 then
        apb_s.s <= nsl_amba.apb.read_response(apb_config_c, value => regs_s(index));
      else
        apb_s.s <= nsl_amba.apb.read_response(apb_config_c, value => x"00000000", error => true);
      end if;
    end process;

    write: process(clock_s) is
      variable index : natural;
    begin
      if rising_edge(clock_s) then
        index := to_integer(nsl_amba.apb.address(apb_config_c, apb_s.m)(15 downto 2));
        if nsl_amba.apb.is_access(apb_config_c, apb_s.m)
          and nsl_amba.apb.is_write(apb_config_c, apb_s.m) and index < 16 then
          regs_s(index) <= nsl_amba.apb.value(apb_config_c, apb_s.m);
        end if;
      end if;
    end process;

    driver: nsl_simulation.driver.simulation_driver
      generic map(
        clock_count => 1,
        reset_count => 1,
        done_count => done_s'length
        )
      port map(
        clock_period(0) => 7 ns,
        reset_duration(0) => 5 ns,
        reset_n_o(0) => async_reset_n_s,
        clock_o(0) => clock_s,
        done_i => done_s
        );
  end block;

end architecture;
