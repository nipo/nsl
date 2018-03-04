library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.framed.all;

package sized is

  subtype sized_data is nsl.framed.framed_data_t;

  type sized_req is record
    data : sized_data;
    valid  : std_ulogic;
  end record;

  type sized_ack is record
    ready : std_ulogic;
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

      p_in_val  : in framed_req;
      p_in_ack  : out framed_ack;

      p_out_val : out sized_req;
      p_out_ack : in  sized_ack
      );
  end component;

  component sized_to_framed
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_inval : out std_ulogic;
      
      p_out_val  : out framed_req;
      p_out_ack  : in  framed_ack;

      p_in_val : in  sized_req;
      p_in_ack : out sized_ack
      );
  end component;

end package sized;
