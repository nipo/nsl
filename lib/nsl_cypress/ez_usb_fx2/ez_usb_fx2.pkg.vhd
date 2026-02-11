library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;

package ez_usb_fx2 is

  constant fx2_data_width_c : natural := 8;
  
  constant fx2_ep2_addr_c : std_ulogic_vector(1 downto 0) := "00";
  constant fx2_ep4_addr_c : std_ulogic_vector(1 downto 0) := "01";
  constant fx2_ep6_addr_c : std_ulogic_vector(1 downto 0) := "10";
  constant fx2_ep8_addr_c : std_ulogic_vector(1 downto 0) := "11";

  type fx2_ep_t is (
    FX2_EP2,
    FX2_EP4,
    FX2_EP6,
    FX2_EP8
    );

  type fx2_flag_t is (
    FX2_FLAGA,
    FX2_FLAGB,
    FX2_FLAGC,
    FX2_FLAGD
    );

  subtype fx2_addr_t is std_ulogic_vector(1 downto 0);
  function get_fifoaddr(ep: fx2_ep_t) return fx2_addr_t;  
  
  type fx2_o is record
    full_n  : std_ulogic;
    empty_n : std_ulogic;
    data    : std_ulogic_vector(fx2_data_width_c-1 downto 0);
  end record;

  type fx2_i is record
    addr    : std_ulogic_vector(1 downto 0);
    wr_n    : std_ulogic;
    rd_n    : std_ulogic;
    oe_n    : std_ulogic;
    data    : std_ulogic_vector(fx2_data_width_c-1 downto 0);
    pktend  : std_ulogic;
  end record;

  type fx2_flags_o is record
    flag_a : std_ulogic;
    flag_b : std_ulogic;
    flag_c : std_ulogic;
    flag_d : std_ulogic;
    data   : std_ulogic_vector(fx2_data_width_c-1 downto 0);
  end record;
  
  type fx2_io is record
    o : fx2_o;
    i : fx2_i;
  end record;

  -- Controller designed to interface with EZ-USB-FX2 configured in Slave FIFOs
  -- mode, with synchronous R/W and flags configured in indexed mode. (Untested)
  --
  -- The FX2 Slave FIFO interface does not preserve USB frame boundaries. As a
  -- result, TLAST is never asserted on the RX AXI-Stream bus (OUT). On the TX
  -- AXI-Stream bus (IN), asserting TLAST forces the controller to commit the
  -- current buffer by pulsing PKTEND, sending a short packet on the USB bus.
  component fx2_controller is
    generic(
      axi_cfg_c : nsl_amba.axi4_stream.config_t;
      rx_ep_c : fx2_ep_t := FX2_EP2;
      tx_ep_c : fx2_ep_t := FX2_EP6;
      addr_change_delay_c : natural := 0 
      );
    port(
      clock_i      : in std_ulogic;
      reset_n_i    : in std_ulogic;
      
      tx_i  : in nsl_amba.axi4_stream.master_t;
      tx_o  : out nsl_amba.axi4_stream.slave_t;
      
      rx_o  : out nsl_amba.axi4_stream.master_t;
      rx_i  : in nsl_amba.axi4_stream.slave_t;

      to_fx2_o   : out fx2_i;
      from_fx2_i : in fx2_o;

      addr_change_done_i : in std_ulogic := '1'
      );
  end component;

  -- Controller designed to interface with EZ-USB-FX2 configured in Slave FIFOs
  -- mode, with synchronous R/W and flags configured in fixed mode.
  -- Follows the read/write state machines described in the EZ-USB-FX2 manual.
  -- It's not optimized for speed.
  --
  -- The FX2 Slave FIFO interface does not preserve USB frame boundaries. As a
  -- result, TLAST is never asserted on the RX AXI-Stream bus (OUT). On the TX
  -- AXI-Stream bus (IN), asserting TLAST forces the controller to commit the
  -- current buffer by pulsing PKTEND, sending a short packet on the USB bus.
  component fx2_controller_fixed is
    generic(
      axi_cfg_c           : nsl_amba.axi4_stream.config_t;
      rx_ep_c             : fx2_ep_t   := FX2_EP2;
      rx_empty_flag_c     : fx2_flag_t := FX2_FLAGA;
      tx_ep_c             : fx2_ep_t   := FX2_EP6;
      tx_full_flag_c      : fx2_flag_t := FX2_FLAGB;
      addr_change_delay_c : natural := 0
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;
      
      tx_i  : in nsl_amba.axi4_stream.master_t;
      tx_o  : out nsl_amba.axi4_stream.slave_t;
      
      rx_o  : out nsl_amba.axi4_stream.master_t;
      rx_i  : in nsl_amba.axi4_stream.slave_t;

      to_fx2_o   : out fx2_i;
      from_fx2_i : in fx2_flags_o;

      addr_change_done_i : in std_ulogic := '1'
      );
  end component;

  -- Controller designed to interface with EZ-USB-FX2 configured in Slave FIFOs
  -- mode, with synchronous R/W and flags configured in fixed mode.
  -- Fastest version of fx2_controller_fixed.
  --
  -- The FX2 Slave FIFO interface does not preserve USB frame boundaries. As a
  -- result, TLAST is never asserted on the RX AXI-Stream bus (OUT). On the TX
  -- AXI-Stream bus (IN), asserting TLAST forces the controller to commit the
  -- current buffer by pulsing PKTEND, sending a short packet on the USB bus.
  component fx2_controller_fixed_fast is
    generic(
      axi_cfg_c           : nsl_amba.axi4_stream.config_t;
      rx_ep_c             : fx2_ep_t   := FX2_EP2;
      rx_empty_flag_c     : fx2_flag_t := FX2_FLAGA;
      tx_ep_c             : fx2_ep_t   := FX2_EP6;
      tx_full_flag_c      : fx2_flag_t := FX2_FLAGB;
      addr_change_delay_c : natural := 0
      );
    port(
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;
      
      tx_i  : in nsl_amba.axi4_stream.master_t;
      tx_o  : out nsl_amba.axi4_stream.slave_t;
      
      rx_o  : out nsl_amba.axi4_stream.master_t;
      rx_i  : in nsl_amba.axi4_stream.slave_t;

      to_fx2_o   : out fx2_i;
      from_fx2_i : in fx2_flags_o;

      addr_change_done_i : in std_ulogic := '1'
      );
  end component;

end ez_usb_fx2;

package body ez_usb_fx2 is
  
  function get_fifoaddr(ep: fx2_ep_t) return fx2_addr_t
  is
  begin
    case ep is
      when FX2_EP2 =>
        return fx2_ep2_addr_c;
      when FX2_EP4 =>
        return fx2_ep4_addr_c;
      when FX2_EP6 =>
        return fx2_ep6_addr_c;
      when FX2_EP8 =>
        return fx2_ep8_addr_c;
    end case;
  end function;

end package body ez_usb_fx2;
