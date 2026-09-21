library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data, nsl_logic;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_logic.bool.all;

-- Vivado IP wrapper for nsl_amba.stream_fifo.axi4_stream_async_packet_drop_fifo.
--
-- IP-XACT cannot express record generics or vector clock ports, so this
-- layer presents:
--
--   config_c : config_t   ->  data_byte_count_c (stream is always
--                             byte-aligned with tlast: a packet-drop
--                             fifo needs packet boundaries)
--   clock_i(0 to 1)       ->  in_clock_i and out_clock_i
--
-- Input is never back-pressured: a packet that does not fit is dropped
-- whole and pulses overrun_o.

entity axi4_stream_async_packet_drop_fifo_ip_top is
  generic(
    -- Payload bytes per beat.
    data_byte_count_c : natural range 1 to 8 := 1;
    -- Depth of the fifo, as log2 of its capacity in bytes.
    word_count_l2_c : natural range 1 to 24 := 9;
    -- 2 for an asynchronous fifo, 1 when both sides share in_clock_i.
    -- With 1, out_clock_i is hidden by ports.tcl and ignored here.
    clock_count_c : natural range 1 to 2 := 2
    );
  port(
    reset_n_i   : in std_logic;
    -- Input side clock.  With clock_count_c = 1 it clocks the whole
    -- fifo and out_clock_i is unused.
    in_clock_i  : in std_logic;
    -- Output side clock, only when clock_count_c = 2.
    out_clock_i : in std_logic := '0';

    error_i   : in  std_logic := '0';
    overrun_o : out std_logic;

    in_tdata  : in  std_logic_vector(8*data_byte_count_c-1 downto 0);
    in_tvalid : in  std_logic;
    in_tlast  : in  std_logic;
    in_tready : out std_logic;

    out_tdata  : out std_logic_vector(8*data_byte_count_c-1 downto 0);
    out_tvalid : out std_logic;
    out_tlast  : out std_logic;
    out_tready : in  std_logic
    );
end entity;

architecture beh of axi4_stream_async_packet_drop_fifo_ip_top is

  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;

  attribute X_INTERFACE_INFO of in_clock_i : signal is "xilinx.com:signal:clock:1.0 in_clock_i CLK";
  attribute X_INTERFACE_INFO of out_clock_i : signal is "xilinx.com:signal:clock:1.0 out_clock_i CLK";
  attribute X_INTERFACE_INFO of reset_n_i : signal is "xilinx.com:signal:reset:1.0 reset_n_i RST";
  attribute X_INTERFACE_PARAMETER of reset_n_i : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_PARAMETER of in_clock_i : signal is "ASSOCIATED_BUSIF in, ASSOCIATED_RESET reset_n_i";
  attribute X_INTERFACE_PARAMETER of out_clock_i : signal is "ASSOCIATED_BUSIF out, ASSOCIATED_RESET reset_n_i";

  attribute X_INTERFACE_INFO of in_tdata : signal is "xilinx.com:interface:axis:1.0 in TDATA";
  attribute X_INTERFACE_INFO of in_tvalid : signal is "xilinx.com:interface:axis:1.0 in TVALID";
  attribute X_INTERFACE_INFO of in_tlast : signal is "xilinx.com:interface:axis:1.0 in TLAST";
  attribute X_INTERFACE_INFO of in_tready : signal is "xilinx.com:interface:axis:1.0 in TREADY";
  attribute X_INTERFACE_INFO of out_tdata : signal is "xilinx.com:interface:axis:1.0 out TDATA";
  attribute X_INTERFACE_INFO of out_tvalid : signal is "xilinx.com:interface:axis:1.0 out TVALID";
  attribute X_INTERFACE_INFO of out_tlast : signal is "xilinx.com:interface:axis:1.0 out TLAST";
  attribute X_INTERFACE_INFO of out_tready : signal is "xilinx.com:interface:axis:1.0 out TREADY";

  constant cfg_c : nsl_amba.axi4_stream.config_t
    := nsl_amba.axi4_stream.config(bytes => data_byte_count_c, last => true);

  -- AXI4-Stream byte order: byte 0 occupies tdata(7 downto 0).
  function to_slv(b : byte_string) return std_logic_vector
  is
    alias xb : byte_string(0 to b'length-1) is b;
    variable r : std_logic_vector(8*b'length-1 downto 0);
  begin
    for i in 0 to b'length-1 loop
      r(8*i+7 downto 8*i) := std_logic_vector(xb(i));
    end loop;
    return r;
  end function;

  function to_bs(v : std_logic_vector) return byte_string
  is
    alias xv : std_logic_vector(v'length-1 downto 0) is v;
    variable r : byte_string(0 to v'length/8-1);
  begin
    for i in 0 to v'length/8-1 loop
      r(i) := std_ulogic_vector(xv(8*i+7 downto 8*i));
    end loop;
    return r;
  end function;

  signal clock_s : std_ulogic_vector(0 to clock_count_c-1);
  signal in_m_s   : master_t;
  signal in_s_s   : slave_t;
  signal out_m_s  : master_t;
  signal out_s_s  : slave_t;

begin

  clock_s(0) <= in_clock_i;

  async_clock: if clock_count_c = 2
  generate
    clock_s(1) <= out_clock_i;
  end generate;

  in_m_s <= transfer(cfg_c,
                     bytes => to_bs(in_tdata),
                     valid => in_tvalid = '1',
                     last  => in_tlast = '1');
  in_tready <= to_logic(is_ready(cfg_c, in_s_s));

  out_s_s <= accept(cfg_c, out_tready = '1');
  out_tdata  <= to_slv(bytes(cfg_c, out_m_s));
  out_tvalid <= to_logic(is_valid(cfg_c, out_m_s));
  out_tlast  <= to_logic(is_last(cfg_c, out_m_s));

  dut: nsl_amba.stream_fifo.axi4_stream_async_packet_drop_fifo
    generic map(
      config_c        => cfg_c,
      word_count_l2_c => word_count_l2_c,
      clock_count_c   => clock_count_c
      )
    port map(
      reset_n_i => reset_n_i,
      clock_i   => clock_s,

      error_i => error_i,

      in_i => in_m_s,
      in_o => in_s_s,

      out_i => out_s_s,
      out_o => out_m_s,

      overrun_o => overrun_o
      );

end architecture;
