library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_bnoc, nsl_data;

package memap_mapper is

  use nsl_data.bytestream.byte;
  
  -- Run cycles between two accesses. Yields no response. This should not be
  -- used as last command byte.
  constant MEMAP_CMD_INTERVAL : byte := "00------";

  -- 6 LSB are the count of 32-bit words to write - 1
  -- Follows 4*(n+1) bytes data, LSB first.
  -- Response is a status byte.
  constant MEMAP_CMD_WRITE : byte := "10------";

  -- 6 LSB are the count of 32-bit words to read - 1
  -- No subsequent command byte.
  -- Response is 4*(n+1) bytes data, LSB first, ends with a status byte.
  constant MEMAP_CMD_READ  : byte := "11------";

  -- Perform one 8-bit read access, 4 bytes + status are returned (we
  -- do not know the actual alignment of data in returned word).
  constant MEMAP_CMD_READ8 : byte := "01000000";

  -- Perform one 16-bit read access, 4 bytes + status are returned (we
  -- do not know the actual alignment of data in returned word).
  constant MEMAP_CMD_READ16 : byte := "01000001";

  -- Perform one 8-bit write access, 4 bytes are to be passed (we do
  -- not know the actual alignment of data in word). Yields one status response
  -- byte.
  constant MEMAP_CMD_WRITE8 : byte := "01000010";

  -- Perform one 8-bit write access, 4 bytes are to be passed (we do
  -- not know the actual alignment of data in word). Yields one status response
  -- byte.
  constant MEMAP_CMD_WRITE16 : byte := "01000011";

  -- Four address bytes follows, LSB first, no response is generated. This is
  -- invalid to use last in the command stream.
  constant MEMAP_CMD_ADDRESS : byte := "01000101";
  -- This sets the 24 LSBs of CSW for subsequent accesses. Three bytes
  -- follows, LSB first, from bit 8 to 31 (other bits are generated
  -- internally). No response is generated. This is invalid to use
  -- last in the command stream.
  constant MEMAP_CMD_CSW : byte := "01000110";

  -- Command / response passthrough until LAST
  constant MEMAP_CMD_RAW_CMD_PT : byte := "01001000";
  constant MEMAP_CMD_RAW_RSP_PT : byte := "01001001";

  -- Echoes a NOP in response stream
  constant MEMAP_CMD_NOP        : byte := "01001111";
  
  -- 4 LSBs are the count of subsequent bytes - 1.  Follows N+1 bytes
  -- of command to pass on to the backend side. No response is
  -- generated. This is invalid to use last in the command stream.  If
  -- you need to pass RAW_CMD as last command in the command stream,
  -- issue a one-short RAW_RSP before, and use a 1-sized RAW_RSP after
  -- this one with last set.
  constant MEMAP_CMD_RAW_CMD : byte := "0110----";

  -- 4 LSBs are the count of response bytes to pass - 1.  N+1 bytes of
  -- response stream are passed in.
  constant MEMAP_CMD_RAW_RSP : byte := "0111----";
 
  -- Status bytes for memory operations
  -- Only MSB is significant, but other bits will not be used.
  constant MEMAP_RSP_OK  : byte := "0-------";
  -- On error, gives the offset of the first word that generated an
  -- error. For read, all received words from this index onwards are
  -- meaningless but are sent anyway (and are sent before this byte anyway).
  constant MEMAP_RSP_ERR : byte := "1-------";


  -- This component maps a MemAP to a framed-based command fifo.
  -- Every transaction generated tries to be stateless (DP, AP and SoC
  -- should be inited anyway).
  --
  -- If needs be to performed DP selection (multidrop), AP selection
  -- (DP.SELECT) or other pre-initialization, this should be performed through
  -- raw command/responses.
  --
  -- Address setting yields a TAR register write. If no address is
  -- set, memory access is still performed. This is mostly useful for
  -- auto-incremented streams.
  --
  -- Transaction sequence for every memory access is:
  -- - AP Abort (all)
  -- - MemAP Write CSW (auto-increment, N-wide access),
  -- - If read:
  --   - Do a dummy access to DRW for first word, followed by N run cycles
  --   - N-1 accesses to DRW for subsequent words, followed by N run cycles
  --   - Do an access to DP RDBUFF, followed by N run cycles
  -- - If write:
  --   - Do N accesses to DRW, followed by N run cycles
  --
  -- Note: This component assumes the SWD, DP and Mem-AP got initialized
  -- correctly by some other code.
  --
  -- When using raw command and responses, you should send raw
  -- response command before the raw command so that response FSM is
  -- in the forwarding state before response bytes begin to stream in
  -- in a way there will be no FIFO needed between this component and
  -- nsl_coresight.Transactor.dp_framed_transactor.
  component framed_memap_transactor is
    port (
      reset_n_i : in std_ulogic;
      clock_i : in std_ulogic;

      cmd_i : in nsl_bnoc.framed.framed_req;
      cmd_o : out nsl_bnoc.framed.framed_ack;
      rsp_o : out nsl_bnoc.framed.framed_req;
      rsp_i : in nsl_bnoc.framed.framed_ack;

      dp_cmd_o : out nsl_bnoc.framed.framed_req;
      dp_cmd_i : in nsl_bnoc.framed.framed_ack;
      dp_rsp_i : in nsl_bnoc.framed.framed_req;
      dp_rsp_o : out nsl_bnoc.framed.framed_ack
      );
    --@-- grouped name:transactor, members:dp_cmd;dp_rsp
    --@-- grouped name:command, members:cmd;rsp
  end component;
  
end package memap_mapper;
