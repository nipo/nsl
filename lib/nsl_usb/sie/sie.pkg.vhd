library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_usb, nsl_data, nsl_logic;
use nsl_usb.utmi.all;
use nsl_usb.usb.all;
use nsl_data.bytestream.byte;
use nsl_data.bytestream.byte_string;
use nsl_data.bytestream.null_byte_string;

package sie is

  -- SIE Packet layer
  -- This validates PIDs and asserts for CRC
  
  type packet_out is
  record
    -- There is guarantee that active is asserted at least one cycle before
    -- first valid = 1 cycle.
    active : std_ulogic;
    -- Must be asserted the first cycle after active gets deasserted
    commit   : std_ulogic;

    -- Whether data is meaningful on this cycle
    valid  : std_ulogic;
    data   : byte;
  end record;

  type packet_in_rsp is
  record
    -- When packet engine accepts a packet (by asserting ready), read
    -- the whole packet until last. Temporary drops in ready indicate
    -- backpressure, but do not cancel packet acceptance.
    ready  : std_ulogic;
  end record;

  type packet_in_cmd is
  record
    -- Once asserted, it must stay until last = 1
    valid   : std_ulogic;
    data    : byte;
    last    : std_ulogic;
  end record;

  -- SIE Transfer layer
  -- This is a Token / Data / Handshake triplet context

  type transfer_t is (
    TRANSFER_NONE,
    TRANSFER_SETUP,
    TRANSFER_OUT,
    TRANSFER_IN,
    TRANSFER_PING
    );

  function transfer_has_data_out(transfer: transfer_t) return boolean;
  function transfer_has_data_in(transfer: transfer_t) return boolean;
  
  type phase_t is (
    PHASE_NONE,
    PHASE_TOKEN,
    PHASE_DATA,
    PHASE_HANDSHAKE
    );

  type handshake_t is (
    HANDSHAKE_SILENT,
    HANDSHAKE_ACK,
    HANDSHAKE_NYET,
    HANDSHAKE_NAK,
    HANDSHAKE_STALL
    );

  -- transfer_cmd and transfer_rsp contain all information about a
  -- transfer.  A transfer usually has 3 phases: TOKEN, DATA,
  -- HANDSHAKE.  Main command/response design here is: information
  -- flow through the interface only when cmd.phase = rsp.phase.
  --
  -- All transfer is driven by commander.
  -- - It may cancel transfer any time and go back to NONE.
  -- - It controls 'nxt' signal, which guards data exchange, in both
  --   directions.
  -- - Responder must be able to accept packet at any time (and handle
  --   overflows nicely), it must be able to feed IN transfers without
  --   pause.
  --
  -- Commander and Responder state machines should walk accross the three
  -- phases coherently.
  --
  -- - For OUT/SETUP/PING transfers, responder should be in Data phase as soon as
  --   possible after TOKEN, as there is no back-pressure from responder.
  --
  --    Cmd state machine:  None ---> Token ---> Data -+-> Handshake
  --                                    |              |
  --                                    \--------------/
  --                                      Ping or ZLP transfers
  --
  --    Rsp state machine:  None ---> Data -+-> Handshake
  --                         |              |
  --                         \--------------/
  --                         Responder can only
  --                         skip data if Cmd is
  --                         already in handshake.
  --
  --   Timeline
  --
  --   Case #1: Data exchange
  --
  --       Command                              Response
  --
  --        None                                 None
  --        Token     --------________
  --                                  --–––––>
  --   +--  Data                                 Data     --+
  --   |                                                    |
  --   |            Data flows, guarded by Nxt              |
  --   |                                                    |
  --   +--                                                --+
  --        Handshake --------________
  --        (Dont care)               --–––––>
  --                          ________--------   Handshake (ACK)
  --                  <-------
  --        None      --------________
  --                                  --–––––>
  --                                             None
  --
  --   Case #2: ZLP / Ping
  --
  --       Command                              Response
  --
  --        None                                 None
  --        Token     --------________
  --                                  --–––––>
  --        Handshake --------________           Data
  --        (Dont care)               --–––––>
  --                          ________--------   Handshake (ACK)
  --                  <-------
  --        None      --------________
  --                                  --–––––>
  --                                             None
  --
  --
  -- - For IN transfers, responder may take a few cycles to move to
  --   Data phase.  Responder may skip Data phase and go to Handshare
  --   directly. This implies either a ZLP (when Handshare = ACK) or
  --   an error PID in lieu of DATA0/1.
  --
  --    Cmd state machine:  None ---> Token ---> Data -+-> Handshake
  --                         |                         |
  --                         \-------------------------/
  --                             Commander can only
  --                             skip data if Rsp is
  --                             already in handshake.
  --
  --    Rsp state machine:  None ---> Token ---> Data -+-> Handshake
  --                                    |              |
  --                                    \--------------/
  --                                  ZLP or Error transfer.
  --
  --   Timeline
  --
  --   Case #1: Data exchange
  --
  --       Command                              Response
  --
  --        None                                 None
  --        Token     --------________
  --                                  --–––––>
  --                          ________--------   Data
  --                  <-------
  --   +--  Data                                          --+
  --   |                                                    |
  --   |            Data flows, guarded by Nxt              |
  --   |                                                    |
  --   +--                                                --+
  --                          ________--------   Handshake (ACK/NYET)
  --                  <-------
  --        Handshake --------________
  --        (ACK)                     --–––––>
  --                          ________--------   None
  --                  <-------
  --        None
  --
  --   Case #2: ZLP or error
  --
  --       Command                              Response
  --
  --        None                                 None
  --        Token     --------________
  --                                  --–––––>
  --                          ________--------   Handshake (ACK/NYET/NAK/STALL)
  --                  <-------
  --        Handshake --------________
  --                                  --–––––>
  --                          ________--------   None
  --                  <-------
  --        None
  --
  
  type transfer_cmd is
  record
    ep_no    : endpoint_no_t;
    transfer : transfer_t;
    phase    : phase_t;

    -- Indicates SIE in is High-Speed mode. Constant '0' if HS is not
    -- supported.
    hs       : std_ulogic;

    -- Control request asks for setting/clearing halt on the endpoint, only
    -- meaningful for endpoint connections
    halt     : std_ulogic;
    clear    : std_ulogic;

    -- Data exchange guard: 'valid' for OUT/SETUP, 'ready' for IN
    -- Cycle synchronous
    nxt      : std_ulogic;

    -- Valid when phase = DATA and transfer = SETUP/OUT, guarded by nxt
    toggle   : std_ulogic;
    data     : byte;

    -- Valid when phase = HANDSHAKE or transfer = IN
    handshake : handshake_t;
  end record;

  type transfer_cmd_vector is array(integer range <>) of transfer_cmd;
  
  constant TRANSFER_CMD_IDLE : transfer_cmd := (
    ep_no => (others => '-'),
    transfer => TRANSFER_NONE,
    phase => PHASE_NONE,

    hs => '0',
    halt => '0',
    clear => '0',

    nxt => '-',
    toggle => '-',
    data => (others => '-'),
    handshake => HANDSHAKE_SILENT
    );

  type transfer_rsp is
  record
    -- For IN transfers, if phase never reaches DATA and goes to
    -- handshake straight, either a ZLP (ACK/NYET) or an error
    -- condition (STALL/NAK) is sent.
    phase    : phase_t;

    -- Valid when phase = DATA and transfer = IN
    toggle   : std_ulogic;
    data     : byte;
    last     : std_ulogic;

    -- Valid when phase = HANDSHAKE and transfer = OUT/SETUP/PING
    handshake : handshake_t;

    -- Only meaningful for endpoints, tells to control whether
    -- endpoint is halted.
    halted : std_ulogic;
  end record;

  type transfer_rsp_vector is array(integer range <>) of transfer_rsp;

  constant TRANSFER_RSP_IDLE : transfer_rsp := (
    phase => PHASE_NONE,
    toggle => '-',
    data => (others => '-'),
    last => '-',
    handshake => HANDSHAKE_SILENT,
    halted => '0'
    );
  constant TRANSFER_RSP_ERROR : transfer_rsp := (
    phase => PHASE_HANDSHAKE,
    toggle => '-',
    data => (others => '-'),
    last => '-',
    handshake => HANDSHAKE_STALL,
    halted => '0'
    );

  -- SIE Descriptor lookup

  -- EP0 queries the descriptor block in three phases:
  --
  -- 1. EP0 triggers lookup of a descriptor by /type/ and
  --    /index/. Next cycle after /lookup/ is asserted on command
  --    channel, /lookup_done/ deasserts until descriptor is found (or
  --    not). Availability of descriptor is responded through
  --    /exists/. Selected descriptor is internally registered in
  --    descriptor block.
  --
  -- 2. EP0 needs to read the previously-selected descriptor from a
  --    given /offset/ (Data retransmission requires to seek back
  --    sometimes).  /seek/ is asserted on command interface with a
  --    base offset.  No more than 2 cycles after, /data/ exposes the
  --    byte of descriptor data at said offset.
  --
  -- 3. EP0 streams the descriptor. Any cycle where /read/ is asserted
  --    on command interface, current data byte is assumed to be
  --    consumed and next data byte will be available on response
  --    interface on next cycle.  When descriptor block presents the
  --    last byte of descriptor, it asserts /last/ during the same
  --    cycle.
  
  type descriptor_cmd is
  record
    hs     : std_ulogic;

    lookup : std_ulogic;
    dtype  : descriptor_type_t;
    index  : unsigned(5 downto 0);

    seek   : std_ulogic;
    offset : unsigned(7 downto 0);

    read    : std_ulogic;
  end record;

  type descriptor_rsp is
  record
    exists, lookup_done : std_ulogic;

    data      : byte;
    last      : std_ulogic;
  end record;

  -- Serializer for sie_descriptor raw entries
  function sie_descriptor_entry(dtype  : descriptor_type_t;
                                index  : integer;
                                data   : byte_string;
                                speed_dependant : boolean := false;
                                hs_only : boolean := false)
    return byte_string;

  component sie_descriptor is
    generic (
      hs_supported_c : boolean := false;
      device_descriptor : byte_string;
      device_qualifier : byte_string := null_byte_string;
      -- Configuration #1 descriptor, for FS and HS. Endpoint MPS
      -- changes. See example in func/serial_port.vhd to see how to use a
      -- function to avoid repeating too much.
      fs_config_1 : byte_string;
      hs_config_1 : byte_string := null_byte_string;
      -- String descriptors. ASCII string is converted to UTF-16
      -- internally.
      string_1 : string := "";
      string_2 : string := "";
      string_3 : string := "";
      string_4 : string := "";
      string_5 : string := "";
      string_6 : string := "";
      string_7 : string := "";
      string_8 : string := "";
      string_9 : string := "";
      -- User-defined additional descriptors. Must be serialized
      -- with help of sie_descriptor_entry.
      raw_0 : byte_string := null_byte_string;
      raw_1 : byte_string := null_byte_string;
      raw_2 : byte_string := null_byte_string;
      raw_3 : byte_string := null_byte_string;
      raw_4 : byte_string := null_byte_string;
      raw_5 : byte_string := null_byte_string;
      raw_6 : byte_string := null_byte_string;
      raw_7 : byte_string := null_byte_string
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- String 10 can be non-constant. A string of any size may be connected
      -- here. It will be converted to UTF-16 when descriptor is read.
      -- This is mostly useful for a serial number.
      string_10_i : in string := "";

      cmd_i : in descriptor_cmd;
      rsp_o : out descriptor_rsp
      );
  end component sie_descriptor;

  component sie_management is
    generic (
      hs_supported_c : boolean := false;
      phy_clock_rate_c : integer := 60000000
      );
    port (
      reset_n_i        : in  std_ulogic;

      phy_system_o : out utmi_system_sie2phy;
      phy_system_i : in utmi_system_phy2sie;

      app_reset_n_o : out std_ulogic;
      hs_o          : out std_ulogic;
      suspend_o     : out std_ulogic;
      chirp_tx_o    : out std_ulogic
      );
  end component sie_management;

  component sie_packet is
    port (
      clock_i   : in std_ulogic;
      reset_n_i : in std_ulogic;

      phy_data_o : out utmi_data8_sie2phy;
      phy_data_i : in  utmi_data8_phy2sie;

      chirp_tx_i : in std_ulogic;

      out_o  : out packet_out;
      in_i   : in packet_in_cmd;
      in_o   : out packet_in_rsp
      );
  end component sie_packet;

  component sie_transfer is
    generic (
      hs_supported_c : boolean := false;
      phy_clock_rate_c : integer := 60000000
      );
    port (
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      frame_number_o : out frame_no_t;
      frame_o        : out std_ulogic;

      hs_i        : in  std_ulogic;
      dev_addr_i  : in  device_address_t;

      packet_out_i  : in  packet_out;
      packet_in_o   : out packet_in_cmd;
      packet_in_i   : in  packet_in_rsp;

      transfer_o : out transfer_cmd;
      transfer_i : in  transfer_rsp
      );
  end component;
      
  component sie_transfer_router is
    generic (
      in_ep_count_c, out_ep_count_c : endpoint_idx_t
      );
    port (
      clock_i     : in  std_ulogic;
      reset_n_i   : in  std_ulogic;

      transfer_i : in  transfer_cmd;
      transfer_o : out transfer_rsp;

      transfer_ep0_o : out transfer_cmd;
      transfer_ep0_i : in transfer_rsp;

      halted_in_o : out std_ulogic_vector(1 to in_ep_count_c);
      halt_in_i : in std_ulogic_vector(1 to in_ep_count_c);
      clear_in_i : in std_ulogic_vector(1 to in_ep_count_c);

      halted_out_o : out std_ulogic_vector(1 to out_ep_count_c);
      halt_out_i : in std_ulogic_vector(1 to out_ep_count_c);
      clear_out_i : in std_ulogic_vector(1 to out_ep_count_c);

      transfer_in_o : out transfer_cmd_vector(1 to in_ep_count_c);
      transfer_in_i : in transfer_rsp_vector(1 to in_ep_count_c);
      transfer_out_o : out transfer_cmd_vector(1 to out_ep_count_c);
      transfer_out_i : in transfer_rsp_vector(1 to out_ep_count_c)
      );
  end component sie_transfer_router;

  component sie_ep0 is
    generic (
      in_ep_count_c, out_ep_count_c : endpoint_idx_t;
      self_powered_c       : boolean
      );
    port (
      clock_i          : in  std_ulogic;
      reset_n_i        : in  std_ulogic;

      dev_addr_o   : out device_address_t;
      configured_o : out std_ulogic;

      transfer_i : in  transfer_cmd;
      transfer_o : out transfer_rsp;

      halted_in_i : in std_ulogic_vector(1 to in_ep_count_c);
      halt_in_o : out std_ulogic_vector(1 to in_ep_count_c);
      clear_in_o : out std_ulogic_vector(1 to in_ep_count_c);

      halted_out_i : in std_ulogic_vector(1 to out_ep_count_c);
      halt_out_o : out std_ulogic_vector(1 to out_ep_count_c);
      clear_out_o : out std_ulogic_vector(1 to out_ep_count_c);

      descriptor_o : out descriptor_cmd;
      descriptor_i : in  descriptor_rsp
      );
  end component;

end package;

package body sie is

  use nsl_logic.bool.all;

  function transfer_has_data_out(transfer: transfer_t) return boolean
  is
  begin
    return transfer = TRANSFER_OUT
      or transfer = TRANSFER_SETUP;
  end function;

  function transfer_has_data_in(transfer: transfer_t) return boolean
  is
  begin
    return transfer = TRANSFER_IN;
  end function;

  function sie_descriptor_entry(dtype  : descriptor_type_t;
                                index  : integer;
                                data   : byte_string;
                                speed_dependant : boolean := false;
                                hs_only : boolean := false) return byte_string
  is
    variable ret : byte_string(0 to data'length+3-1);
  begin
    if data'length = 0 then
      return null_byte_string;
    end if;

    ret(0) := byte(to_unsigned(data'length, 8));
    ret(1) := byte(dtype);
    ret(2) := byte(to_unsigned(index, 8));
    ret(2)(7) := to_logic(speed_dependant);
    ret(2)(6) := to_logic(hs_only);
    ret(3 to ret'right) := data;

    return ret;
  end function;

end package body;
