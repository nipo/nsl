library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight;

entity dapbus_interconnect is
  generic(
    access_port_count : natural range 1 to 256
    );
  port(
    s_i : in nsl_coresight.dapbus.dapbus_m_o;
    s_o : out nsl_coresight.dapbus.dapbus_m_i;

    m_o : out nsl_coresight.dapbus.dapbus_m_o_vector(0 to access_port_count-1);
    m_i : in nsl_coresight.dapbus.dapbus_m_i_vector(0 to access_port_count-1)
    );
end entity;

architecture beh of dapbus_interconnect is
begin

  io: process(s_i, m_i)
    variable selected : natural range 0 to 255;
  begin
    selected := to_integer(unsigned(s_i.addr(15 downto 8)));

    s_o.ready <= '1';
    s_o.rdata <= (others => '0');
    s_o.slverr <= '0';

    lp: for i in 0 to access_port_count-1
    loop
      if selected = i then
        m_o(i) <= s_i;
        s_o <= m_i(i);
      else
        m_o(i).sel <= '0';
        m_o(i).enable <= '0';
        m_o(i).write <= '0';
        m_o(i).addr <= (others => '-');
        m_o(i).wdata <= (others => '-');
        m_o(i).abort <= '0';
      end if;
    end loop;

  end process;
  
end architecture;

