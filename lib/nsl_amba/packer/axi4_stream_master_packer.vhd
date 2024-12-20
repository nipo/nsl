library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba, nsl_logic, nsl_data;
use nsl_amba.axi4_stream.all;
use nsl_logic.bool.all;
use nsl_data.bytestream.all;

entity axi4_stream_master_packer is
  generic (
    config_c: config_t
    );
  port (
    tvalid : out std_logic;
    tready : in std_logic := '1';
    tdata : out std_logic_vector(8 * config_c.data_width - 1 downto 0);
    tstrb : out std_logic_vector(config_c.data_width - 1 downto 0);
    tkeep : out std_logic_vector(config_c.data_width - 1 downto 0);
    tlast: out std_logic;
    tid: out std_logic_vector(config_c.id_width - 1 downto 0);
    tdest: out std_logic_vector(config_c.dest_width-1 downto 0);
    tuser: out std_logic_vector(config_c.user_width-1 downto 0);

    stream_o : out slave_t;
    stream_i : in master_t
    );
end entity;

architecture rtl of axi4_stream_master_packer is

begin

  tvalid <= to_logic(is_valid(config_c, stream_i));
  stream_o <= accept(config_c, tready = '1');
  tdata <= std_logic_vector(value(config_c, stream_i));
  tstrb <= std_logic_vector(strobe(config_c, stream_i, BYTE_ORDER_DECREASING));
  tkeep <= std_logic_vector(keep(config_c, stream_i, BYTE_ORDER_DECREASING));
  tlast <= to_logic(is_last(config_c, stream_i));
  tid <= std_logic_vector(id(config_c, stream_i));
  tdest <= std_logic_vector(dest(config_c, stream_i));
  tuser <= std_logic_vector(user(config_c, stream_i));
  
end architecture;
