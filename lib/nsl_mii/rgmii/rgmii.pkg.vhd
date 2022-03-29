library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_mii;
use nsl_mii.mii.all;
use nsl_bnoc.committed.all;
use nsl_bnoc.framed.all;

package rgmii is

  -- RGMII is a transport for Layer 1.  Frames in and out of RGMII
  -- transceiver contain the whole ethernet frame, not including FCS,
  -- but with a status byte instead.  Payload may be padded. Padding
  -- is carried over.  There is no minimal size for frame TX, it is up
  -- to transmitter to abide minimal size constraints.
  --
  -- Layer 1 <-> layer 2 frame components:
  -- * Destination MAC [6]
  -- * Source MAC [6]
  -- * Ethertype [2]
  -- * Payload [*]
  -- * Status
  --   [0]   CRC valid / Frame complete
  --   [7:1] Reserved

  type rgmii_sdr_io_t is record
    -- data[3:0] + ctl(0), on wire first
    -- data[7:4] + ctl(1), on wire last
    data   : std_ulogic_vector(7 downto 0);
    dv, er : std_ulogic;
  end record;

  type rgmii_mode_t is (
    RGMII_MODE_10,
    RGMII_MODE_100,
    RGMII_MODE_1000
    );

  function to_logic(mode: rgmii_mode_t) return std_ulogic_vector;
  function to_string(mode: rgmii_mode_t) return string;
  function to_mode(rxd21: std_ulogic_vector(1 downto 0)) return rgmii_mode_t;
  
  -- RGMII driver. Implements 10/100/1000 transparently. Always feed a
  -- 125 MHz clock to TX clock.
  component rgmii_driver is
    generic(
      rx_clock_delay_ps_c: natural := 0;
      tx_clock_delay_ps_c: natural := 0;
      -- In bit time
      ipg_c : natural := 96
      );
    port(
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      rgmii_o : out rgmii_io_group_t;
      rgmii_i : in  rgmii_io_group_t;
      
      mode_i : in rgmii_mode_t;
      
      rx_o : out committed_req;
      rx_i : in committed_ack;

      tx_i : in committed_req;
      tx_o : out committed_ack
      );
  end component;

  component rgmii_smi_status_poller is
    generic(
      refresh_hz_c : real := 2.0;
      clock_i_hz_c: natural
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
  end component;

  component rgmii_tx_driver is
    generic(
      clock_delay_ps_c: natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      mode_i : in rgmii_mode_t;
      flit_i : in rgmii_sdr_io_t;
      ready_o : out std_ulogic;

      rgmii_o : out rgmii_io_group_t
      );
  end component;

  component rgmii_rx_driver is
    generic(
      clock_delay_ps_c: natural := 0
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Buffered RX clock, for measurement, if any
      rx_clock_o : out std_ulogic;

      mode_i : in rgmii_mode_t;
      rgmii_i : in  rgmii_io_group_t;

      flit_o : out rgmii_sdr_io_t;
      valid_o : out std_ulogic
      );
  end component;

end package rgmii;

package body rgmii is

  function to_logic(mode: rgmii_mode_t) return std_ulogic_vector
  is
    variable ret: std_ulogic_vector(1 downto 0) := "00";
  begin
    case mode is
      when RGMII_MODE_10   => ret := "00";
      when RGMII_MODE_100  => ret := "01";
      when RGMII_MODE_1000 => ret := "10";
    end case;

    return ret;
  end function;

  function to_string(mode: rgmii_mode_t) return string
  is
  begin
    case mode is
      when RGMII_MODE_10   => return "10M";
      when RGMII_MODE_100  => return "100M";
      when RGMII_MODE_1000 => return "1G";
    end case;
  end function;

  function to_mode(rxd21: std_ulogic_vector(1 downto 0)) return rgmii_mode_t
  is
  begin
    case rxd21 is
      when "00" => return RGMII_MODE_10;
      when "01" => return RGMII_MODE_100;
      when others => return RGMII_MODE_1000;
    end case;
  end function;

end package body;
