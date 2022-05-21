library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_bnoc, nsl_mii, nsl_logic, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_bnoc.framed.all;
use nsl_mii.rgmii.all;

entity rgmii_smi_status_poller is
  generic(
    refresh_hz_c : real := 2.0;
    clock_i_hz_c: natural;
    phy_type_c: phy_type_t
    );
  port(
    reset_n_i   : in std_ulogic;
    clock_i     : in std_ulogic;

    irq_n_i    : in std_ulogic := '0';

    phyad_i : in unsigned(4 downto 0);
    
    link_up_o: out std_ulogic;
    mode_o: out rgmii_mode_t;
    fd_o: out std_ulogic;
    
    cmd_o  : out framed_req;
    cmd_i  : in  framed_ack;
    rsp_i  : in  framed_req;
    rsp_o  : out framed_ack
    );
end entity;

architecture beh of rgmii_smi_status_poller is

  constant auto_refresh_reload_c: natural := integer(realmax(1.0, real(clock_i_hz_c) / realmax(0.1, refresh_hz_c))) - 1;
  
  type cmd_state_t is (
    CMD_RESET,
    CMD_IDLE,

    CMD_PUT_READ,
    CMD_PUT_ADDR,
    CMD_WAIT_DONE
    );

  type rsp_state_t is (
    RSP_RESET,
    RSP_IDLE,

    RSP_VALUE_H,
    RSP_VALUE_L,
    RSP_STAT,
    RSP_REPORT
    );

  constant reg_isr_c   : natural := 0;
  constant reg_bmcr_c  : natural := 1;
  constant reg_bmsr_c  : natural := 2;
  constant reg_anar_c  : natural := 3;
  constant reg_lpar_c  : natural := 4;
  constant reg_gsr_c   : natural := 5;
  constant reg_gcr_c   : natural := 6;
  constant reg_gst1_c  : natural := 7;
  constant reg_count_c : natural := 8;
  
  subtype register_value_t is unsigned(15 downto 0);
  subtype register_addr_t is std_ulogic_vector(4 downto 0);
  type register_value_vector is array (natural range <>) of register_value_t;
  type register_addr_vector is array (natural range <>) of register_addr_t;

  constant dp83xxx_isr_addr_c: register_addr_t := "10011";
  -- The way RTL8211F has a banked register set at address 0x10-0x17.
  -- Bank base address is set in register 0x1f.
  -- Actual register address is (bank << 3) | (addr & 0x7)
  -- Registers 0x00-0x0f and 0x18-0x1f are not really banked.
  -- IEEE register set starts at bank 0xa40.
  -- IEEE reigster 0 is accessible at reg 0x00 (any bank) or bank 0xa40 reg 0x18.
  -- ISR at 0x1d is always mapped.
  constant rtl8211f_isr_addr_c: register_addr_t := "11101";

  function isr_reg_addr(t: phy_type_t) return register_addr_t is
  begin
    case t is
      when PHY_DP83xxx => return dp83xxx_isr_addr_c;
      when PHY_RTL8211F => return rtl8211f_isr_addr_c;
    end case;
  end function;

  constant register_addr_c : register_addr_vector(0 to reg_count_c-1) := (
    reg_isr_c  => isr_reg_addr(phy_type_c),
    reg_bmcr_c => "00000",
    reg_bmsr_c => "00001",
    reg_anar_c => "00100",
    reg_lpar_c => "00101",
    reg_gsr_c  => "01111",
    reg_gcr_c  => "01001",
    reg_gst1_c => "01010"
    );

  type regs_t is
  record
    cmd_state: cmd_state_t;
    cmd_index: integer range 0 to reg_count_c-1;
    rsp_state: rsp_state_t;
    rsp_index: integer range 0 to reg_count_c-1;

    refresh_timeout: integer range 0 to auto_refresh_reload_c;
    
    link_up: std_ulogic;
    mode: rgmii_mode_t;
    fd: std_ulogic;
    phyad : std_ulogic_vector(4 downto 0);
    
    value: register_value_vector(0 to reg_count_c-1);
    in_data: byte_string(0 to 1);
    in_left: integer range 0 to 2;
  end record;

  signal r, rin : regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cmd_state <= CMD_RESET;
      r.rsp_state <= RSP_RESET;
    end if;
  end process;

  transition: process(r, irq_n_i, cmd_i, rsp_i, phyad_i) is
    variable supports_10bt_hd, supports_100bt_hd, supports_1000bt_hd: boolean;
    variable announces_10bt_hd, announces_100bt_hd, announces_1000bt_hd: boolean;
    variable receives_10bt_hd, receives_100bt_hd, receives_1000bt_hd: boolean;
    variable supports_10bt_fd, supports_100bt_fd, supports_1000bt_fd: boolean;
    variable announces_10bt_fd, announces_100bt_fd, announces_1000bt_fd: boolean;
    variable receives_10bt_fd, receives_100bt_fd, receives_1000bt_fd: boolean;
    variable has_1g, link_up, autoneg_en, autoneg_done, force_fd, speed1, speed0: boolean;
  begin
    rin <= r;

    has_1g := r.value(reg_bmsr_c)(8) = '1';
    link_up := r.value(reg_bmsr_c)(2) = '1';
    autoneg_en := r.value(reg_bmcr_c)(12) = '1';
    autoneg_done := r.value(reg_bmsr_c)(5) = '1';
    force_fd := r.value(reg_bmcr_c)(8) = '1';
    speed1 := r.value(reg_bmcr_c)(6) = '1';
    speed0 := r.value(reg_bmcr_c)(13) = '1';
    
    supports_10bt_hd := r.value(reg_bmsr_c)(11) = '1';
    supports_10bt_fd := r.value(reg_bmsr_c)(12) = '1';
    supports_100bt_hd := r.value(reg_bmsr_c)(13) = '1';
    supports_100bt_fd := r.value(reg_bmsr_c)(14) = '1';
    supports_1000bt_hd := false;
    supports_1000bt_fd := false;

    announces_10bt_hd := r.value(reg_anar_c)(5) = '1';
    announces_10bt_fd := r.value(reg_anar_c)(6) = '1';
    announces_100bt_hd := r.value(reg_anar_c)(7) = '1';
    announces_100bt_fd := r.value(reg_anar_c)(8) = '1';
    announces_1000bt_hd := false;
    announces_1000bt_fd := false;

    if has_1g then
      announces_1000bt_hd := r.value(reg_gcr_c)(8) = '1';
      announces_1000bt_fd := r.value(reg_gcr_c)(9) = '1';
      supports_1000bt_hd := r.value(reg_gsr_c)(12) = '1';
      supports_1000bt_fd := r.value(reg_gsr_c)(13) = '1';
    end if;

    receives_10bt_hd := false;
    receives_10bt_fd := false;
    receives_100bt_hd := false;
    receives_100bt_fd := false;
    receives_1000bt_hd := false;
    receives_1000bt_fd := false;

    if autoneg_en and autoneg_done then
      receives_10bt_hd := r.value(reg_lpar_c)(5) = '1';
      receives_100bt_hd := r.value(reg_lpar_c)(7) = '1';
      receives_10bt_fd := r.value(reg_lpar_c)(6) = '1';
      receives_100bt_fd := r.value(reg_lpar_c)(8) = '1';
      if has_1g then
        receives_1000bt_hd := r.value(reg_gst1_c)(10) = '1';
        receives_1000bt_fd := r.value(reg_gst1_c)(11) = '1';
      end if;
    end if;
    
    if r.refresh_timeout /= 0 then
      rin.refresh_timeout <= r.refresh_timeout - 1;
    end if;
    
    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_IDLE;
        rin.refresh_timeout <= auto_refresh_reload_c;
        rin.link_up <= '0';

      when CMD_IDLE =>
        if irq_n_i = '0' and r.refresh_timeout = 0 then
          rin.refresh_timeout <= auto_refresh_reload_c;
          rin.cmd_state <= CMD_PUT_READ;
          rin.cmd_index <= reg_count_c-1;
          rin.phyad <= std_ulogic_vector(phyad_i);
        end if;

      when CMD_PUT_READ =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_ADDR;
        end if;

      when CMD_PUT_ADDR =>
        if cmd_i.ready = '1' then
          if r.cmd_index /= 0 then
            rin.cmd_index <= r.cmd_index - 1;
            rin.cmd_state <= CMD_PUT_READ;
          else
            rin.cmd_state <= CMD_WAIT_DONE;
          end if;
        end if;

      when CMD_WAIT_DONE =>
        if r.rsp_state = RSP_IDLE then
          rin.cmd_state <= CMD_IDLE;
        end if;
    end case;

    case r.rsp_state is
      when RSP_RESET =>
        rin.rsp_state <= RSP_IDLE;

      when RSP_IDLE =>
        if r.cmd_state = CMD_PUT_READ then
          rin.rsp_state <= RSP_VALUE_H;
          rin.rsp_index <= reg_count_c-1;
        end if;

      when RSP_VALUE_H =>
        if rsp_i.valid = '1' then
          rin.in_data(0) <= rsp_i.data;
          rin.rsp_state <= RSP_VALUE_L;
          if rsp_i.last = '1' then
            rin.rsp_state <= RSP_IDLE;
          end if;
        end if;

      when RSP_VALUE_L =>
        if rsp_i.valid = '1' then
          rin.in_data(1) <= rsp_i.data;
          rin.rsp_state <= RSP_STAT;
          if rsp_i.last = '1' then
            rin.rsp_state <= RSP_IDLE;
          end if;
        end if;

      when RSP_STAT =>
        if rsp_i.valid = '1' then
          rin.value(r.rsp_index) <= from_be(r.in_data);
          if r.rsp_index /= 0 then
            rin.rsp_index <= r.rsp_index - 1;
            rin.rsp_state <= RSP_VALUE_H;
            if rsp_i.last = '1' then
              rin.rsp_state <= RSP_IDLE;
            end if;
          else
            if rsp_i.last = '1' then
              rin.rsp_state <= RSP_REPORT;
            end if;
          end if;
        end if;

      when RSP_REPORT =>
        rin.rsp_state <= RSP_IDLE;

        rin.link_up <= to_logic(link_up);

        if not autoneg_en then
          if speed1 then
            rin.mode <= RGMII_MODE_1000;
          elsif speed0 then
            rin.mode <= RGMII_MODE_100;
          else
            rin.mode <= RGMII_MODE_10;
          end if;
          rin.fd <= to_logic(force_fd);
        elsif autoneg_done then
          if supports_1000bt_fd and announces_1000bt_fd and receives_1000bt_fd then
            rin.mode <= RGMII_MODE_1000;
            rin.fd <= '1';
          elsif supports_1000bt_hd and announces_1000bt_hd and receives_1000bt_hd then
            rin.mode <= RGMII_MODE_1000;
            rin.fd <= '0';
          elsif supports_100bt_fd and announces_100bt_fd and receives_100bt_fd then
            rin.mode <= RGMII_MODE_100;
            rin.fd <= '1';
          elsif supports_100bt_hd and announces_100bt_hd and receives_100bt_hd then
            rin.mode <= RGMII_MODE_100;
            rin.fd <= '0';
          elsif supports_10bt_fd and announces_10bt_fd and receives_10bt_fd then
            rin.mode <= RGMII_MODE_10;
            rin.fd <= '1';
          elsif supports_10bt_hd and announces_10bt_hd and receives_10bt_hd then
            rin.mode <= RGMII_MODE_10;
            rin.fd <= '0';
          end if;
        else
          rin.link_up <= '0';
        end if;
    end case;

  end process;

  moore: process(r) is
  begin
    case r.cmd_state is
      when CMD_RESET | CMD_IDLE | CMD_WAIT_DONE =>
        cmd_o <= framed_req_idle_c;

      when CMD_PUT_READ =>
        cmd_o <= framed_flit(data => "100" & r.phyad);

      when CMD_PUT_ADDR =>
        cmd_o <= framed_flit(data => "000" & register_addr_c(r.cmd_index),
                             last => r.cmd_index = 0);
    end case;
    
    case r.rsp_state is
      when RSP_RESET | RSP_IDLE | RSP_REPORT =>
        rsp_o <= framed_accept(false);

      when RSP_VALUE_H | RSP_VALUE_L | RSP_STAT =>
        rsp_o <= framed_accept(true);
    end case;

    link_up_o <= r.link_up;
    mode_o <= r.mode;
    fd_o <= r.fd;
  end process;

end architecture;
