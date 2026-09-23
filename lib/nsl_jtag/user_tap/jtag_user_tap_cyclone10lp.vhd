library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking, nsl_jtag;

-- Cyclone 10 LP user chains, USER0 (IR 0x00C) on port 0 and USER1
-- (IR 0x00E) on port 1.
--
-- The device atom gives the pad signals back and qualifies shift,
-- update and run-test/idle with "IR is a user instruction", but has
-- no capture strobe and no USER0 select.  Both are derived here from
-- a TAP port shadowing the hard TAP, which then is the only source for
-- every output.
--
-- The atom's tck/tms/tdi/tdo must reach top-level ports named
-- altera_reserved_tck/tms/tdi/tdo.  Instantiating it inserts no SLD
-- hub, so SignalTap and virtual JTAG are unavailable alongside.
entity jtag_user_tap is
  generic(
    user_port_count_c : integer := 1
    );
  port(
    chip_tck_i : in std_ulogic := '0';
    chip_tms_i : in std_ulogic := '0';
    chip_tdi_i : in std_ulogic := '0';
    chip_tdo_o : out std_ulogic;

    tdo_i : in std_ulogic_vector(0 to user_port_count_c-1);
    selected_o : out std_ulogic_vector(0 to user_port_count_c-1);
    run_o : out std_ulogic;
    tck_o : out std_ulogic;
    tdi_o : out std_ulogic;
    tlr_o : out std_ulogic;
    shift_o : out std_ulogic;
    capture_o : out std_ulogic;
    update_o : out std_ulogic
    );
begin

  assert user_port_count_c <= 2 and user_port_count_c >= 1
    report "Bad user port count, supports 1 or 2"
    severity failure;

end entity;

architecture cyclone10lp of jtag_user_tap is

  component cyclone10lp_jtag is
    generic (
      lpm_type : string := "cyclone10lp_jtag"
      );
    port (
      tms : in std_logic := '0';
      tck : in std_logic := '0';
      tdi : in std_logic := '0';
      tdoutap : in std_logic := '0';
      tdouser : in std_logic := '0';
      tdo: out std_logic;
      tmsutap: out std_logic;
      tckutap: out std_logic;
      tdiutap: out std_logic;
      shiftuser: out std_logic;
      clkdruser: out std_logic;
      updateuser: out std_logic;
      runidleuser: out std_logic;
      usr1user: out std_logic
      );
  end component;

  constant ir_len_c : natural := 10;
  subtype ir_t is std_ulogic_vector(ir_len_c-1 downto 0);
  type ir_vector is array (natural range <>) of ir_t;

  constant ir_idcode_c : ir_t := "0000000110";
  constant ir_user_c : ir_vector(0 to 1) := ("0000001100", "0000001110");

  signal tck_unbuf_s, tms_s, tdi_s : std_logic;
  signal jtag_i_s : nsl_jtag.jtag.jtag_tap_i;
  signal jtag_o_s : nsl_jtag.jtag.jtag_tap_o;
  signal ir_s : ir_t;
  signal selected_s : std_ulogic_vector(0 to 1);
  signal user_s, run_s, capture_s, shift_s, update_s, tdo_s : std_ulogic;

begin

  jtag_i_s.tms <= tms_s;
  jtag_i_s.tdi <= tdi_s;
  jtag_i_s.trst <= '1';

  tap: nsl_jtag.tap.tap_port
    generic map(
      ir_len => ir_len_c
      )
    port map(
      jtag_i => jtag_i_s,
      jtag_o => jtag_o_s,
      default_instruction_i => ir_idcode_c,
      ir_o => ir_s,
      ir_out_i => (others => '0'),
      reset_o => tlr_o,
      run_o => run_s,
      dr_capture_o => capture_s,
      dr_shift_o => shift_s,
      dr_update_o => update_s,
      dr_tdi_o => tdi_o,
      dr_tdo_i => tdo_s
      );

  selection: process(ir_s) is
  begin
    for i in selected_s'range
    loop
      if i < user_port_count_c and ir_s = ir_user_c(i) then
        selected_s(i) <= '1';
      else
        selected_s(i) <= '0';
      end if;
    end loop;
  end process;

  user_s <= selected_s(0) or selected_s(1);

  tdo_mux: process(selected_s, tdo_i) is
  begin
    tdo_s <= tdo_i(0);
    if selected_s(1) = '1' then
      tdo_s <= tdo_i(user_port_count_c-1);
    end if;
  end process;

  selected_o <= selected_s(0 to user_port_count_c-1);
  run_o <= run_s and user_s;
  capture_o <= capture_s and user_s;
  shift_o <= shift_s and user_s;
  update_o <= update_s and user_s;
  tck_o <= jtag_i_s.tck;

  inst: cyclone10lp_jtag
    port map(
      tck => chip_tck_i,
      tms => chip_tms_i,
      tdi => chip_tdi_i,
      tdo => chip_tdo_o,
      tdouser => jtag_o_s.tdo.v,
      tckutap => tck_unbuf_s,
      tmsutap => tms_s,
      tdiutap => tdi_s,
      shiftuser => open,
      clkdruser => open,
      updateuser => open,
      runidleuser => open,
      usr1user => open
      );

  tck_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => tck_unbuf_s,
      clock_o => jtag_i_s.tck
      );

end architecture;
