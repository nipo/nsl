-- This module is in charge of formatting data from core. It discards 
-- all synchronization and halfword synchronisation packets after the
-- start of a frame is found.

-- Author: Sebastien Cerdan sebcerdan@gmail.com

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library nsl;
use nsl.framed.all;

library hwdep;
use hwdep.fifo.all;

entity tpiu_unformatter is
  generic(
    test        : boolean := false;       -- Send an incremented value instead of retrieved data
    trace_width : positive range 1 to 32  -- Data width of trace data
    );
  port(
    p_resetn    : in  std_ulogic;                                 --* asynchronous active low reset
    p_traceclk  : in  std_ulogic;                                 --* clock
    p_clk       : in  std_ulogic;                                 --* clock
    p_overflow  : out std_ulogic;                                 --* Command/data fifo full 
    p_sync      : out std_ulogic;                                 --* Synchronization is done 
    p_tracedata : in  std_ulogic_vector(2 * trace_width - 1 downto 0); --* input  data
    p_out_val   : out nsl.framed.framed_req;
    p_out_ack   : in  nsl.framed.framed_ack
    );

end entity tpiu_unformatter;

architecture rtl of tpiu_unformatter is

  constant FRAME_SYNC_WORD       : std_ulogic_vector(31 downto 0) := X"7FFFFFFF";
  constant FRAME_SYNC_HWORD      : std_ulogic_vector(15 downto 0) := X"7FFF";
  constant FRAME_WIDTH           : integer := 128;
  constant MAXLENWIDTH           : integer := 8;

  signal synchronised   : boolean;
  signal auxiliary      : std_ulogic_vector(7 downto 0);
  signal frame_data     : std_ulogic_vector(FRAME_WIDTH - 1 downto 0);
  signal frame_valid    : std_ulogic_vector(15 downto 0);
  signal filt_data      : std_ulogic_vector(31 + trace_width downto 0);
  signal filt_valid     : std_ulogic_vector(31 + trace_width downto 0);
  signal pid            : std_ulogic;
  signal fifo_cnt       : unsigned(MAXLENWIDTH - 1 downto 0);
  signal next_id        : std_ulogic_vector(6 downto 0);
  signal curr_id        : std_ulogic_vector(6 downto 0);
  signal frame_idx      : unsigned(3 downto 0);
  signal filt_idx       : unsigned(3 downto 0);

  signal cmd_wen        : std_ulogic;
  signal cmd_ren        : std_ulogic;
  signal cmd_din        : std_ulogic_vector(15 downto 0);
  signal cmd_dout       : std_ulogic_vector(15 downto 0);
  signal cmd_ready     : std_ulogic;
  signal cmd_valid    : std_ulogic;

  signal data_wen       : std_ulogic;
  signal data_ren       : std_ulogic;
  signal data_din       : std_ulogic_vector(7 downto 0);
  signal data_dout      : std_ulogic_vector(7 downto 0);
  signal data_ready    : std_ulogic;
  signal data_valid   : std_ulogic;

  type state_type is (STATE_RESET, STATE_WAIT_CMD, STATE_PUT_TAG, STATE_DATA);
  signal state: state_type;
  signal tag  : std_ulogic_vector(7 downto 0);
  signal cnt  : unsigned(MAXLENWIDTH - 1 downto 0);

  signal offset         : integer range 0 to trace_width;

