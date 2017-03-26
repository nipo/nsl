library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.types.all;

package noc is

  component nsl_noc_injector is
    generic(
      g_id        : nsl_id
      );
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
  end component;

  component nsl_noc_extractor is
    generic(
      g_id        : nsl_id
      );
    port(
      p_reset_n   : in  std_ulogic;
      p_clk       : in  std_ulogic;

      p_count_in  : in std_ulogic_vector(7 downto 0);
      p_count_out : out std_ulogic_vector(7 downto 0);

      p_data_in   : in std_ulogic_vector(7 downto 0);
      p_data_out  : out std_ulogic_vector(7 downto 0);

      p_req_in    : in std_ulogic;
      p_req_out   : out std_ulogic;

      p_msg       : out std_ulogic_vector(7 downto 0);
      p_msg_val   : out std_ulogic;
      p_msg_ack   : out std_ulogic;

      p_avail     : in unsigned(9 downto 0)
      );
  end component;
  
end package noc;
