library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.types.all;

entity nsl_noc_router is
  port(
    p_reset_n   : in  std_ulogic;
    p_clk       : in  std_ulogic;

    p_count_in  : in std_ulogic_vector(7 downto 0);
    p_count_out : out std_ulogic_vector(7 downto 0);

    p_data_in   : in std_ulogic_vector(7 downto 0);
    p_data_out  : out std_ulogic_vector(7 downto 0);

    p_req_in    : in std_ulogic;
    p_req_out   : out std_ulogic;

    p_msg       : in  std_ulogic_vector(7 downto 0);
    p_msg_val   : in  std_ulogic;
    p_msg_ack   : out std_ulogic
    );
end entity;
