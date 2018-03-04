library ieee;
use ieee.std_logic_1164.all;

library nsl;

entity ft245_sync_fifo_slave is
  port (
    p_clk    : in std_ulogic;

    p_ftdi_clk  : out std_ulogic;
    p_ftdi_data : inout std_logic_vector(7 downto 0);
    p_ftdi_rxfn : out std_ulogic;
    p_ftdi_txen : out std_ulogic;
    p_ftdi_rdn  : in std_ulogic;
    p_ftdi_wrn  : in std_ulogic;
    p_ftdi_oen  : in std_ulogic;

    p_in_ready : in  std_ulogic;
    p_in_valid : out std_ulogic;
    p_in_data  : out std_ulogic_vector(7 downto 0);

    p_out_ready : out std_ulogic;
    p_out_valid : in  std_ulogic;
    p_out_data  : in  std_ulogic_vector(7 downto 0)
    );
end ft245_sync_fifo_slave;

architecture arch of ft245_sync_fifo_slave is
  
begin
  
  p_ftdi_clk <= p_clk;
  p_in_data <= std_ulogic_vector(p_ftdi_data);
  p_ftdi_data <= std_logic_vector(p_out_data) when p_ftdi_oen = '0' else (others => 'Z');  
  p_ftdi_rxfn <= not p_out_valid;
  p_ftdi_txen <= not p_in_ready;
  p_out_ready <= not p_ftdi_rdn;
  p_in_valid <= not p_ftdi_wrn;

end arch;
