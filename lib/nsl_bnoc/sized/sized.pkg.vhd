library ieee;
use ieee.std_logic_1164.all;

library nsl_bnoc;

-- Bnoc sized abstraction. A sized network conveys frames (i.e.  data
-- flits with a boundary) through a pipe (a continuous stream
-- interface).  This is done by adding a header between every frame
-- data with following frame size.
--
-- Frame size is encoded as 16-bit value, little endian, off by one
-- (size field of 0x0000 denotes a 1-byte frame).
package sized is

  alias sized_data is nsl_bnoc.pipe.pipe_data_t;
  alias sized_req is nsl_bnoc.pipe.pipe_req_t;
  alias sized_ack is nsl_bnoc.pipe.pipe_ack_t;

  type sized_bus is record
    req: sized_req;
    ack: sized_ack;
  end record;

  type sized_req_array is array(natural range <>) of sized_req;
  type sized_ack_array is array(natural range <>) of sized_ack;

  component sized_fifo
    generic(
      depth     : integer;
      clk_count : natural range 1 to 2
      );
    port(
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic_vector(0 to clk_count-1);

      p_in_val  : in  sized_req;
      p_in_ack  : out sized_ack;

      p_out_val : out sized_req;
      p_out_ack : in  sized_ack
      );
  end component;

  component sized_from_framed
    generic(
      max_txn_length  : natural := 2048
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val  : in nsl_bnoc.framed.framed_req;
      p_in_ack  : out nsl_bnoc.framed.framed_ack;

      p_out_val : out sized_req;
      p_out_ack : in  sized_ack
      );
  end component;

  component sized_to_framed
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_inval : out std_ulogic;
      
      p_out_val  : out nsl_bnoc.framed.framed_req;
      p_out_ack  : in  nsl_bnoc.framed.framed_ack;

      p_in_val : in  sized_req;
      p_in_ack : out sized_ack
      );
  end component;

end package sized;
