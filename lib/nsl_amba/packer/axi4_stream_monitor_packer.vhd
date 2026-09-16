library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;

entity axi4_stream_monitor_packer is
  generic (
    config_c: config_t
    );
  port (
    tvalid : in std_logic;
    tready : in std_logic := '1';
    tdata : in std_logic_vector(8 * config_c.data_width - 1 downto 0) := (others => '0');
    tstrb : in std_logic_vector(config_c.data_width - 1 downto 0) := (others => '1');
    tkeep : in std_logic_vector(config_c.data_width - 1 downto 0) := (others => '1');
    tlast: in std_logic := '1';
    tid: in std_logic_vector(config_c.id_width - 1 downto 0) := (others => '0');
    tdest: in std_logic_vector(config_c.dest_width-1 downto 0) := (others => '0');
    tuser: in std_logic_vector(config_c.user_width-1 downto 0) := (others => '0');

    stream_o : out bus_t
    );
end entity;

architecture rtl of axi4_stream_monitor_packer is

begin

  -- Both bus halves are observed, none is driven back to the pins.
  stream_o.m <= transfer(config_c,
                         bytes => to_be(unsigned(tdata)),
                         strobe => std_ulogic_vector(tstrb),
                         keep => std_ulogic_vector(tkeep),
                         order => BYTE_ORDER_DECREASING,
                         id => std_ulogic_vector(tid),
                         user => std_ulogic_vector(tuser),
                         dest => std_ulogic_vector(tdest),
                         valid => tvalid = '1',
                         last => tlast = '1');
  stream_o.s <= accept(config_c, tready = '1');

end architecture;
