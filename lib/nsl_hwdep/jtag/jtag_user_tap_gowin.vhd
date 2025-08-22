library ieee;
use ieee.std_logic_1164.all;

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

architecture gw1n of jtag_user_tap is

  attribute syn_black_box : boolean;
  signal tck_unbuf_s, tck_s, tlr_n_s, shift_dr_capture_dr_s, pause_s, update_s : std_ulogic;
  signal last_enable_s, capture_s, tdo_s, rti_s, enable_s : std_ulogic_vector(0 to 1);

  component GW_JTAG is
    port(
      tck_pad_i : in std_logic;
      tms_pad_i : in std_logic;
      tdi_pad_i : in std_logic;
      tdo_pad_o : out std_logic;
      tdo_er1_i : in std_logic;
      tdo_er2_i : in std_logic;
      tck_o : out std_logic;
      tdi_o : out std_logic;
      test_logic_reset_o : out std_logic;
      run_test_idle_er1_o : out std_logic;
      run_test_idle_er2_o : out std_logic;
      shift_dr_capture_dr_o : out std_logic;
      pause_dr_o : out std_logic;
      update_dr_o : out std_logic;
      enable_er1_o : out std_logic;
      enable_er2_o : out std_logic
      );
  end component;
  attribute syn_black_box of GW_JTAG : Component is true;
  
begin

  trans: process(tck_s) is
  begin
    if rising_edge(tck_s) then
      if user_port_count_c = 1 then
        if enable_s(1) = '1' then
          if capture_s(1) = '1' then
            tdo_s(1) <= '0';
          elsif shift_dr_capture_dr_s = '1' then
            tdo_s(1) <= chip_tdi_i;
          end if;
        end if;
      end if;

      for i in 0 to 1
      loop
        last_enable_s(i) <= enable_s(i);
        capture_s(i) <= '0';

        if last_enable_s(i) = '0' and enable_s(i) = '1' and rti_s(i) = '0' then
          capture_s(i) <= '1';
        end if;

        if update_s = '1' or rti_s(i) = '1' then
          last_enable_s(i) <= '0';
        end if;
      end loop;
    end if;
  end process;

  shift_o <= shift_dr_capture_dr_s;
  tdo_s(0 to user_port_count_c-1) <= tdo_i;
  selected_o <= enable_s(0 to user_port_count_c-1);
  run_o <= rti_s(0) or rti_s(1);
  tdi_o <= chip_tdi_i;
  tck_o <= tck_s;
  tlr_o <= not tlr_n_s;
  capture_o <= capture_s(0) or capture_s(1);
  update_o <= update_s;

  inst: GW_JTAG
    port map(
      tck_pad_i => chip_tck_i,
      tdi_pad_i => chip_tdi_i,
      tms_pad_i => chip_tms_i,
      tdo_pad_o => chip_tdo_o,

      tdo_er1_i => tdo_s(0),
      tdo_er2_i => tdo_s(1),
      tck_o => tck_unbuf_s,
      tdi_o => open,
      test_logic_reset_o => tlr_n_s,
      run_test_idle_er1_o => rti_s(0),
      run_test_idle_er2_o => rti_s(1),
      shift_dr_capture_dr_o => shift_dr_capture_dr_s,
      pause_dr_o => pause_s,
      update_dr_o => update_s,
      enable_er1_o => enable_s(0),
      enable_er2_o => enable_s(1)
      );

  tck_buf: gowin.components.bufg
    port map(
      i => tck_unbuf_s,
      o => tck_s
      );

end architecture;
