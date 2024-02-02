library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_bnoc, nsl_data;

-- Here are defined accessors to Segger-defined Real-Time Terminal
-- through various methods.  RTT is a set of memory-mapped
-- ring-buffers that can be accessed simultaneously from MCU's CPU and
-- debugger.
-- Typical usage is to send console logs there, or emulate an UART.
--
-- We reuse the Coresight DP/Mem-AP transactors to transact those ring
-- buffers to pipe interfaces.
package rtt is
  
  -- Must be initialized to "SEGGER RTT" to be valid
  constant rtt_control_id_offset_c : integer := 0;
  constant rtt_control_signature_c : nsl_data.bytestream.byte_string
    := nsl_data.bytestream.from_hex("5345474745522052545400----------");
  -- Count of channels from MCU to debugger
  constant rtt_control_up_count_offset_c : integer := 16;
  -- Count of channels from debugger to MCU
  constant rtt_control_down_count_offset_c : integer := 20;
  -- Follows an array of channel structures, each is 6 32-bit fields
  -- Up channels come first, then down buffers
  constant rtt_control_channel0_offset_c : integer := 24;

  -- Channel structures
  constant rtt_channel_size_c : integer := 24;
  -- All fields are 32 bits, little-endian
  constant rtt_channel_name_offset_c : integer := 0;
  constant rtt_channel_buffer_offset_c : integer := 4;
  constant rtt_channel_buffer_length_offset_c : integer := 8;
  constant rtt_channel_wptr_offset_c : integer := 12;
  constant rtt_channel_rptr_offset_c : integer := 16;
  constant rtt_channel_flags_offset_c : integer := 20;

  -- Flags for each channel
  constant rtt_channel_flag_skip_c : std_ulogic_vector(31 downto 0) := "------------------------------00";
  constant rtt_channel_flag_trim_c : std_ulogic_vector(31 downto 0) := "------------------------------01";
  constant rtt_channel_flag_block_c : std_ulogic_vector(31 downto 0) := "------------------------------10";
  
  component rtt_down_pipe is
    port (
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      enable_i: in std_ulogic;
      busy_o: out std_ulogic;
      error_o: out std_ulogic;

      ap_i: in unsigned(7 downto 0) := x"00";
      control_address_i: in unsigned(31 downto 2);
      channel_address_i: in unsigned(31 downto 2);

      data_i : in nsl_bnoc.pipe.pipe_req_t;
      data_o : out nsl_bnoc.pipe.pipe_ack_t;

      memap_cmd_o : out nsl_bnoc.framed.framed_req_t;
      memap_cmd_i : in nsl_bnoc.framed.framed_ack_t;
      memap_rsp_i : in nsl_bnoc.framed.framed_req_t;
      memap_rsp_o : out nsl_bnoc.framed.framed_ack_t
      );
  end component;

  -- Maps a RTT channel from memory to pipe.
  component rtt_up_pipe is
    generic (
      offset_width_c : integer range 9 to 20 := 13;
      control_check_every_c : integer := 8
      );
    port (
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      enable_i: in std_ulogic;
      busy_o: out std_ulogic;
      error_o: out std_ulogic;

      interval_i: in unsigned;
      control_address_i: in unsigned(31 downto 2);
      channel_address_i: in unsigned(31 downto 2);

      data_o : out nsl_bnoc.pipe.pipe_req_t;
      data_i : in nsl_bnoc.pipe.pipe_ack_t;

      memap_cmd_o : out nsl_bnoc.framed.framed_req_t;
      memap_cmd_i : in nsl_bnoc.framed.framed_ack_t;
      memap_rsp_i : in nsl_bnoc.framed.framed_req_t;
      memap_rsp_o : out nsl_bnoc.framed.framed_ack_t
      );
  end component;
  
end package rtt;
