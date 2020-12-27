library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package framed is

  subtype framed_data_t is std_ulogic_vector(7 downto 0);
  
  type framed_req is record
    data : framed_data_t;
    last : std_ulogic;
    valid  : std_ulogic;
  end record;

  type framed_ack is record
    ready  : std_ulogic;
  end record;
  
  type framed_bus is record
    req: framed_req;
    ack: framed_ack;
  end record;
  
  type framed_req_array is array(natural range <>) of framed_req;
  type framed_ack_array is array(natural range <>) of framed_ack;
  type framed_bus_array is array(natural range <>) of framed_bus;

  component framed_fifo is
    generic(
      depth      : natural;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_val   : in framed_req;
      p_in_ack   : out framed_ack;

      p_out_val   : out framed_req;
      p_out_ack   : in framed_ack
      );
  end component;

  component framed_fifo_atomic is
    generic(
      depth : natural;
      txn_depth : natural := 4;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_val   : in framed_req;
      p_in_ack   : out framed_ack;

      p_out_val   : out framed_req;
      p_out_ack   : in framed_ack
      );
  end component;

  component framed_arbitrer is
    generic(
      source_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_val   : in framed_req_array(0 to source_count - 1);
      p_cmd_ack   : out framed_ack_array(0 to source_count - 1);
      p_rsp_val   : out framed_req_array(0 to source_count - 1);
      p_rsp_ack   : in framed_ack_array(0 to source_count - 1);

      p_target_cmd_val   : out framed_req;
      p_target_cmd_ack   : in framed_ack;
      p_target_rsp_val   : in framed_req;
      p_target_rsp_ack   : out framed_ack
      );
  end component;

end package framed;