begin

  fcmd: hwdep.fifo.fifo_2p
    generic map(
      data_width => 16,
      depth => 1024,
      clk_count => 2
      )
    port map(
      reset_n_i => p_resetn,
      clk_i(0) => p_traceclk,
      clk_i(1) => p_clk,

      out_data_o => cmd_dout,
      out_ready_i => cmd_ren,
      out_valid_o => cmd_valid,

      in_valid_i => cmd_wen,
      in_ready_o => cmd_ready,
      in_data_i => cmd_din
      );

  fdata: hwdep.fifo.fifo_2p
    generic map(
      data_width => 8,
      depth => 1024,
      clk_count => 2
      )
    port map(
      reset_n_i => p_resetn,
      clk_i(0) => p_traceclk,
      clk_i(1) => p_clk,

      out_data_o => data_dout,
      out_ready_i => data_ren,
      out_valid_o => data_valid,

      in_valid_i => data_wen,
      in_ready_o => data_ready,
      in_data_i => data_din
      );

  p_sync <= '1' when synchronised else '0';

  filter : process(p_traceclk, p_resetn)
    variable filt_data_v   : std_ulogic_vector(31 + trace_width downto 0);
    variable filt_valid_v  : std_ulogic_vector(31 + trace_width downto 0);
    variable idx           : unsigned(3 downto 0);
  begin

    if (p_resetn = '0') then
      
      filt_data    <= (others => '0');
      filt_valid   <= (others => '0');
      synchronised <= false;
      offset       <= 0;
      filt_idx     <= (others => '0');

    elsif rising_edge(p_traceclk) then

      filt_data_v  := std_ulogic_vector(SHIFT_RIGHT(unsigned(filt_data), 2*trace_width));
      filt_valid_v := std_ulogic_vector(SHIFT_RIGHT(unsigned(filt_valid), 2*trace_width));

      filt_data_v(31 + trace_width - offset downto 32 - trace_width - offset) := p_tracedata;

      if not synchronised then 
        -- Not yet syncronised
        filt_valid_v(31 + trace_width downto 32 - trace_width) := (others => '0');
        if filt_data_v(31 downto 0) = FRAME_SYNC_WORD then 
          filt_valid_v(31 + trace_width downto 32 - trace_width) := (others => '1');
          offset <= 0;
          synchronised <= true;
        elsif filt_data_v(31 + trace_width downto trace_width) = FRAME_SYNC_WORD then 
          offset <= trace_width;
          synchronised <= true;
        end if;
      else
        filt_valid_v(31 downto 32 - 2*trace_width) := (others => '1');
        idx := filt_idx + 2*trace_width;
        if idx = 0 then
          if filt_data_v(31 downto 0) = FRAME_SYNC_WORD then
            -- Halfword synchronization packet detection
            filt_valid_v(31 downto 0) := (others => '0');
          end if;
          if filt_data_v(31 downto 16) = FRAME_SYNC_HWORD then
            -- Word synchronization packet detection
            filt_valid_v(31 downto 16) := (others => '0');
          end if;
        end if;
        filt_idx <= idx;
      end if;

      filt_data  <= filt_data_v;
      filt_valid <= filt_valid_v;

    end if;

  end process filter;

  framer : process(p_traceclk, p_resetn)

    variable frame_data_v  : std_ulogic_vector(FRAME_WIDTH - 1 downto 0);
    variable frame_valid_v : std_ulogic_vector(15 downto 0);

  begin

    if p_resetn = '0' then
      
      frame_valid  <= (others => '0');
      frame_data   <= (others => '0');
      frame_idx    <= (others => '0');
      auxiliary    <= (others => '0');

    elsif rising_edge(p_traceclk) then
      frame_valid_v := frame_valid;
      frame_data_v  := frame_data;

      frame_valid_v(0) := '0';

      if filt_valid(7 downto 0) = X"FF" then
        -- One byte is ready

        frame_valid_v := std_ulogic_vector(shift_right(unsigned(frame_valid_v), 1));
        frame_data_v  := std_ulogic_vector(shift_right(unsigned(frame_data_v), 8));

        frame_valid_v(15) := '1';
        frame_data_v(FRAME_WIDTH - 1 downto FRAME_WIDTH - 8) := filt_data(7 downto 0);

        if frame_idx = 15 then
          -- byte of auxiliary bits
          frame_valid_v(15) := '0';
          auxiliary <= filt_data(7 downto 0);
        end if;

        frame_idx <= frame_idx + 1;

      end if;

      frame_valid <= frame_valid_v;
      frame_data <= frame_data_v;

    end if;

  end process framer;

  fullp : process(p_traceclk, p_resetn)
  begin
    if p_resetn = '0' then
      p_overflow <= '0';
    elsif rising_edge(p_traceclk) and synchronised and (cmd_ready = '0' or data_ready = '0') then
      p_overflow <= '1';
    end if;
  end process fullp;

  splitter : process(p_traceclk, p_resetn)
    variable bit_idx_v   : natural range 0 to 7;
    variable data_en_v   : boolean;
    variable data_v      : std_ulogic_vector(7 downto 0);
    variable nullid      : std_ulogic;
  begin
    if p_resetn = '0' then
      curr_id   <= (others => '0');
      next_id   <= (others => '0');
      fifo_cnt  <= (others => '0');
      data_din  <= (others => '0');
      cmd_din   <= (others => '0');
      pid       <= '0';
      cmd_wen   <= '0';
      data_wen  <= '0';

    elsif rising_edge(p_traceclk) then
      data_en_v   := false;
      data_v      := (others => '0');
      cmd_wen     <= '0';
      data_wen    <= '0';
      nullid      := '0';

      if curr_id = (curr_id'range => '0') then 
        -- Discard null id and associated data
        nullid    := '1';
      end if;

      if frame_valid(0) = '1' then
        -- A new byte is available
        bit_idx_v := to_integer(frame_idx(3 downto 1));

        assert not(frame_idx = 14 and frame_data(0) = '1' and auxiliary(bit_idx_v) = '1')
          report "Auxiliary bit of byte 14 must be zero when new ID"
          severity failure;

        if frame_idx(0) = '1' then 
          -- This is always a data
          data_en_v := true;
          data_v    := frame_data(7 downto 0);

        elsif frame_data(0) = '0' then
          -- Start of an halfword
          -- This byte is a data byte
          data_en_v := true;
          data_v    := frame_data(7 downto 1) & auxiliary(bit_idx_v);

        elsif curr_id /= frame_data(7 downto 1) then
          -- This byte is a new id
          if auxiliary(bit_idx_v) = '0' then
            -- The new ID takes effect immediately
            curr_id <= frame_data(7 downto 1);
            if fifo_cnt > 0 then 
              cmd_wen   <= not nullid;
              cmd_din   <= '0' &  curr_id & std_ulogic_vector(fifo_cnt - 1);
              fifo_cnt  <= (others => '0');
            end if;
          else
            -- The new ID takes effect after next data byte
            pid       <= '1';
            next_id   <= frame_data(7 downto 1);
          end if;
        end if;
      end if;
      
      if data_en_v then
        fifo_cnt <= fifo_cnt + 1;
        if fifo_cnt = 2**MAXLENWIDTH - 1 or pid = '1' then
          cmd_wen <= not nullid;
          cmd_din <= '0' & curr_id & std_ulogic_vector(fifo_cnt);
          if pid = '1' then
            -- A new id was pending
            fifo_cnt  <= (others => '0');
            pid       <= '0';
            curr_id   <= next_id;
          end if;
        end if;
        data_wen <= not nullid;
        if test then
          data_din <= std_ulogic_vector(fifo_cnt);
        else
          data_din <= data_v;
        end if;
      end if;
    end if;

  end process splitter;

  outdata : process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      state     <= STATE_RESET;
    elsif rising_edge(p_clk) then
      case state is
        when STATE_RESET =>
          state <= STATE_WAIT_CMD;

        when STATE_WAIT_CMD =>
          if cmd_valid = '1' then
            -- A new command is available
            cnt     <= unsigned(cmd_dout(MAXLENWIDTH - 1 downto 0));
            tag     <= cmd_dout(15 downto 8);
            state   <= STATE_PUT_TAG;
          end if;
          
        when STATE_PUT_TAG =>
          if p_out_ack.ready = '1' then
            state   <= STATE_DATA;
          end if;
          
        when STATE_DATA =>
          if data_valid = '1' and p_out_ack.ready = '1' then
            if cnt = 0 then 
              state <= STATE_WAIT_CMD;
            end if;
            cnt <= cnt - 1;
          end if;
      end case;
    end if;
  end process outdata;

  mux : process(state, cmd_valid, cmd_dout, data_valid, data_dout, p_out_ack, tag, cnt)
  begin
    case state is
      when STATE_RESET =>
        p_out_val.valid <= '0';
        p_out_val.data  <= (others => '-');
        p_out_val.last <= '-';
        data_ren <= '0';
        cmd_ren <= '0';

      when STATE_WAIT_CMD =>
        p_out_val.valid <= '0';
        p_out_val.data  <= (others => '-');
        p_out_val.last <= '-';
        data_ren <= '0';
        cmd_ren <= '1';

      when STATE_PUT_TAG => 
        p_out_val.valid <= '1';
        p_out_val.data <= tag;
        p_out_val.last <= '0';
        data_ren <= '0';
        cmd_ren <= '0';

      when STATE_DATA => 
        p_out_val.valid <= data_valid;
        p_out_val.data <= data_dout;
        if cnt = 0 then
          p_out_val.last <= '1';
        else
          p_out_val.last <= '0';
        end if;
        data_ren <= p_out_ack.ready;
        cmd_ren <= '0';

    end case;
  end process mux;

end architecture rtl;
