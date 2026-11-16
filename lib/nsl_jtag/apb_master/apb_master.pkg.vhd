library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

-- APB master driven from scans of one JTAG data register: slow register
-- access to a design, needing nothing else than its TAP.
--
-- Each scan of the register exchanges one word, shifted LSB first.
-- The word shifted in is a command:
-- - bits 1-0: operation, "01" read, "10" write, others none,
-- - then the byte address, address_width bits of the APB configuration,
-- - then the write data, the data width of the APB configuration.
-- The word captured, shifted out, is the outcome of the previous
-- operation:
-- - bits 7-0: sync_c, telling where the word starts,
-- - bit 8: done, set when the previous operation is over. The
--   operation of the same scan is then taken. Otherwise, it is ignored,
--   and the host shifts it again,
-- - bit 9: error, set when the previous operation got an error,
-- - then the read data of the previous operation,
-- - zeros up to the register width.
--
-- The register keeps the last register_width() bits shifted in: a scan
-- may shift pad bits before the command. On some TAPs (Gowin), the
-- captured word leaves one bit late: the host looks for sync_c in the
-- first bits shifted out. An operation takes a few TCK cycles to
-- complete, the host may spend them in Run-Test/Idle before the scan
-- reading the outcome.
package apb_master is

  constant sync_c : std_ulogic_vector(7 downto 0) := x"a5";

  constant op_read_c : std_ulogic_vector(1 downto 0) := "01";
  constant op_write_c : std_ulogic_vector(1 downto 0) := "10";

  -- Bits of the data register for an APB configuration.
  function register_width(config: nsl_amba.apb.config_t) return natural;

  -- Bus side of the master, on the TAP signals of
  -- nsl_jtag.user_tap.jtag_user_tap for the user port it is wired to.
  component jtag_apb_master is
    generic(
      config_c : nsl_amba.apb.config_t
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      tck_i : in std_ulogic;
      tdi_i : in std_ulogic;
      tdo_o : out std_ulogic;
      selected_i : in std_ulogic;
      capture_i : in std_ulogic;
      shift_i : in std_ulogic;
      update_i : in std_ulogic;

      apb_o : out nsl_amba.apb.master_t;
      apb_i : in nsl_amba.apb.slave_t
      );
  end component;

  -- Master alone on the first user data register of the TAP.
  component jtag_apb_master_tap is
    generic(
      config_c : nsl_amba.apb.config_t;
      node_vendor_c : natural range 0 to 2047 := 16#5ff#;
      node_type_c : natural range 0 to 255 := 16#02#;
      node_version_c : natural range 0 to 15 := 0
      );
    port(
      chip_tck_i : in std_ulogic := '0';
      chip_tms_i : in std_ulogic := '0';
      chip_tdi_i : in std_ulogic := '0';
      chip_tdo_o : out std_ulogic;

      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      apb_o : out nsl_amba.apb.master_t;
      apb_i : in nsl_amba.apb.slave_t
      );
  end component;

end package;

package body apb_master is

  function register_width(config: nsl_amba.apb.config_t) return natural is
    constant data_width : natural := 8 * 2 ** config.data_bus_width_l2;
    constant command_width : natural := 2 + config.address_width + data_width;
    constant outcome_width : natural := 10 + data_width;
  begin
    if command_width > outcome_width then
      return command_width;
    end if;
    return outcome_width;
  end function;

end package body;
