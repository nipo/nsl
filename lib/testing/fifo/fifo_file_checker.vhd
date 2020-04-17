library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_simulation;

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

  process (p_clk, p_valid, r_accept)
    variable data : std_logic_vector(width-1 downto 0);
    variable udata : std_ulogic_vector(width-1 downto 0);
    variable complaint : line;
  begin
    if rising_edge(p_clk) then
      if not is_reset and is_open and r_accept = '1' and p_valid = '1' then
        readline(fd, line_content);
        nsl_simulation.file_io.slv_read(line_content, data);
        read(line_content, wait_cycles);

        write(complaint, filename);
        write(complaint, string'(" value "));
        nsl_simulation.file_io.slv_write(complaint, std_logic_vector(data));
        write(complaint, string'(" does not match fifo data "));
        nsl_simulation.file_io.slv_write(complaint, std_logic_vector(p_data));

        
        assert std_match(std_ulogic_vector(data), to_x01(p_data))
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
