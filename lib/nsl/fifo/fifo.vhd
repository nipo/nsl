library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package fifo is

  subtype framed_data_t is std_ulogic_vector(7 downto 0);
  
  type fifo_framed_cmd is record
    data : framed_data_t;
    more : std_ulogic;
    val  : std_ulogic;
  end record;

  type fifo_framed_rsp is record
    ack  : std_ulogic;
  end record;

  type fifo_framed_cmd_array is array(natural range <>) of fifo_framed_cmd;
  type fifo_framed_rsp_array is array(natural range <>) of fifo_framed_rsp;

  subtype component_id is natural range 0 to 15;
  type fifo_framed_routing_table is array(component_id) of natural;

  component fifo_framed_router is
    generic(
      in_port_count : natural;
      out_port_count : natural;
      routing_table : fifo_framed_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out fifo_framed_rsp_array(in_port_count-1 downto 0);

      p_out_val   : out fifo_framed_cmd_array(out_port_count-1 downto 0);
      p_out_ack   : in fifo_framed_rsp_array(out_port_count-1 downto 0)
      );
  end component;

  component fifo_framed_router_inbound is
    generic(
      out_port_count : natural;
      routing_table : fifo_framed_routing_table
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd;
      p_in_ack   : out fifo_framed_rsp;

      p_out_val  : out fifo_framed_cmd;
      p_out_ack  : in fifo_framed_rsp_array(out_port_count-1 downto 0);

      p_request  : out std_ulogic_vector(out_port_count-1 downto 0);
      p_selected : in  std_ulogic_vector(out_port_count-1 downto 0)
      );
  end component;

  component fifo_framed_router_outbound is
    generic(
      in_port_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd_array(in_port_count-1 downto 0);
      p_in_ack   : out fifo_framed_rsp;

      p_out_val  : out fifo_framed_cmd;
      p_out_ack  : in fifo_framed_rsp;

      p_request  : in  std_ulogic_vector(in_port_count-1 downto 0);
      p_selected : out std_ulogic_vector(in_port_count-1 downto 0)
      );
  end component;
  
  component fifo_sync
    generic(
      data_width : integer;
      depth      : integer
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic;

      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_write  : in  std_ulogic;
      p_in_full_n : out std_ulogic
      );
  end component;

  component fifo_async
    generic(
      data_width : integer;
      depth      : integer
      );
    port(
      p_resetn   : in  std_ulogic;

      p_out_clk     : in  std_ulogic;
      p_out_data    : out std_ulogic_vector(data_width-1 downto 0);
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic;

      p_in_clk    : in  std_ulogic;
      p_in_data   : in  std_ulogic_vector(data_width-1 downto 0);
      p_in_write  : in  std_ulogic;
      p_in_full_n : out std_ulogic
      );
  end component;

  component fifo_sink
    generic (
      width: integer
      );
    port (
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_in_full_n : out std_ulogic;
      p_in_write  : in std_ulogic;
      p_in_data   : in std_ulogic_vector(width-1 downto 0)
      );
  end component;

  component fifo_narrower
    generic(
      parts : integer;
      width_out : integer
      );
    port(
      p_resetn  : in  std_ulogic;
      p_clk     : in  std_ulogic;

      p_out_data    : out std_ulogic_vector(width_out-1 downto 0);
      p_out_read    : in  std_ulogic;
      p_out_empty_n : out std_ulogic;

      p_in_data   : in  std_ulogic_vector(parts*width_out-1 downto 0);
      p_in_write  : in  std_ulogic;
      p_in_full_n : out std_ulogic
      );
  end component;

  component fifo_framed is
    generic(
      depth : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd;
      p_in_ack   : out fifo_framed_rsp;

      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp
      );
  end component;

  component fifo_framed_atomic is
    generic(
      depth : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_in_val   : in fifo_framed_cmd;
      p_in_ack   : out fifo_framed_rsp;

      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp
      );
  end component;

  component fifo_framed_async is
    generic(
      depth : natural
      );
    port(
      p_resetn    : in  std_ulogic;

      p_in_clk    : in  std_ulogic;
      p_in_val    : in fifo_framed_cmd;
      p_in_ack    : out fifo_framed_rsp;

      p_out_clk   : in  std_ulogic;
      p_out_val   : out fifo_framed_cmd;
      p_out_ack   : in fifo_framed_rsp
      );
  end component;

  component fifo_framed_endpoint
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_in_val   : in fifo_framed_cmd;
      p_cmd_in_ack   : out fifo_framed_rsp;
      p_cmd_out_val   : out fifo_framed_cmd;
      p_cmd_out_ack   : in fifo_framed_rsp;

      p_rsp_in_val   : in fifo_framed_cmd;
      p_rsp_in_ack   : out fifo_framed_rsp;
      p_rsp_out_val   : out fifo_framed_cmd;
      p_rsp_out_ack   : in fifo_framed_rsp
      );
  end component;

  component fifo_framed_gateway
    generic(
      source_id: component_id;
      target_id: component_id
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_in_val   : in fifo_framed_cmd;
      p_cmd_in_ack   : out fifo_framed_rsp;
      p_cmd_out_val   : out fifo_framed_cmd;
      p_cmd_out_ack   : in fifo_framed_rsp;

      p_rsp_in_val   : in fifo_framed_cmd;
      p_rsp_in_ack   : out fifo_framed_rsp;
      p_rsp_out_val   : out fifo_framed_cmd;
      p_rsp_out_ack   : in fifo_framed_rsp
      );
  end component;
  
  function fifo_framed_header(dst: component_id;
                              src: component_id)
    return framed_data_t is
  begin
    return framed_data_t(to_unsigned(src * 16 + dst, 8));
  end;

  function fifo_framed_header_dst(w: framed_data_t)
    return component_id is
  begin
    return to_integer(unsigned(w(3 downto 0)));
  end;
  
  function fifo_framed_header_src(w: framed_data_t)
    return component_id is
  begin
    return to_integer(unsigned(w(7 downto 4)));
  end;

end package fifo;
