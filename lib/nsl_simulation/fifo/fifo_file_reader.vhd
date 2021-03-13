library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_simulation;

entity fifo_file_reader is
  generic (
    width: integer;
    filename: string
    );
  port (
    reset_n_i  : in  std_ulogic;
    clock_i     : in  std_ulogic;

    valid_o: out std_ulogic;
    ready_i: in std_ulogic;
    data_o: out std_ulogic_vector(width-1 downto 0);
    
    done_o: out std_ulogic
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

begin

  process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r_is_reset <= false;
    end if;
    if (reset_n_i = '0') then
      if not r_is_reset then
        file_open(fd, filename, READ_MODE);
        r_is_reset <= true;
        r_is_open <= true;
      end if;
    end if;
  end process;

  process (clock_i)
    variable line_content : line;
    variable wc : integer;
    variable data : std_logic_vector(width-1 downto 0);
  begin
    r_done <= '0';

    if not r_is_reset and rising_edge(clock_i) then
      if r_data_valid = '0' or ready_i = '1' then
        if r_wait_cycles /= 0 then
          r_data_valid <= '0';
          r_wait_cycles <= r_wait_cycles - 1;
        elsif r_is_open then
          if endfile(fd) then
            r_data_valid <= '0';
            r_done <= '1';
          else
            readline(fd, line_content);
            nsl_simulation.file_io.slv_read(line_content, data);
            r_data <= std_ulogic_vector(data);
            read(line_content, wc);
            r_wait_cycles <= wc;
            r_data_valid <= '1';
          end if;
        else
          r_data_valid <= '0';
        end if;
      elsif ready_i = '1' then
        r_data_valid <= '0';
      end if;
    end if;
  end process;
  
  moore: process (clock_i)
  begin
    if falling_edge(clock_i) then
      data_o <= r_data;
      valid_o <= r_data_valid;
      done_o <= r_done;
    end if;
  end process;
  
  
end rtl;
