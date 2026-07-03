library ieee;
use ieee.std_logic_1164.all;

library nsl_clocking;

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

architecture lattice of jtag_user_tap is

  signal tck_unbuf_s, tck_s, tlr_n_s, shift_dr_s, update_s : std_ulogic;
  signal tdo_s, rti_s, sel_s : std_ulogic_vector(0 to 1);

  component JTAGG is
    generic(
      ER1 : string;
      ER2 : string
      );
    port(
      JSHIFT  : out std_ulogic;
      JUPDATE : out std_ulogic;
      JRSTN   : out std_ulogic;
      JRTI1   : out std_ulogic;
      JRTI2   : out std_ulogic;
      JCE1    : out std_ulogic;
      JCE2    : out std_ulogic;
      JTCK    : out std_ulogic;
      JTDI    : out std_ulogic;
      JTDO1   : in std_ulogic;
      JTDO2   : in std_ulogic
      );
  end component;
  attribute syn_black_box : boolean;
  attribute syn_black_box of JTAGG : component is true;
  attribute syn_noprune: boolean ;
  attribute syn_noprune of JTAGG: component is true;  

  function is_en(no: integer) return string
  is
  begin
    if no = 0 or user_port_count_c = 2 then
      return "ENABLED";
    end if;
    return "DISABLED";
  end function;

  type regs_t is
  record
    in_dr_branch, capture, last_tdi : std_ulogic_vector(0 to user_port_count_c-1);
  end record;

  signal r, rin: regs_t;
  
begin

  reg: process(tck_unbuf_s)
  begin
    if rising_edge(tck_unbuf_s) then
      r <= rin;
    end if;
  end process;

  transition: process(sel_s, rti_s, update_s, shift_dr_s, r)
  begin
    rin <= r;

    for i in 0 to user_port_count_c-1
    loop
      rin.in_dr_branch(i) <= sel_s(i);
      rin.capture(i) <= '0';

      if r.in_dr_branch(i) = '0' and sel_s(i) = '1' and rti_s(i) = '0' then
        rin.capture(i) <= '1';
      end if;

      if update_s = '1' or rti_s(i) = '1' then
        rin.in_dr_branch(i) <= '0';
      end if;
    end loop;
  end process;

  inst: JTAGG
    generic map(
      ER1 => is_en(0),
      ER2 => is_en(1)
      )
    port map(
      jshift => shift_dr_s,
      jupdate => update_s,
      jrstn => tlr_n_s,
      jrti1 => rti_s(0),
      jrti2 => rti_s(1),
      jce1 => sel_s(0),
      jce2 => sel_s(1),
      jtck => tck_unbuf_s,
      jtdi => tdi_o,
      jtdo1 => tdo_s(0),
      jtdo2 => tdo_s(1)
      );

  tlr_o <= not tlr_n_s;
  shift_o <= shift_dr_s;
  tck_o <= tck_s;
  update_o <= update_s;

  one_port: if user_port_count_c = 1
  generate
    tdo_s(0) <= tdo_i(0);
    tdo_s(1) <= '0';

    capture_o <= r.capture(0);
    run_o <= rti_s(0);
    selected_o(0) <= sel_s(0);
  end generate;

  two_ports: if user_port_count_c = 2
  generate
    tdo_s <= tdo_i;

    capture_o <= r.capture(0) or r.capture(1);
    run_o <= rti_s(0) or rti_s(1);
    selected_o(0) <= sel_s(0);
    selected_o(1) <= sel_s(1);
  end generate;

  tck_buf: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => tck_unbuf_s,
      clock_o => tck_s
      );

end architecture;
