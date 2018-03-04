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

    p_ready: out std_ulogic;
    p_valid: in std_ulogic;
    p_data: in std_ulogic_vector(width-1 downto 0);
    
    p_done: out std_ulogic
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

  procedure slv_write(buf: inout line; v: in std_logic_vector) is
    variable c: character;
  begin
    for i in v'range loop
      case v(i) is
        when 'X' => c := 'X';
        when 'U' => c := 'U';
        when 'Z' => c := 'Z';
        when '0' => c := '0';
        when '1' => c := '1';
        when '-' => c := '-';
        when 'W' => c := 'W';
        when 'H' => c := 'H';
        when 'L' => c := 'L';
        when others => c := '0';
      end case;
      write(buf, c);
    end loop;
  end procedure slv_write;
  
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

  process (p_clk, p_valid, r_accept)
    variable data : std_logic_vector(width-1 downto 0);
    variable udata : std_ulogic_vector(width-1 downto 0);
    variable complaint : line;
  begin
    if rising_edge(p_clk) then
      if not is_reset and is_open and r_accept = '1' and p_valid = '1' then
        readline(fd, line_content);
        slv_read(line_content, data);
        read(line_content, wait_cycles);

        write(complaint, string'("Expected value "));
        slv_write(complaint, std_logic_vector(data));
        write(complaint, string'(" does not match fifo data "));
        slv_write(complaint, std_logic_vector(p_data));

        
        assert std_match(std_ulogic_vector(data), p_data)
          report complaint.all & CR & LF
          severity error;

        deallocate (complaint);
        complaint := new string'("");
        
      end if;
    end if;
  end process;

  moore: process (p_clk)
  begin
    if falling_edge(p_clk) then
      p_ready <= r_accept;
    end if;
    if not is_reset and is_open then
      if endfile(fd) then
        p_done <= '1';
      else
        p_done <= '0';
      end if;
    else
      p_done <= '0';
    end if;
  end process;
  
  
end rtl;
