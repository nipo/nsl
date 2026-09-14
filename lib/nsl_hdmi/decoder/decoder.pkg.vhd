library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, work;

-- HDMI data island decoding: the packets an island carries, taken
-- out of the symbols a DVI decoder hands over.
package decoder is

  -- Puts data island packets back together.
  --
  -- What arrives is a symbol at a time, and a packet is spread over
  -- thirty two of them: the header goes out one bit a symbol on the
  -- sync channel, and the four subpackets two bits a symbol each on
  -- the other two.  An island holds one packet or several, back to
  -- back, and the decoder marks where it starts.
  --
  -- Both header and subpackets end in eight bits of BCH parity.  What
  -- is done here is to run the same remainder a source runs over the
  -- data bits and hold it against the parity that follows.  A packet
  -- whose parity did not hold is still handed over, marked: whether
  -- that is worth acting on is the reader's to decide, and an audio
  -- sample is not worth the same as an infoframe.
  --
  -- Nothing is corrected.  One bad bit is within what the code could
  -- repair, but a link this far out of shape is usually further out
  -- than that, and dropping the packet costs a sample.
  --
  -- There is no back pressure: a packet is offered for one cycle and
  -- the next one may follow thirty two cycles later.  A reader that
  -- cannot keep up needs a buffer of its own.
  component data_island_receiver is
    port(
      reset_n_i : in std_ulogic;
      pixel_clock_i : in std_ulogic;

      -- Straight off nsl_dvi.decoder.sink_stream_decoder
      period_i : in nsl_dvi.dvi.period_t;
      di_hdr_i : in std_ulogic_vector(1 downto 0);
      di_data_i : in std_ulogic_vector(7 downto 0);

      valid_o : out std_ulogic;
      packet_o : out work.hdmi.data_island_t;
      -- Whether the parity failed, on the header or on any subpacket
      error_o : out std_ulogic
      );
  end component;

end package decoder;
