library ieee;
use ieee.std_logic_1164.all;

entity fifo_merger is
  port (
    p_io_data: inout std_logic_vector(7 downto 0);
    p_io_rxfn: out std_ulogic;
    p_io_txen: out std_ulogic;
    p_io_rdn: in std_ulogic;
    p_io_wrn: in std_ulogic;
    p_io_oen: in std_ulogic;

    p_out_wok: in std_ulogic;
    p_out_w: out std_ulogic;
    p_out_d: out std_ulogic_vector(7 downto 0);

    p_in_r: out std_ulogic;
    p_in_rok: in std_ulogic;
    p_in_d: in std_ulogic_vector(7 downto 0)
    );
end fifo_merger;

architecture arch of fifo_merger is
  
begin
  
  -- Constant mapping
  p_out_d <= std_ulogic_vector(p_io_data);
  p_io_data <= std_logic_vector(p_in_d) when p_io_oen = '0' else (others => 'Z');  
  p_io_rxfn <= not p_in_rok;
  p_io_txen <= not p_out_wok;
  p_in_r <= not p_io_rdn;
  p_out_w <= not p_io_wrn;

end arch;
