library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_spi, nsl_data, nsl_clocking, work;
use nsl_data.bytestream.all;
use work.ads8028.all;

entity ads8028_framed_scanner is
  generic(
    channels_c : channel_mask_t := all_channels_c;
    external_reference_c : boolean := false;
    temperature_averaging_c : boolean := false;
    slave_no_c : natural range 0 to 6;
    divisor_c : natural range 1 to 128;
    frame_gap_c : natural := 0;
    resync_frames_c : positive := 256
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i   : in std_ulogic;

    cmd_o : out nsl_bnoc.framed.framed_req;
    cmd_i : in  nsl_bnoc.framed.framed_ack;
    rsp_i : in  nsl_bnoc.framed.framed_req;
    rsp_o : out nsl_bnoc.framed.framed_ack;

    busy_i : in std_ulogic := '0';

    code_o : out code_vector(0 to channel_count_c-1);
    valid_o : out channel_mask_t;
    strobe_o : out channel_mask_t
    );
end entity;

architecture beh of ads8028_framed_scanner is

  function control_word return std_ulogic_vector
  is
    variable ret : std_ulogic_vector(15 downto 0) := (others => '0');
  begin
    -- WRITE, REPEAT
    ret(15) := '1';
    ret(14) := '1';
    -- AIN0..AIN7 in bits 13..6, TSENSE in bit 5
    for i in channels_c'range
    loop
      ret(13 - i) := channels_c(i);
    end loop;
    if external_reference_c then
      ret(2) := '1';
    end if;
    if temperature_averaging_c then
      ret(1) := '1';
    end if;
    return ret;
  end function;

  constant control_c : byte_string(0 to 1) := from_suv(control_word);
  constant nop_c : byte_string(0 to 1) := (others => x"00");
  -- 2-byte full-duplex shift, without its data
  constant shift_c : byte_string(0 to 2) := nsl_spi.transactor.spi_shift(nop_c, true);

  -- Divisor, select (mode 2), shift command, then the shifted word and
  -- unselect
  constant prefix_c : byte_string := nsl_spi.transactor.spi_div(divisor_c)
                                     & nsl_spi.transactor.spi_select(slave_no_c, mode => 2)
                                     & shift_c(0 to 0);
  constant unselect_c : byte_string(0 to 0) := (0 => "00000111");
  constant frame_size_c : natural := prefix_c'length + 3;
  -- The response echoes command bytes and replaces the shifted words
  -- by the ones read.
  constant data_offset_c : natural := prefix_c'length;

  -- Results of the frame writing the control register and of the next
  -- one are invalid.
  constant write_discard_c : natural := 2;

  type state_t is (
    ST_RESET,
    ST_GAP,
    ST_BUSY,
    ST_SEND,
    ST_RECV,
    ST_DECODE
    );

  type regs_t is record
    state : state_t;
    frame : byte_string(0 to frame_size_c-1);
    cmd_index, rsp_index : natural range 0 to frame_size_c;
    word : byte_string(0 to 1);
    gap : natural range 0 to frame_gap_c;
    discard : natural range 0 to write_discard_c;
    invalid : natural range 0 to resync_frames_c;
    write : boolean;
    code : code_vector(0 to channel_count_c-1);
    valid, strobe : channel_mask_t;
  end record;

  signal r, rin : regs_t;
  signal busy_s : std_ulogic;

begin

  busy_sampler: nsl_clocking.async.async_input
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      data_i => busy_i,
      data_o => busy_s,
      rising_o => open,
      falling_o => open
      );

  regs: process(clock_i, reset_n_i)
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;
    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.code <= (others => (others => '0'));
      r.valid <= (others => '0');
      r.strobe <= (others => '0');
    end if;
  end process;

  transition: process(r, cmd_i, rsp_i, busy_s)
    variable address : natural range 0 to 15;
    variable channel : integer range -1 to channel_count_c-1;
    variable next_frame : byte_string(0 to frame_size_c-1);
    variable rsp_index : natural range 0 to frame_size_c;
  begin
    rin <= r;
    rin.strobe <= (others => '0');

    -- Responses are taken as they come, the transactor may send them
    -- while commands are still going.
    rsp_index := r.rsp_index;
    if (r.state = ST_SEND or r.state = ST_RECV) and rsp_i.valid = '1' then
      if r.rsp_index = data_offset_c then
        rin.word(0) <= rsp_i.data;
      elsif r.rsp_index = data_offset_c + 1 then
        rin.word(1) <= rsp_i.data;
      end if;
      if r.rsp_index /= frame_size_c then
        rsp_index := r.rsp_index + 1;
      end if;
      rin.rsp_index <= rsp_index;
      if rsp_i.last = '1' then
        rin.state <= ST_DECODE;
      end if;
    end if;

    case r.state is
      when ST_RESET =>
        rin.write <= true;
        rin.discard <= 0;
        rin.invalid <= 0;
        rin.gap <= 0;
        rin.state <= ST_BUSY;

      when ST_GAP =>
        if r.gap /= 0 then
          rin.gap <= r.gap - 1;
        else
          rin.state <= ST_BUSY;
        end if;

      when ST_BUSY =>
        if busy_s = '0' then
          if r.write then
            next_frame := prefix_c & control_c & unselect_c;
            rin.discard <= write_discard_c;
            rin.invalid <= 0;
            rin.write <= false;
          else
            next_frame := prefix_c & nop_c & unselect_c;
          end if;
          rin.frame <= next_frame;
          rin.cmd_index <= 0;
          rin.rsp_index <= 0;
          rin.state <= ST_SEND;
        end if;

      when ST_SEND =>
        if cmd_i.ready = '1' then
          if r.cmd_index = frame_size_c - 1 then
            if not (rsp_i.valid = '1' and rsp_i.last = '1') then
              rin.state <= ST_RECV;
            end if;
          end if;
          rin.cmd_index <= r.cmd_index + 1;
        end if;

      when ST_RECV =>
        null;

      when ST_DECODE =>
        rin.gap <= frame_gap_c;
        rin.state <= ST_GAP;

        address := to_integer(unsigned(r.word(0)(7 downto 4)));
        channel := -1;
        if address < 8 then
          channel := address;
        elsif address = 8 or address = 9 then
          channel := temperature_c;
        end if;

        if r.discard /= 0 then
          rin.discard <= r.discard - 1;
        elsif channel >= 0 and channels_c(channel) = '1' then
          rin.code(channel) <= unsigned(r.word(0)(3 downto 0)) & unsigned(r.word(1));
          rin.valid(channel) <= '1';
          rin.strobe(channel) <= '1';
          rin.invalid <= 0;
        elsif r.invalid = resync_frames_c - 1 then
          rin.write <= true;
          rin.invalid <= 0;
        else
          rin.invalid <= r.invalid + 1;
        end if;
    end case;
  end process;

  moore: process(r)
  begin
    cmd_o.valid <= '0';
    cmd_o.data <= (others => '-');
    cmd_o.last <= '-';
    rsp_o.ready <= '0';

    case r.state is
      when ST_SEND =>
        cmd_o.valid <= '1';
        cmd_o.data <= r.frame(r.cmd_index);
        if r.cmd_index = frame_size_c - 1 then
          cmd_o.last <= '1';
        else
          cmd_o.last <= '0';
        end if;
        rsp_o.ready <= '1';

      when ST_RECV =>
        rsp_o.ready <= '1';

      when others =>
        null;
    end case;
  end process;

  code_o <= r.code;
  valid_o <= r.valid;
  strobe_o <= r.strobe;

end architecture;
