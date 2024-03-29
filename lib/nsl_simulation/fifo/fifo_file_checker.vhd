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
    reset_n_i  : in  std_ulogic;
    clock_i     : in  std_ulogic;

    ready_o: out std_ulogic;
    valid_i: in std_ulogic;
    data_i: in std_ulogic_vector(width-1 downto 0);
    
    done_o: out std_ulogic
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

  process (clock_i, reset_n_i)
  begin
    if (reset_n_i = '0') then
      is_reset := true;
      is_open := false;
    elsif rising_edge(clock_i) then
      if is_reset then
        file_open(fd, filename, READ_MODE);
        is_reset := false;
        is_open := true;
      end if;
    end if;
  end process;

  process (clock_i)
  begin
    if rising_edge(clock_i) then
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

  process (clock_i, valid_i, r_accept)
    variable data : std_logic_vector(width-1 downto 0);
    variable udata : std_ulogic_vector(width-1 downto 0);
  begin
    if rising_edge(clock_i) then
      if not is_reset and is_open and r_accept = '1' and valid_i = '1' then
        readline(fd, line_content);
        nsl_simulation.file_io.slv_read(line_content, data);
        read(line_content, wait_cycles);

        if not std_match(std_ulogic_vector(data), to_x01(data_i)) then
          nsl_simulation.assertions.assert_equal("value vs. fifo data",
                                                 std_ulogic_vector(data),
                                                 to_x01(data_i),
                                                 error);
        end if;
      end if;
    end if;
  end process;

  moore: process (clock_i)
  begin
    if falling_edge(clock_i) then
      ready_o <= r_accept;
    end if;
    if not is_reset and is_open then
      if endfile(fd) then
        done_o <= '1';
      else
        done_o <= '0';
      end if;
    else
      done_o <= '0';
    end if;
  end process;
  
  
end rtl;
