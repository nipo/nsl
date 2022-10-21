library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library nsl_bnoc, work, nsl_logic, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_logic.bool.all;
use nsl_bnoc.framed.all;
use work.link_monitor.all;
use work.link.all;

entity link_monitor_smi is
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
    link_status_o: out link_status_t;
    
    cmd_o  : out framed_req;
    cmd_i  : in  framed_ack;
    rsp_i  : in  framed_req;
    rsp_o  : out framed_ack
    );
end entity;

architecture beh of link_monitor_smi is

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

  subtype reg_idx_t is integer range 0 to 7;
  constant gst1 : reg_idx_t := 0;
  constant gcr  : reg_idx_t := 1;
  constant gsr  : reg_idx_t := 2;
  constant lpar : reg_idx_t := 3;
  constant anar : reg_idx_t := 4;
  constant bmsr : reg_idx_t := 5;
  constant bmcr : reg_idx_t := 6;
  constant isr  : reg_idx_t := 7;
  
  type value_vector is array (reg_idx_t) of phy_reg_value_t;
  type addr_vector is array (reg_idx_t) of phy_reg_addr_t;

  constant dp83xxx_isr_addr_c: phy_reg_addr_t := "10011";
  -- The way RTL8211F has a banked register set at address 0x10-0x17.
  -- Bank base address is set in register 0x1f.
  -- Actual register address is (bank << 3) | (addr & 0x7)
  -- Registers 0x00-0x0f and 0x18-0x1f are not really banked.
  -- IEEE register set starts at bank 0xa40.
  -- IEEE reigster 0 is accessible at reg 0x00 (any bank) or bank 0xa40 reg 0x18.
  -- ISR at 0x1d is always mapped.
  constant rtl8211f_isr_addr_c: phy_reg_addr_t := "11101";
  constant lan8710_isr_addr_c: phy_reg_addr_t := "11101";

  function isr_reg_addr(t: phy_type_t) return phy_reg_addr_t is
  begin
    case t is
      when PHY_DP83xxx => return dp83xxx_isr_addr_c;
      when PHY_RTL8211F => return rtl8211f_isr_addr_c;
      when PHY_LAN8710 => return lan8710_isr_addr_c;
    end case;
  end function;

  constant addr_c : addr_vector := (
    isr  => isr_reg_addr(phy_type_c),
    bmcr => phy_reg_bmcr_c,
    bmsr => phy_reg_bmsr_c,
    anar => phy_reg_anar_c,
    lpar => phy_reg_lpar_c,
    gsr  => phy_reg_gsr_c,
    gcr  => phy_reg_gcr_c,
    gst1 => phy_reg_gst1_c
    );

  constant handle_1000_c: boolean := phy_supports(phy_type_c, LINK_SPEED_1000);
  constant handle_100_c: boolean := phy_supports(phy_type_c, LINK_SPEED_100);
  constant handle_10_c: boolean := phy_supports(phy_type_c, LINK_SPEED_10);
  constant handle_fd_c: boolean := phy_supports(phy_type_c, LINK_DUPLEX_FULL);
  constant handle_hd_c: boolean := phy_supports(phy_type_c, LINK_DUPLEX_HALF);
  
  function link_status_resolve(r: value_vector) return link_status_t
  is
    variable supports_10bt_hd, supports_100bt_hd, supports_1000bt_hd: boolean;
    variable announces_10bt_hd, announces_100bt_hd, announces_1000bt_hd: boolean;
    variable receives_10bt_hd, receives_100bt_hd, receives_1000bt_hd: boolean;
    variable supports_10bt_fd, supports_100bt_fd, supports_1000bt_fd: boolean;
    variable announces_10bt_fd, announces_100bt_fd, announces_1000bt_fd: boolean;
    variable receives_10bt_fd, receives_100bt_fd, receives_1000bt_fd: boolean;
    variable has_1g, autoneg_en, autoneg_done, force_fd: boolean;
    variable speed: std_ulogic_vector(1 downto 0);
    variable ret: link_status_t;
  begin
    ret.up := r(bmsr)(2) = '1';

    autoneg_en := r(bmcr)(12) = '1';
    autoneg_done := r(bmsr)(5) = '1';

    has_1g := r(bmsr)(8) = '1' and handle_1000_c;
    force_fd := r(bmcr)(8) = '1' and handle_fd_c;

    speed := r(bmcr)(6) & r(bmcr)(13);
    
    supports_10bt_hd := r(bmsr)(11) = '1' and handle_10_c and handle_hd_c;
    supports_10bt_fd := r(bmsr)(12) = '1' and handle_10_c and handle_fd_c;
    supports_100bt_hd := r(bmsr)(13) = '1' and handle_100_c and handle_hd_c;
    supports_100bt_fd := r(bmsr)(14) = '1' and handle_100_c and handle_fd_c;
    supports_1000bt_hd := false;
    supports_1000bt_fd := false;

    announces_10bt_hd := r(anar)(5) = '1';
    announces_10bt_fd := r(anar)(6) = '1';
    announces_100bt_hd := r(anar)(7) = '1';
    announces_100bt_fd := r(anar)(8) = '1';
    announces_1000bt_hd := false;
    announces_1000bt_fd := false;

    if has_1g then
      announces_1000bt_hd := r(gcr)(8) = '1' and handle_hd_c;
      announces_1000bt_fd := r(gcr)(9) = '1' and handle_fd_c;
      supports_1000bt_hd := r(gsr)(12) = '1' and handle_hd_c;
      supports_1000bt_fd := r(gsr)(13) = '1' and handle_fd_c;
    end if;

    receives_10bt_hd := false;
    receives_10bt_fd := false;
    receives_100bt_hd := false;
    receives_100bt_fd := false;
    receives_1000bt_hd := false;
    receives_1000bt_fd := false;

    -- Set defaults that can actually happen.
    if handle_10_c then
      ret.speed := LINK_SPEED_10;
    elsif handle_100_c then
      ret.speed := LINK_SPEED_100;
    else
      ret.speed := LINK_SPEED_1000;
    end if;

    if handle_hd_c then
      ret.duplex := LINK_DUPLEX_HALF;
    else
      ret.duplex := LINK_DUPLEX_FULL;
    end if;

    if not autoneg_en then
      if has_1g and (handle_100_c or handle_10_c) then
        case speed is
          when "00" =>
            ret.speed := LINK_SPEED_10;
          when "01" =>
            ret.speed := LINK_SPEED_100;
          when others =>
            ret.speed := LINK_SPEED_1000;
        end case;
      elsif handle_100_c and handle_10_c then
        case speed(0) is
          when '0' =>
            ret.speed := LINK_SPEED_10;
          when others =>
            ret.speed := LINK_SPEED_100;
        end case;
      else
        -- Only one speed handled ? Just leave it as-is
        null;
      end if;
            
      if force_fd then
        ret.duplex := LINK_DUPLEX_FULL;
      else
        ret.duplex := LINK_DUPLEX_HALF;
      end if;
    elsif autoneg_done then
      receives_10bt_hd := r(lpar)(5) = '1';
      receives_100bt_hd := r(lpar)(7) = '1';
      receives_10bt_fd := r(lpar)(6) = '1';
      receives_100bt_fd := r(lpar)(8) = '1';
      if has_1g then
        receives_1000bt_hd := r(gst1)(10) = '1';
        receives_1000bt_fd := r(gst1)(11) = '1';
      end if;

      if supports_1000bt_fd and announces_1000bt_fd and receives_1000bt_fd then
        ret.speed := LINK_SPEED_1000;
        ret.duplex := LINK_DUPLEX_FULL;
      elsif supports_1000bt_hd and announces_1000bt_hd and receives_1000bt_hd then
        ret.speed := LINK_SPEED_1000;
        ret.duplex := LINK_DUPLEX_HALF;
      elsif supports_100bt_fd and announces_100bt_fd and receives_100bt_fd then
        ret.speed := LINK_SPEED_100;
        ret.duplex := LINK_DUPLEX_FULL;
      elsif supports_100bt_hd and announces_100bt_hd and receives_100bt_hd then
        ret.speed := LINK_SPEED_100;
        ret.duplex := LINK_DUPLEX_HALF;
      elsif supports_10bt_fd and announces_10bt_fd and receives_10bt_fd then
        ret.speed := LINK_SPEED_10;
        ret.duplex := LINK_DUPLEX_FULL;
      elsif supports_10bt_hd and announces_10bt_hd and receives_10bt_hd then
        ret.speed := LINK_SPEED_10;
        ret.duplex := LINK_DUPLEX_HALF;
      end if;
    end if;

    return ret;
  end function;  
  
  type regs_t is
  record
    cmd_state: cmd_state_t;
    cmd_index: reg_idx_t;
    rsp_state: rsp_state_t;
    rsp_index: reg_idx_t;

    refresh_timeout: integer range 0 to auto_refresh_reload_c;

    link_status: link_status_t;
    phyad : std_ulogic_vector(4 downto 0);
    
    value: value_vector;
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
  begin
    rin <= r;

    if r.refresh_timeout /= 0 then
      rin.refresh_timeout <= r.refresh_timeout - 1;
    end if;
    
    case r.cmd_state is
      when CMD_RESET =>
        rin.cmd_state <= CMD_IDLE;
        rin.refresh_timeout <= auto_refresh_reload_c;
        rin.link_status <= link_status_resolve(value_vector'(others => x"0000"));

      when CMD_IDLE =>
        if irq_n_i = '0' and r.refresh_timeout = 0 then
          rin.refresh_timeout <= auto_refresh_reload_c;
          rin.cmd_state <= CMD_PUT_READ;
          rin.cmd_index <= reg_idx_t'low;
          rin.phyad <= std_ulogic_vector(phyad_i);
        end if;

      when CMD_PUT_READ =>
        if cmd_i.ready = '1' then
          rin.cmd_state <= CMD_PUT_ADDR;
        end if;

      when CMD_PUT_ADDR =>
        if cmd_i.ready = '1' then
          if r.cmd_index /= reg_idx_t'high then
            rin.cmd_index <= r.cmd_index + 1;
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
          rin.rsp_index <= reg_idx_t'low;
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
          if r.rsp_index /= reg_idx_t'high then
            rin.rsp_index <= r.rsp_index + 1;
            if rsp_i.last = '1' then
              rin.rsp_state <= RSP_IDLE;
            else
              rin.rsp_state <= RSP_VALUE_H;
            end if;
          else
            if rsp_i.last = '1' then
              rin.rsp_state <= RSP_REPORT;
            end if;
          end if;
        end if;

      when RSP_REPORT =>
        rin.rsp_state <= RSP_IDLE;

        rin.link_status <= link_status_resolve(r.value);
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
        cmd_o <= framed_flit(data => "000" & std_ulogic_vector(addr_c(r.cmd_index)),
                             last => r.cmd_index = reg_idx_t'high);
    end case;
    
    case r.rsp_state is
      when RSP_RESET | RSP_IDLE | RSP_REPORT =>
        rsp_o <= framed_accept(false);

      when RSP_VALUE_H | RSP_VALUE_L | RSP_STAT =>
        rsp_o <= framed_accept(true);
    end case;

    link_status_o <= r.link_status;
  end process;

end architecture;
