library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc;

-- Committed network is a subset of framed network where a frame always ends
-- with a status word. LSB of status word tells whether frame is valid (active
-- high).
  
package committed is

  subtype committed_req is nsl_bnoc.framed.framed_req;
  subtype committed_ack is nsl_bnoc.framed.framed_ack;

  type committed_bus is record
    req: committed_req;
    ack: committed_ack;
  end record;
  
  type committed_req_array is array(natural range <>) of committed_req;
  type committed_ack_array is array(natural range <>) of committed_ack;
  type committed_bus_array is array(natural range <>) of committed_bus;

  -- Only pass through frames with a valid status byte.
  -- Buffers the frame before letting it through.
  component committed_filter is
    generic(
      max_size_c : natural := 2048
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      in_i   : in  committed_req;
      in_o   : out committed_ack;
      out_o  : out committed_req;
      out_i  : in committed_ack
      );
  end component;

  component committed_dispatch is
    generic(
      destination_count_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      enable_i : in std_ulogic := '1';
      destination_i  : in natural range 0 to destination_count_c - 1;
      
      in_i   : in committed_req;
      in_o   : out committed_ack;

      out_o   : out committed_req_array(0 to destination_count_c - 1);
      out_i   : in committed_ack_array(0 to destination_count_c - 1)
      );
  end component;

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

      out_o   : out committed_req;
      out_i   : in committed_ack
      );
  end component;

  component committed_fifo is
    generic(
      clock_count_c : natural range 1 to 2 := 1;
      depth_c : natural
      );
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic_vector(0 to clock_count_c-1);
      
      in_i   : in committed_req;
      in_o   : out committed_ack;

      out_o   : out committed_req;
      out_i   : in committed_ack
      );
  end component;

end package committed;
