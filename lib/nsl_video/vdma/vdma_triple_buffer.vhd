library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video, nsl_logic;
use nsl_logic.bool.all;

entity vdma_triple_buffer is
  generic(
    address_width_c : positive;
    base_c : unsigned;
    buffer_size_c : unsigned
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    writer_base_o : out unsigned(address_width_c-1 downto 0);
    writer_done_i : in std_ulogic;
    writer_status_i : in nsl_video.vdma.frame_status_t;

    display_request_i : in std_ulogic;
    reader_base_o : out unsigned(address_width_c-1 downto 0);
    reader_start_o : out std_ulogic;
    reader_ready_i : in std_ulogic;

    frame_dropped_o : out std_ulogic;
    frame_repeated_o : out std_ulogic;
    frame_skipped_o : out std_ulogic
    );
end entity;

architecture beh of vdma_triple_buffer is

  subtype address_t is unsigned(address_width_c-1 downto 0);
  subtype buffer_t is integer range 0 to 2;
  type address_vector is array(buffer_t) of address_t;

  function buffer_bases return address_vector
  is
    variable ret: address_vector;
  begin
    for i in buffer_t
    loop
      ret(i) := resize(base_c, address_width_c)
                + resize(buffer_size_c * to_unsigned(i, 2), address_width_c);
    end loop;
    return ret;
  end function;

  constant bases_c : address_vector := buffer_bases;

  type regs_t is
  record
    displayed, latest, writing: buffer_t;
    -- latest holds a complete frame never displayed yet.
    fresh: boolean;
    writer_base, reader_base: address_t;
    start: boolean;
    dropped, repeated, skipped: boolean;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.displayed <= 0;
      r.latest <= 1;
      r.writing <= 2;
      r.fresh <= false;
      r.writer_base <= bases_c(2);
      r.reader_base <= bases_c(0);
      r.start <= false;
      r.dropped <= false;
      r.repeated <= false;
      r.skipped <= false;
    end if;
  end process;

  transition: process(r, writer_done_i, writer_status_i,
                      display_request_i, reader_ready_i) is
    variable completed, accepted: boolean;
  begin
    rin <= r;

    completed := writer_done_i = '1' and writer_status_i.complete = '1';
    -- While start is asserted, reader_ready_i does not reflect it yet.
    accepted := display_request_i = '1' and reader_ready_i = '1' and not r.start;

    rin.start <= accepted;
    rin.dropped <= writer_done_i = '1' and writer_status_i.complete /= '1';
    rin.repeated <= accepted and not completed and not r.fresh;
    rin.skipped <= completed and r.fresh;

    if completed and accepted then
      -- Display the frame that just completed; latest becomes stale
      -- whatever it held, and the buffer the reader is done with is
      -- free for writing.
      rin.displayed <= r.writing;
      rin.writing <= r.displayed;
      rin.fresh <= false;
      rin.writer_base <= bases_c(r.displayed);
      rin.reader_base <= bases_c(r.writing);
    elsif completed then
      rin.latest <= r.writing;
      rin.writing <= r.latest;
      rin.fresh <= true;
      rin.writer_base <= bases_c(r.latest);
    elsif accepted and r.fresh then
      rin.displayed <= r.latest;
      rin.latest <= r.displayed;
      rin.fresh <= false;
      rin.reader_base <= bases_c(r.latest);
    end if;
  end process;

  moore: process(r) is
  begin
    writer_base_o <= r.writer_base;
    reader_base_o <= r.reader_base;
    reader_start_o <= to_logic(r.start);
    frame_dropped_o <= to_logic(r.dropped);
    frame_repeated_o <= to_logic(r.repeated);
    frame_skipped_o <= to_logic(r.skipped);
  end process;

end architecture;
