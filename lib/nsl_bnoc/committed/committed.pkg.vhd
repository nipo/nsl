library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_data;
use nsl_data.bytestream.all;

-- Committed network is a subset of framed network where a frame
-- always ends with an additional status word. LSB of status word
-- tells whether frame is valid (active high).
  
package committed is

  subtype committed_req_t is nsl_bnoc.framed.framed_req;
  subtype committed_ack_t is nsl_bnoc.framed.framed_ack;
  subtype committed_req is committed_req_t;
  subtype committed_ack is committed_ack_t;

  type committed_bus_t is record
    req: committed_req;
    ack: committed_ack;
  end record;
  subtype committed_bus is committed_bus_t;

  type committed_req_array is array(natural range <>) of committed_req_t;
  type committed_ack_array is array(natural range <>) of committed_ack_t;
  type committed_bus_array is array(natural range <>) of committed_bus_t;
  subtype committed_req_vector is committed_req_array;
  subtype committed_ack_vector is committed_ack_array;
  subtype committed_bus_vector is committed_bus_array;

  constant committed_req_idle_c : committed_req_t := nsl_bnoc.framed.framed_req_idle_c;
  constant committed_ack_idle_c : committed_ack_t := nsl_bnoc.framed.framed_ack_idle_c;
  constant committed_ack_blackhole_c : committed_ack_t := nsl_bnoc.framed.framed_ack_blackhole_c;

  function committed_flit(data: nsl_bnoc.framed.framed_data_t;
                          last: boolean := false;
                          valid: boolean := true) return committed_req_t;

  function committed_accept(ready: boolean := true) return committed_ack_t;

  function committed_commit(valid: boolean := true) return committed_req_t;
  
  -- Only pass through frames with a valid status byte.
  -- Buffers the frame before letting it through.
  component committed_filter is
    generic(
      max_size_c : natural := 2048
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      in_i   : in  committed_req_t;
      in_o   : out committed_ack_t;
      out_o  : out committed_req_t;
      out_i  : in committed_ack_t
      );
  end component;

  -- Sort of one-to-many router where route is taken from a port.
  component committed_dispatch is
    generic(
      destination_count_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      enable_i : in std_ulogic := '1';
      destination_i  : in natural range 0 to destination_count_c - 1;
      
      in_i   : in committed_req_t;
      in_o   : out committed_ack_t;

      out_o   : out committed_req_array(0 to destination_count_c - 1);
      out_i   : in committed_ack_array(0 to destination_count_c - 1)
      );
  end component;

  -- Many to one router.
  component committed_funnel is
    generic(
      source_count_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      enable_i : in std_ulogic := '1';
      selected_o  : out natural range 0 to source_count_c - 1;
      
      in_i   : in committed_req_array(0 to source_count_c - 1);
      in_o   : out committed_ack_array(0 to source_count_c - 1);

      out_o   : out committed_req_t;
      out_i   : in committed_ack_t
      );
  end component;

  -- Simple basic fifo. Equivalent to a framed fifo.
  component committed_fifo is
    generic(
      clock_count_c : natural range 1 to 2 := 1;
      depth_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic_vector(0 to clock_count_c-1);
      
      in_i   : in committed_req_t;
      in_o   : out committed_ack_t;

      out_o   : out committed_req_t;
      out_i   : in committed_ack_t
      );
  end component;

  -- Measures the actual byte length of committed frame (validity flit
  -- not included).
  --
  -- For every frame that comes in the component, exactly one word is
  -- outputted on the size fifo, and exactly one frame is outputted on
  -- the output port.
  --
  -- Synchronously to the size output, a good output tells whether the
  -- frame is good for consumption. If not, some words will still be
  -- forwarded to the output port.  Size may not reflect the actual
  -- count of flits on the output port when frame is bad.
  --
  -- If a frame bigger than 2**max_size_l2_c gets to the input, it is
  -- automatically considered bad and will be forwarded truncated
  -- (with status byte marking the cancellation).
  component committed_sizer is
    generic(
      clock_count_c : natural range 1 to 2 := 1;
      -- Reload value of counter. Set to 1 to count validity bit
      offset_c : integer := 0;
      txn_count_c : natural;
      -- Should fit size + offset_c
      max_size_l2_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic_vector(0 to clock_count_c-1);
      
      in_i   : in committed_req_t;
      in_o   : out committed_ack_t;

      size_o : out unsigned(max_size_l2_c-1 downto 0);
      good_o : out std_ulogic;
      size_valid_o : out std_ulogic;
      size_ready_i : in std_ulogic;

      out_o   : out committed_req_t;
      out_i   : in committed_ack_t
      );
  end component;

  -- A small fifo that allows the frame to get out only when fillness reaches a
  -- given threshold. Handle frames shorter that the threshold nicely.
  component committed_prefill_buffer is
    generic(
      prefill_count_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;
      
      in_i   : in  committed_req_t;
      in_o   : out committed_ack_t;

      out_o  : out committed_req_t;
      out_i  : in committed_ack_t
      );
  end component;

  -- Adds a fixed-length header taken from ports before a message.
  -- Header is captured on demand from the instantiator.
  component committed_header_inserter is
    generic(
      header_length_c : positive
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      header_i : in byte_string(0 to header_length_c-1);
      -- Tell the module when to capture header value.  This may
      -- happen any time before frame_i.valid gets asserted.  If
      -- capture is asserted multiple times (or continuously) before
      -- frame_i.valid gets asserted, the last value is used.  If no
      -- capture happens for two consecutive frames, what is outputted
      -- to the frames after the first one is undefined.
      capture_i : in std_ulogic;
      
      in_i   : in  committed_req_t;
      in_o   : out committed_ack_t;

      out_o  : out committed_req_t;
      out_i  : in committed_ack_t
      );
  end component;

  -- Strips a header from a committed network frame, and exposes it to
  -- interface port.
  component committed_header_extractor is
    generic(
      header_length_c : positive
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      header_o : out byte_string(0 to header_length_c-1);
      valid_o : out std_ulogic;
      
      in_i   : in  committed_req_t;
      in_o   : out committed_ack_t;

      out_o  : out committed_req_t;
      out_i  : in committed_ack_t
      );
  end component;

  component committed_fifo_slice is
    port(
      reset_n_i  : in  std_ulogic;
      clock_i    : in  std_ulogic;

      in_i   : in committed_req_t;
      in_o   : out committed_ack_t;

      out_o   : out committed_req_t;
      out_i   : in committed_ack_t
      );
  end component;

  -- A module asserting valid_o exactly during one cycle at end of
  -- every frame.  Gives out statistic about past frame when valid_o
  -- is asserted.
  --
  -- Counter saturation is not handled on intraframe counters,
  -- optional on interframe counter. All counters roll over silently.
  --
  -- Every time valid_o is asserted, there should be exactly
  -- interframe_count_o + flit_count_o + pause_count_o +
  -- backpressure_count_o + 1 cycles passed since last assertion,
  -- unless some counter rolled over.
  component committed_statistics is
    generic(
      interframe_saturate_c : boolean := false
      );
    port(
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      req_i : in committed_req_t;
      ack_i : in committed_ack_t;

      -- Whether frame is valid
      frame_ok_o : out std_ulogic;
      -- Count of cycles between previous frame and first cycle of
      -- current one
      interframe_count_o : out unsigned;
      -- Count of data flits in the frame (status excluded)
      flit_count_o : out unsigned;
      -- Count of cycles when no data was exchanged because of request
      -- valid not asserted
      pause_count_o : out unsigned;
      -- Count of cycles when no data was exchanged because of
      -- acknowledge ready not asserted
      backpressure_count_o : out unsigned;

      -- Strobe signal for all statistics
      valid_o : out std_ulogic
      );
  end component;

end package committed;

package body committed is

  function committed_flit(data: nsl_bnoc.framed.framed_data_t;
                          last: boolean := false;
                          valid: boolean := true) return committed_req_t
  is
  begin
    if not valid then
      return (valid => '0', data => "--------", last => '-');
    elsif last then
      return (valid => '1', data => data, last => '1');
    else
      return (valid => '1', data => data, last => '0');
    end if;
  end function;

  function committed_commit(valid: boolean := true) return committed_req_t
  is
  begin
    if valid then
      return committed_flit(data => x"01", last => true, valid => true);
    else
      return committed_flit(data => x"00", last => true, valid => true);
    end if;
  end function;

  function committed_accept(ready: boolean := true) return committed_ack_t
  is
  begin
    if ready then
      return (ready => '1');
    else
      return (ready => '0');
    end if;
  end function;
      
end package body;
