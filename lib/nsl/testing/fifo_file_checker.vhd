library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity fifo_file_checker is
  generic (
    width: integer;
    filename: string
    );
  port (
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_full_n: out std_ulogic;
    p_write: in std_ulogic;
    p_data: in std_ulogic_vector(width-1 downto 0)
    );
end fifo_file_checker;

architecture rtl of fifo_file_checker is

  file fd : text;
  shared variable line_content : line;
  shared variable is_reset : boolean := false;
  shared variable is_open : boolean := false;
  shared variable wait_cycles : integer := 0;
  shared variable data : integer;

  signal r_accept : std_ulogic;

begin

  process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      if not is_reset then
        file_open(fd, filename, READ_MODE);
        is_reset := true;
        is_open := true;
      end if;
    elsif rising_edge(p_clk) then
      is_reset := false;
    end if;
  end process;

  process (p_clk)
  begin
    if rising_edge(p_clk) then
      r_accept <= '0';

      if is_open and not is_reset then
        if wait_cycles /= 0 then
          wait_cycles := wait_cycles - 1;
        elsif not endfile(fd) then
          r_accept <= '1';
        end if;
      end if;
    end if;
  end process;

  process (p_clk, p_write, r_accept)
  begin
    if rising_edge(p_clk) then
      if not is_reset and is_open and r_accept = '1' and p_write = '1' then
        readline(fd, line_content);
        read(line_content, data);
        read(line_content, wait_cycles);
        assert std_ulogic_vector(to_unsigned(data, width)) = p_data
          report "Expected value "
            & integer'image(data)
            & " does not match fifo data "
            & integer'image(to_integer(unsigned(p_data)))
          severity error;
      end if;
    end if;
  end process;

  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_full_n <= r_accept;
    end if;
  end process;
  
  
end rtl;
