library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_simulation, nsl_data;
use nsl_simulation.logging.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_data.binary_io.all;

entity fifo_bytestream_writer is
  generic (
    flit_byte_count_c    : positive;
    filename_c : string
    );
  port (
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    ready_o : out std_ulogic;
    valid_i : in  std_ulogic;
    data_i  : in  byte_string(0 to flit_byte_count_c-1)
    );
end fifo_bytestream_writer;

architecture rtl of fifo_bytestream_writer is

  file fd : binary_file;
  shared variable is_reset : boolean := false;
  shared variable is_open : boolean := false;
  signal s_did_accept: std_ulogic := '0';
  
begin

  file_side: process (clock_i, reset_n_i)
    variable status: file_open_status;
  begin
    if rising_edge(clock_i) then
      if is_reset and reset_n_i /= '0' then
        file_open(status, fd, filename_c, WRITE_MODE);
        is_reset := false;
        is_open := status = OPEN_OK;
        log_info(filename_c & " open status: " & file_open_status'image(status));
      end if;
    end if;

    if reset_n_i = '0' then
      is_reset := true;
      if is_open then
        file_close(fd);
        is_open := false;
      end if;
    end if;
  end process;

  fifo_side: process (clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      if reset_n_i = '0' and not is_reset and is_open then
        if s_did_accept = '1' and valid_i = '1' then
          log_info(filename_c & " > " & to_string(data_i));
          write(fd, data_i);
        end if;
        s_did_accept <= '1';
      else
        s_did_accept <= '0';
      end if;
    end if;

    if reset_n_i = '0' then
      s_did_accept <= '0';
    end if;
  end process;

  ready_o <= s_did_accept;
  
end rtl;
