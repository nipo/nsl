library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity fifo_file_reader is
  generic (
    width: integer;
    filename: string
    );
  port (
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_empty_n: out std_ulogic;
    p_read: in std_ulogic;
    p_data: out std_ulogic_vector(width-1 downto 0);
    
    p_done: out std_ulogic
    );
end fifo_file_reader;

architecture rtl of fifo_file_reader is

  file fd : text;
  shared variable line_content : line;
  shared variable is_reset : boolean := false;
  shared variable is_open : boolean := false;
  shared variable wait_cycles : integer := 0;

  signal r_data : std_ulogic_vector(width-1 downto 0);
  signal r_data_valid : std_ulogic;
  signal r_done : std_ulogic;

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
    variable data : integer;
  begin
    r_done <= '0';

    if not is_reset and rising_edge(p_clk) then
      if r_data_valid = '0' or p_read = '1' then
        if wait_cycles /= 0 then
          r_data_valid <= '0';
          wait_cycles := wait_cycles - 1;
        elsif is_open then
          if endfile(fd) then
            r_data_valid <= '0';
            r_done <= '1';
          else
            readline(fd, line_content);
            read(line_content, data);
            read(line_content, wait_cycles);
            r_data <= std_ulogic_vector(to_unsigned(data, width));
            r_data_valid <= '1';
          end if;
        else
          r_data_valid <= '0';
        end if;
      elsif p_read = '1' then
        r_data_valid <= '0';
      end if;
    end if;
  end process;
  
  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_data <= r_data;
      p_empty_n <= r_data_valid;
      p_done <= r_done;
    end if;
  end process;
  
  
end rtl;
