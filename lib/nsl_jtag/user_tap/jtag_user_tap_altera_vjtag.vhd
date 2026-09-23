library ieee;
use ieee.std_logic_1164.all;

-- User chains on an Altera part, as one virtual JTAG node behind the
-- SLD hub Quartus inserts.
--
-- The hub owns USER0 and USER1: a USER1 scan loads its virtual IR,
-- holding a node address and that node's IR, and a USER0 scan then
-- reaches the addressed node's DR with no framing added.  This node
-- carries a one-bit IR selecting port 0 or port 1, so a host selects
-- a port with one USER1 scan and then shifts its DR under USER0 like
-- any other user chain.
--
-- The node reports node_vendor_c, node_type_c and node_version_c to
-- hub enumeration, as user_tap's package states.
--
-- There is no hard TAP to reach here: the hub connects itself to the
-- part's JTAG, so the chip_* ports are unused.  run_o is the TAP's
-- own Run-Test/Idle, whatever instruction is loaded.
entity jtag_user_tap is
  generic(
    user_port_count_c : integer := 1;
    node_vendor_c : natural range 0 to 2047 := 16#5ff#;
    node_type_c : natural range 0 to 255 := 0;
    node_version_c : natural range 0 to 15 := 0
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

architecture altera_vjtag of jtag_user_tap is

  component sld_virtual_jtag_basic is
    generic (
      sld_mfg_id : natural := 0;
      sld_type_id : natural := 0;
      sld_version : natural := 0;
      sld_instance_index : natural := 0;
      sld_auto_instance_index : string := "NO";
      sld_ir_width : natural := 1;
      sld_sim_n_scan : natural := 0;
      sld_sim_action : string := "UNUSED";
      sld_sim_total_length : natural := 0;
      lpm_type : string := "sld_virtual_jtag_basic";
      lpm_hint : string := "UNUSED"
      );
    port (
      tck : out std_logic;
      tdi : out std_logic;
      ir_in : out std_logic_vector(sld_ir_width-1 downto 0);
      tdo : in std_logic;
      ir_out : in std_logic_vector(sld_ir_width-1 downto 0);
      virtual_state_cdr : out std_logic;
      virtual_state_sdr : out std_logic;
      virtual_state_udr : out std_logic;
      jtag_state_tlr : out std_logic;
      jtag_state_rti : out std_logic
      );
  end component;

  signal ir_s : std_logic_vector(0 downto 0);
  signal selected_s : std_ulogic_vector(0 to 1);
  signal tdo_s : std_ulogic;

begin

  selected_s(0) <= not ir_s(0);
  selected_s(1) <= ir_s(0) when user_port_count_c > 1 else '0';
  selected_o <= selected_s(0 to user_port_count_c-1);

  tdo_s <= tdo_i(user_port_count_c-1) when ir_s(0) = '1' else tdo_i(0);

  chip_tdo_o <= '0';

  inst: sld_virtual_jtag_basic
    generic map(
      sld_mfg_id => node_vendor_c,
      sld_type_id => node_type_c,
      sld_version => node_version_c,
      sld_auto_instance_index => "YES",
      sld_ir_width => 1
      )
    port map(
      tck => tck_o,
      tdi => tdi_o,
      ir_in => ir_s,
      tdo => tdo_s,
      ir_out => ir_s,
      virtual_state_cdr => capture_o,
      virtual_state_sdr => shift_o,
      virtual_state_udr => update_o,
      jtag_state_tlr => tlr_o,
      jtag_state_rti => run_o
      );

end architecture;
