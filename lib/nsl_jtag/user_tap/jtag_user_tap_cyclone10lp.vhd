library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

-- Cyclone 10 LP user chains, USER0 (IR 0x00C) on port 0 and USER1
-- (IR 0x00E) on port 1.
--
-- The device atom gives the pad signals back and qualifies shift,
-- update and run-test/idle with "IR is a user instruction", but has
-- no capture strobe and no USER0 select.  Both are derived here from
-- a TAP state machine and an IR shadow tracking the hard TAP, which
-- then are the only source for every output.
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

  subtype ir_t is std_ulogic_vector(9 downto 0);
  type ir_vector is array (natural range <>) of ir_t;

  constant ir_idcode_c : ir_t := "0000000110";
  constant ir_user_c : ir_vector(0 to 1) := ("0000001100", "0000001110");

  type state_t is (
    ST_TLR,
    ST_RTI,
    ST_SELECT_DR,
    ST_CAPTURE_DR,
    ST_SHIFT_DR,
    ST_EXIT1_DR,
    ST_PAUSE_DR,
    ST_EXIT2_DR,
    ST_UPDATE_DR,
    ST_SELECT_IR,
    ST_CAPTURE_IR,
    ST_SHIFT_IR,
    ST_EXIT1_IR,
    ST_PAUSE_IR,
    ST_EXIT2_IR,
    ST_UPDATE_IR
    );

  type regs_t is
  record
    state : state_t;
    ir_shreg, ir : ir_t;
  end record;

  signal r, rin: regs_t;

  signal tck_unbuf_s, tck_s, tms_s, tdi_s, tdo_s : std_logic;
  signal tdouser_s : std_logic;
  signal selected_s : std_ulogic_vector(0 to 1);
  signal user_s, run_s, capture_s, shift_s, update_s : std_ulogic;

begin

  regs: process(tck_s) is
  begin
    if rising_edge(tck_s) then
      r <= rin;
    end if;
  end process;

  transition: process(r, tms_s, tdi_s) is
  begin
    rin <= r;

    case r.state is
      when ST_TLR =>
        rin.ir <= ir_idcode_c;
      when ST_SHIFT_IR =>
        rin.ir_shreg <= tdi_s & r.ir_shreg(r.ir_shreg'left downto 1);
      when ST_UPDATE_IR =>
        rin.ir <= r.ir_shreg;
      when others =>
        null;
    end case;

    if tms_s = '0' then
      case r.state is
        when ST_TLR | ST_RTI | ST_UPDATE_DR | ST_UPDATE_IR => rin.state <= ST_RTI;
        when ST_SELECT_DR => rin.state <= ST_CAPTURE_DR;
        when ST_CAPTURE_DR | ST_SHIFT_DR | ST_EXIT2_DR => rin.state <= ST_SHIFT_DR;
        when ST_EXIT1_DR | ST_PAUSE_DR => rin.state <= ST_PAUSE_DR;
        when ST_SELECT_IR => rin.state <= ST_CAPTURE_IR;
        when ST_CAPTURE_IR | ST_SHIFT_IR | ST_EXIT2_IR => rin.state <= ST_SHIFT_IR;
        when ST_EXIT1_IR | ST_PAUSE_IR => rin.state <= ST_PAUSE_IR;
      end case;
    else
      case r.state is
        when ST_TLR | ST_SELECT_IR => rin.state <= ST_TLR;
        when ST_RTI | ST_UPDATE_DR | ST_UPDATE_IR => rin.state <= ST_SELECT_DR;
        when ST_SELECT_DR => rin.state <= ST_SELECT_IR;
        when ST_CAPTURE_DR | ST_SHIFT_DR => rin.state <= ST_EXIT1_DR;
        when ST_EXIT1_DR | ST_EXIT2_DR => rin.state <= ST_UPDATE_DR;
        when ST_PAUSE_DR => rin.state <= ST_EXIT2_DR;
        when ST_CAPTURE_IR | ST_SHIFT_IR => rin.state <= ST_EXIT1_IR;
        when ST_EXIT1_IR | ST_EXIT2_IR => rin.state <= ST_UPDATE_IR;
        when ST_PAUSE_IR => rin.state <= ST_EXIT2_IR;
      end case;
    end if;
  end process;

  moore: process(r) is
  begin
    for i in selected_s'range
    loop
      if i < user_port_count_c and r.ir = ir_user_c(i) then
        selected_s(i) <= '1';
      else
        selected_s(i) <= '0';
      end if;
    end loop;

    tlr_o <= '0';
    run_s <= '0';
    capture_s <= '0';
    shift_s <= '0';
    update_s <= '0';

    case r.state is
      when ST_TLR => tlr_o <= '1';
      when ST_RTI => run_s <= '1';
      when ST_CAPTURE_DR => capture_s <= '1';
      when ST_SHIFT_DR => shift_s <= '1';
      when ST_UPDATE_DR => update_s <= '1';
      when others => null;
    end case;
  end process;

  user_s <= selected_s(0) or selected_s(1);

  tdo_mux: process(selected_s, tdo_i) is
  begin
    tdo_s <= tdo_i(0);
    if selected_s(1) = '1' then
      tdo_s <= tdo_i(user_port_count_c-1);
    end if;
  end process;

  tdo_launch: process(tck_s) is
  begin
    if falling_edge(tck_s) then
      tdouser_s <= tdo_s;
    end if;
  end process;

  selected_o <= selected_s(0 to user_port_count_c-1);
  run_o <= run_s and user_s;
  capture_o <= capture_s and user_s;
  shift_o <= shift_s and user_s;
  update_o <= update_s and user_s;
  tdi_o <= tdi_s;
  tck_o <= tck_s;

  inst: cyclone10lp_jtag
    port map(
      tck => chip_tck_i,
      tms => chip_tms_i,
      tdi => chip_tdi_i,
      tdo => chip_tdo_o,
      tdouser => tdouser_s,
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
      clock_o => tck_s
      );

end architecture;
