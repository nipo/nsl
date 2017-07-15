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
  signal r_is_reset : boolean := false;
  signal r_is_open : boolean := false;
  signal r_wait_cycles : integer := 0;

  signal r_data : std_ulogic_vector(width-1 downto 0);
  signal r_data_valid : std_ulogic := '0';
  signal r_done : std_ulogic;

  procedure slv_read(buf: inout line; v: out std_logic_vector) is
    variable c: character;
  begin
    for i in v'range loop
      read(buf, c);
      case c is
        when 'X' => v(i) := 'X';
        when 'U' => v(i) := 'U';
        when 'Z' => v(i) := 'Z';
        when '0' => v(i) := '0';
        when '1' => v(i) := '1';
        when '-' => v(i) := '-';
        when 'W' => v(i) := 'W';
        when 'H' => v(i) := 'H';
        when 'L' => v(i) := 'L';
        when others => v(i) := '0';
      end case;
    end loop;
  end procedure slv_read;

begin

  process (p_clk, p_resetn)
  begin
    if (p_resetn = '0') then
      if not r_is_reset then
        file_open(fd, filename, READ_MODE);
        r_is_reset <= true;
        r_is_open <= true;
      end if;
    elsif rising_edge(p_clk) then
      r_is_reset <= false;
    end if;
  end process;

  process (p_clk)
    variable line_content : line;
    variable wc : integer;
    variable data : std_logic_vector(width-1 downto 0);
  begin
    r_done <= '0';

    if not r_is_reset and rising_edge(p_clk) then
      if r_data_valid = '0' or p_read = '1' then
        if r_wait_cycles /= 0 then
          r_data_valid <= '0';
          r_wait_cycles <= r_wait_cycles - 1;
        elsif r_is_open then
          if endfile(fd) then
            r_data_valid <= '0';
            r_done <= '1';
          else
            readline(fd, line_content);
            slv_read(line_content, data);
            r_data <= std_ulogic_vector(data);
            read(line_content, wc);
            r_wait_cycles <= wc;
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
