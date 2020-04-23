library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_i2c;

entity i2c_resolver is
  generic(
    port_count : natural
    );
  port(
    bus_i : in nsl_i2c.i2c.i2c_o_vector(0 to port_count-1);
    bus_o : out nsl_i2c.i2c.i2c_i
    );
end entity;

architecture beh of i2c_resolver is
begin

  upd: process(bus_i)
    variable sda, scl : std_ulogic;
  begin
    sda := '1';
    scl := '1';

    l: for i in 0 to port_count-1
    loop
      if bus_i(i).sda.drain = '1' then
        sda := '0';
      end if;
      if bus_i(i).scl.drain = '1' then
        scl := '0';
      end if;
    end loop;

    if sda = '1' then
      bus_o.sda <= '1' after 10 ns;
    else
      bus_o.sda <= '0';
    end if;

    if scl = '1' then
      bus_o.scl <= '1' after 10 ns;
    else
      bus_o.scl <= '0';
    end if;
    
  end process;    
  
end architecture;
