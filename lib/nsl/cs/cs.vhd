library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl;
use nsl.fifo.all;

package cs is

  subtype cs_reg is std_ulogic_vector(31 downto 0);
  type cs_reg_array is array (natural range <>) of cs_reg;

  constant CS_REG_WRITE: std_ulogic_vector(7 downto 0) := "0-------";
  constant CS_REG_READ : std_ulogic_vector(7 downto 0) := "1-------";
  
  component cs_framed_reg
    generic (
      config_count : integer range 1 to 128;
      status_count : integer range 1 to 128
      );
    port (
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_cmd_val   : in nsl.fifo.fifo_framed_cmd;
      p_cmd_ack   : out nsl.fifo.fifo_framed_rsp;

      p_rsp_val   : out nsl.fifo.fifo_framed_cmd;
      p_rsp_ack   : in nsl.fifo.fifo_framed_rsp;

      p_config_data  : out cs_reg;
      p_config_write : out std_ulogic_vector(config_count-1 downto 0);
      p_status   : in  cs_reg_array(status_count-1 downto 0) := (others => (others => '-'))
      );
  end component;

end package cs;
