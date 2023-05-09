library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library nsl_simulation, nsl_data;
use nsl_data.bytestream.all;
use nsl_data.binary_io.all;
use nsl_data.text.all;
use nsl_simulation.logging.all;

entity fifo_bytestream_reader is
  generic (
    flit_byte_count_c    : positive;
    filename_c : string
    );
  port (
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    valid_o : out std_ulogic;
    ready_i : in  std_ulogic;
    data_o  : out nsl_data.bytestream.byte_string(0 to flit_byte_count_c-1);

    done_o : out std_ulogic
    );
end fifo_bytestream_reader;

architecture rtl of fifo_bytestream_reader is

  file fd : binary_file;
  shared variable is_reset : boolean := false;
  shared variable is_open : boolean := false;
  shared variable is_done : boolean := false;
  signal valid_s : std_ulogic;
  signal data_s : nsl_data.bytestream.byte_string(0 to flit_byte_count_c-1);
  
begin

  fd_mgmt: process (clock_i, reset_n_i)
    variable status: file_open_status;
  begin
    if rising_edge(clock_i) then
      if is_reset and reset_n_i /= '0' then
        file_open(status, fd, filename_c, READ_MODE);
        is_reset := false;
        is_open := status = OPEN_OK;
        is_done := false;
        log_info(filename_c & " open status: " & file_open_status'image(status));
      end if;
    end if;

    if reset_n_i = '0' then
      is_reset := true;
      is_done := false;
      if is_open then
        file_close(fd);
        is_open := false;
      end if;
    end if;
  end process;

  transition: process (clock_i) is
    variable tmp : nsl_data.bytestream.byte_string(0 to flit_byte_count_c-1);
    variable refill : boolean;
  begin
    if rising_edge(clock_i) then
      refill := valid_s = '0';

      if valid_s = '1' and ready_i = '1' then
        valid_s <= '0';
        refill := true;
        data_s <= (others => "--------");
      end if;

      if is_done or (is_open and endfile(fd)) then
        is_done := true;
      elsif refill and is_open then
        read(fd, tmp);
        data_s <= tmp;
        valid_s <= '1';
      end if;
    end if;

    if reset_n_i = '0' then
      valid_s <= '0';
      data_s <= (others => "--------");
    end if;
  end process;

  moore: process (clock_i) is
  begin
    if falling_edge(clock_i) then
      valid_o <= valid_s;
      data_o <= data_s;
    end if;
  end process;
  
end rtl;
