library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data, nsl_logic, nsl_math;
use nsl_logic.bool.all;
use nsl_bnoc.framed.all;
use nsl_bnoc.framed_transactor.all;
use nsl_data.endian.all;
use nsl_data.bytestream.all;
use nsl_math.fixed.all;

package pct2075 is

  type pct2075_reg_t is (
    PCT2075_REG_TEMP,
    PCT2075_REG_CONF,
    PCT2075_REG_THYST,
    PCT2075_REG_TOS,
    PCT2075_REG_TIDLE
    );

  function pct2075_reg_set(saddr: unsigned; reg: pct2075_reg_t; value: std_ulogic_vector) return byte_string;
  
  -- Spawn a byte string suitable for
  -- nsl_bnoc.framed_transactor.framed_transactor_once for proper
  -- initialization of device.
  function pct2075_init(saddr: unsigned;
                        queue: integer;
                        os_active_value: std_ulogic;
                        os_is_interrupt: boolean;
                        running: boolean;
                        period: real;
                        t_hi, t_low: real) return byte_string;

  -- PCT2075 reader.
  --
  -- If IRQ is available, reads the inputs as long as IRQ is asserted.
  --
  -- Use routed_transactor_once for initialization of device
  component pct2075_reader is
    generic(
      i2c_addr_c    : unsigned(6 downto 0) := "0100000";

      -- Minimum interval between two temperature readings.
      irq_backoff_timeout_c : integer := 0;

      -- If set to a non-zero value, set Thys (low limit reg) and Tots
      -- (high limit reg) around current temperature and wait for
      -- interrupt.  If set to zero, simply wait irq_backoff_timeout_c
      -- between two inconditional readings, do not update Thys and Tots.
      temp_threshold_c: real := 0.0
      );
    port(
      reset_n_i   : in std_ulogic;
      clock_i     : in std_ulogic;

      -- allow transactions
      enable_i : in std_ulogic := '1';

      -- Forces refresh
      force_i : in std_ulogic := '0';

      busy_o  : out std_ulogic;

      -- Only used if temp_threshold_c is non-zero.
      irq_n_i     : in std_ulogic := '1';

      temp_o       : out sfixed(7 downto -3);

      cmd_o  : out nsl_bnoc.framed.framed_req;
      cmd_i  : in  nsl_bnoc.framed.framed_ack;
      rsp_i  : in  nsl_bnoc.framed.framed_req;
      rsp_o  : out nsl_bnoc.framed.framed_ack
      );
  end component;

end package pct2075;

package body pct2075 is

  function pct2075_reg_set(saddr: unsigned; reg: pct2075_reg_t; value: std_ulogic_vector) return byte_string
  is
    variable pointer: byte := to_byte(pct2075_reg_t'pos(reg));
  begin
    return i2c_write(saddr, pointer & to_be(unsigned(value)));
  end function;

  function pct2075_init(saddr: unsigned;
                        queue: integer;
                        os_active_value: std_ulogic;
                        os_is_interrupt: boolean;
                        running: boolean;
                        period: real;
                        t_hi, t_low: real) return byte_string
  is
    variable os_f_que: std_ulogic_vector(1 downto 0);
    variable os_comp_int: std_ulogic;
    variable shutdown: std_ulogic;
    variable tidle: unsigned(4 downto 0);
    variable tos, thyst: signed(15 downto 7);
  begin
    case queue is
      when 1 => os_f_que := "00";
      when 2 => os_f_que := "01";
      when 4 => os_f_que := "10";
      when 6 => os_f_que := "11";
      when others => assert false report "Bad queue value" severity failure;
    end case;

    os_comp_int := not to_logic(os_is_interrupt);
    shutdown := not to_logic(running);

    tidle := to_unsigned(integer(period / 100.0e-3), 5);
    tos := to_signed(integer(t_hi / 0.5), 9);
    thyst := to_signed(integer(t_low / 0.5), 9);

    return null_byte_string
      & pct2075_reg_set(saddr, PCT2075_REG_CONF, "000" & os_f_que & os_active_value & os_comp_int & shutdown)
      & pct2075_reg_set(saddr, PCT2075_REG_THYST, std_ulogic_vector(thyst) & "0000000")
      & pct2075_reg_set(saddr, PCT2075_REG_TOS, std_ulogic_vector(tos) & "0000000")
      & pct2075_reg_set(saddr, PCT2075_REG_TIDLE, "000" & std_ulogic_vector(tidle))
      & i2c_write_read(saddr, from_hex("00"), 2)
      ;
  end function;

end package body pct2075;
