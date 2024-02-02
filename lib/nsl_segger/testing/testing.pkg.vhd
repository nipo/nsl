library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_coresight, nsl_data, nsl_bnoc, nsl_simulation, nsl_math, work;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_data.endian.all;
use nsl_bnoc.testing.all;
use nsl_coresight.testing.all;
use work.rtt.all;

package testing is

  procedure memap_rtt_channel_write(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant channel_address: unsigned(31 downto 0);
    constant payload: byte_string);

end package testing;

package body testing is

  procedure memap_rtt_channel_write(
    log_context: string;
    variable cmd_queue: inout framed_queue_root;
    variable rsp_queue: inout framed_queue_root;
    constant channel_address: unsigned(31 downto 0);
    constant payload: byte_string)
  is
    variable channel_pointers: byte_string(rtt_channel_buffer_offset_c to rtt_channel_size_c-1);
    variable addr, len, wptr, rptr, to_copy: unsigned(31 downto 0);
    alias data : byte_string(0 to payload'length-1) is payload;
    variable point: natural := 0;
  begin
    while point < data'length
    loop
      memap_read(log_context & "-pr", cmd_queue, rsp_queue,
                 channel_address + rtt_channel_buffer_offset_c,
                 channel_pointers);
      addr := from_le(channel_pointers(rtt_channel_buffer_offset_c to rtt_channel_buffer_offset_c+3));
      len := from_le(channel_pointers(rtt_channel_buffer_length_offset_c to rtt_channel_buffer_length_offset_c+3));
      wptr := from_le(channel_pointers(rtt_channel_wptr_offset_c to rtt_channel_wptr_offset_c+3));
      rptr := from_le(channel_pointers(rtt_channel_rptr_offset_c to rtt_channel_rptr_offset_c+3));

      if addr = 0 or len = 0 then
        return;
      end if;

      if rptr = wptr then
        to_copy := len - 1;
      elsif rptr < wptr and rptr /= 0 then
        to_copy := len - wptr;
      elsif rptr < wptr then
        to_copy := len - wptr - 1;
      else
        to_copy := rptr - wptr - 1;
      end if;

      if to_copy > data'length - point then
        to_copy := to_unsigned(data'length - point, to_copy'length);
      end if;
      
      if to_copy /= 0 then
        memap_write(log_context & "-dw", cmd_queue, rsp_queue,
                    addr + wptr, data(point to point + to_integer(to_copy) - 1));

        wptr := wptr + to_copy;
        if wptr = len then
          wptr := (others => '0');
        end if;

        memap_write(log_context & "-pw", cmd_queue, rsp_queue,
                    channel_address + rtt_channel_wptr_offset_c,
                    to_le(wptr));

        point := point + to_integer(to_copy);
      end if;
    end loop;
  end procedure;      
end package body;
