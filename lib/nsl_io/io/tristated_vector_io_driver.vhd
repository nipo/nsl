library ieee;
use ieee.std_logic_1164.all;

library nsl_io;

entity tristated_vector_io_driver is

  generic(
    width_c : natural
    );
  port(
    v_i : in nsl_io.io.tristated_vector(width_c-1 downto 0);
    v_o : out std_ulogic_vector(width_c-1 downto 0);
    io_io : inout std_logic_vector(width_c-1 downto 0)
    );

end entity;

architecture beh of tristated_vector_io_driver is
begin

  instances: for i in 0 to width_c-1
  generate
    driver: nsl_io.io.tristated_io_driver
      port map(
        v_i => v_i(i),
        v_o => v_o(i),
        io_io => io_io(i)
        );
  end generate;
  
end architecture;
