library ieee;
use ieee.std_logic_1164.all, ieee.numeric_std.all;

library nsl_usb, nsl_math;
use nsl_usb.utmi.all;
use nsl_usb.usb.all;

entity sie_management is
  generic (
    hs_supported_c : boolean := false;
    phy_clock_rate_c : integer := 60000000
    );
  port (
    reset_n_i     : in  std_ulogic;
    app_reset_n_o : out std_ulogic;
    hs_o          : out std_ulogic;
    suspend_o     : out std_ulogic;
    chirp_tx_o    : out std_ulogic;

    phy_system_o : out utmi_system_sie2phy;
    phy_system_i : in utmi_system_phy2sie
    );
end entity sie_management;

architecture beh of sie_management is

  function t_cycles(s : real) return integer
  is
  begin
    return integer(s * real(phy_clock_rate_c));
  end function;

  -- Table 7-14
  constant T_FILTSE0      : integer := t_cycles(2.5e-6 * 1.1);
  constant T_FILT         : integer := t_cycles(2.5e-6 * 1.1);
  -- Is there a spec symbol for this ?
  constant T_IDLE_SUSPEND : integer := t_cycles(3.0e-3);
  constant T_UCHEND       : integer := t_cycles(7.0e-3);
  constant T_UCH          : integer := t_cycles(1.0e-3);
  constant T_WTFS         : integer := t_cycles(1.0e-3 * 1.1);
  constant T_WTRSTHS      : integer := t_cycles(100.0e-6 * 1.1);

  -- Custom timeout
  constant T_ATTACH_WAIT  : integer := t_cycles(2.0e-4);

  constant t04_wrap  : integer := 2**nsl_math.arith.log2(nsl_math.arith.max(T_FILT, T_FILTSE0));
  constant t1_wrap : integer := 2**nsl_math.arith.log2(T_UCHEND - T_UCH);

  -- Implementation of Figure C-2 / C-3.
  type state_t is (
    ST_RESET,
    ST_ATTACH_WAIT,

    ST_FS_RESET,
    ST_FS_RESET_WAIT,
    ST_FS_ENTER,
    ST_FS,
    ST_FS_SUSPENDED,

    ST_HS_SUSPENDED,
    ST_HS_SUSPEND_EXIT,

    ST_RESET_HANDSHAKE_ENTER,
    ST_RESET_HANDSHAKE_SEND,
    ST_RESET_HANDSHAKE_RECEIVE,
    ST_HS_DEFAULT,
    ST_HS_EXIT
    );

  type regs_t is
  record
    state     : state_t;
    -- Both used for T0 and T4 in Figure C-2/C-3 diagrams
    t04       : integer range 0 to t04_wrap-1;
    t1        : integer range 0 to t1_wrap-1;
    c0        : integer range 0 to 3;
    chirp_rx_j : boolean;
    linestate : usb_symbol_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(phy_system_i.clock, reset_n_i) is
  begin
    if rising_edge(phy_system_i.clock) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, phy_system_i) is
  begin
    rin <= r;

    if r.t04 /= 0 then
      rin.t04 <= r.t04 - 1;
    end if;

    if r.t1 /= 0 then
      rin.t1 <= r.t1 - 1;
    end if;

    rin.linestate <= phy_system_i.line_state;

    case r.state is
      when ST_RESET =>
        rin.t1 <= T_ATTACH_WAIT;
        rin.state <= ST_ATTACH_WAIT;

      when ST_ATTACH_WAIT =>
        if r.t1 = 0 then
          rin.state <= ST_FS_ENTER;
        end if;

      when ST_FS_RESET =>
        rin.state <= ST_FS_RESET_WAIT;

      when ST_FS_RESET_WAIT =>
        if r.linestate /= USB_SYMBOL_SE0 then
          rin.state <= ST_FS_ENTER;
        end if;

      when ST_FS_ENTER =>
        rin.t1 <= T_IDLE_SUSPEND;
        rin.t04 <= T_FILTSE0;
        rin.state <= ST_FS;

      when ST_FS =>
        if r.linestate /= USB_SYMBOL_SE0 then
          rin.t04 <= T_FILTSE0;
        end if;

        if r.linestate /= USB_SYMBOL_J then
          rin.t1 <= T_IDLE_SUSPEND;
        end if;

        if r.t04 = 0 then
          if hs_supported_c then
            rin.state <= ST_RESET_HANDSHAKE_ENTER;
          else
            rin.state <= ST_FS_RESET;
          end if;
        end if;

        if r.t1 = 0 then
          rin.state <= ST_FS_SUSPENDED;
        end if;

      when ST_FS_SUSPENDED =>
        if r.linestate /= USB_SYMBOL_J then
          rin.state <= ST_FS_ENTER;
        end if;

      when ST_HS_SUSPENDED =>
        if r.linestate = USB_SYMBOL_K then
          rin.state <= ST_HS_DEFAULT;
        elsif r.linestate = USB_SYMBOL_SE0 then
          rin.t1 <= T_UCHEND - T_UCH;
          rin.t04 <= T_FILTSE0;
          rin.state <= ST_HS_SUSPEND_EXIT;
        end if;

      when ST_HS_SUSPEND_EXIT =>
        if r.linestate /= USB_SYMBOL_SE0 then
          rin.t04 <= T_FILTSE0;
        end if;

        if r.t04 = 0 then
          rin.state <= ST_RESET_HANDSHAKE_ENTER;
        end if;

        if r.t1 = 0 then
          rin.state <= ST_HS_SUSPENDED;
        end if;

      when ST_RESET_HANDSHAKE_ENTER =>
        rin.state <= ST_RESET_HANDSHAKE_SEND;
        rin.t1 <= T_UCH;

      when ST_RESET_HANDSHAKE_SEND =>
        if r.t1 = 0 then
          rin.t1 <= T_WTFS;
          rin.c0 <= 0;
          rin.t04 <= T_FILT;
          rin.state <= ST_RESET_HANDSHAKE_RECEIVE;
          rin.chirp_rx_j <= false;
        end if;

      when ST_RESET_HANDSHAKE_RECEIVE =>
        if r.chirp_rx_j then
          if r.linestate /= USB_SYMBOL_J then
            rin.t04 <= T_FILT;
          end if;
        else
          if r.linestate /= USB_SYMBOL_K then
            rin.t04 <= T_FILT;
          end if;
        end if;

        if r.t04 = 0 then
          if r.c0 = 3 then
            rin.state <= ST_HS_DEFAULT;
            rin.t1 <= T_IDLE_SUSPEND;
          else
            if r.chirp_rx_j then
              rin.c0 <= r.c0 + 1;
            end if;
            rin.chirp_rx_j <= not r.chirp_rx_j;
            rin.t04 <= T_FILT;
          end if;
        end if;

        if r.t1 = 0 then
          rin.state <= ST_FS_RESET;
        end if;

      when ST_HS_DEFAULT =>
        if r.linestate /= USB_SYMBOL_SE0 then
          rin.t1 <= T_IDLE_SUSPEND;
        end if;

        if r.t1 = 0 then
          rin.t1 <= T_WTRSTHS;
          rin.state <= ST_HS_EXIT;
        end if;

      when ST_HS_EXIT =>
        if r.t1 = 0 then
          if r.linestate = USB_SYMBOL_SE0 then
            rin.state <= ST_RESET_HANDSHAKE_ENTER;
          else
            rin.state <= ST_HS_SUSPENDED;
          end if;
        end if;

    end case;
  end process;

  moore: process(r) is
  begin
    phy_system_o.suspend <= false;

    case r.state is
      when ST_RESET | ST_FS_RESET | ST_RESET_HANDSHAKE_ENTER =>
        app_reset_n_o <= '0';
        phy_system_o.reset <= '1';

      when others =>
        app_reset_n_o <= '1';
        phy_system_o.reset <= '0';
    end case;

    case r.state is
      when ST_HS_SUSPENDED | ST_HS_SUSPEND_EXIT | ST_HS_DEFAULT =>
        hs_o <= '1';

      when others =>
        hs_o <= '0';
    end case;

    case r.state is
      when ST_FS_SUSPENDED | ST_HS_SUSPENDED =>
        suspend_o <= '1';

      when others =>
        suspend_o <= '0';
    end case;

    case r.state is
      when ST_RESET_HANDSHAKE_SEND =>
        chirp_tx_o <= '1';

      when others =>
        chirp_tx_o <= '0';
    end case;

    case r.state is
      when ST_ATTACH_WAIT =>
        phy_system_o.op_mode <= UTMI_OP_MODE_NON_DRIVING;
        phy_system_o.xcvr_select <= UTMI_MODE_FS;
        phy_system_o.term_select <= UTMI_MODE_FS;

      when ST_RESET_HANDSHAKE_ENTER | ST_RESET_HANDSHAKE_SEND
        | ST_RESET_HANDSHAKE_RECEIVE =>
        phy_system_o.xcvr_select <= UTMI_MODE_HS;
        phy_system_o.term_select <= UTMI_MODE_FS;
        phy_system_o.op_mode <= UTMI_OP_MODE_STUFF_DIS;

      when ST_HS_DEFAULT =>
        phy_system_o.xcvr_select <= UTMI_MODE_HS;
        phy_system_o.term_select <= UTMI_MODE_HS;
        phy_system_o.op_mode <= UTMI_OP_MODE_NORMAL;

      when others =>
        phy_system_o.xcvr_select <= UTMI_MODE_FS;
        phy_system_o.term_select <= UTMI_MODE_FS;
        phy_system_o.op_mode <= UTMI_OP_MODE_NORMAL;

    end case;
  end process;

end architecture beh;
