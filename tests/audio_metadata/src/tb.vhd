library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_audio, nsl_amba, nsl_data, nsl_simulation;
use nsl_audio.pcm.all;
use nsl_audio.pcm_stream.all;
use nsl_audio.metadata.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- Takes the bits off a stream and puts them back.
--
-- The two are checked apart rather than chained, because chained they
-- are an inverse in content and not in time: a block is only whole
-- once its last frame has gone, so what comes out of one goes against
-- the frames after the ones it came from.
entity tb is
end entity;

architecture arch of tb is

  constant framed_c: config_t := framed_config;
  constant plain_c: config_t := plain_config;

  signal clock_s, reset_n_s: std_ulogic;
  signal done_s: std_ulogic_vector(0 to 0);

  -- Taking apart
  signal ex_in_m_s, ex_out_m_s: nsl_amba.axi4_stream.master_t;
  signal ex_in_s_s, ex_out_s_s: nsl_amba.axi4_stream.slave_t;
  signal ex_block_s: std_ulogic;
  signal ex_v_s, ex_u_s, ex_c_s: block_bits_vector(0 to 1);

  -- Putting back
  signal mg_in_m_s, mg_out_m_s: nsl_amba.axi4_stream.master_t;
  signal mg_in_s_s, mg_out_s_s: nsl_amba.axi4_stream.slave_t;
  signal mg_block_valid_s, mg_block_ready_s: std_ulogic;
  signal mg_v_s, mg_u_s, mg_c_s: block_bits_vector(0 to 1);

  -- What a frame of a block holds.  Nothing here is the same from one
  -- channel or one bit to the next, so anything landing in the wrong
  -- place shows.
  function pat_v(ch, idx: natural) return std_ulogic is
  begin
    if ((idx + ch * 3) mod 5) = 0 then
      return '1';
    end if;
    return '0';
  end function;

  function pat_u(ch, idx: natural) return std_ulogic is
  begin
    if ((idx + ch) mod 3) = 0 then
      return '1';
    end if;
    return '0';
  end function;

  function pat_c(ch, idx: natural) return std_ulogic is
  begin
    if ((idx * 2 + ch) mod 7) = 0 then
      return '1';
    end if;
    return '0';
  end function;

  function pat_block(kind: natural; ch: natural) return block_bits_t is
    variable ret: block_bits_t;
  begin
    for i in 0 to block_frame_count_c-1
    loop
      case kind is
        when 0 => ret(i) := pat_v(ch, i);
        when 1 => ret(i) := pat_u(ch, i);
        when others => ret(i) := pat_c(ch, i);
      end case;
    end loop;
    return ret;
  end function;

  function pat_frame(cfg: config_t; idx: natural) return frame_t is
    variable ret: frame_t := frame_zero_c;
  begin
    for ch in 0 to 1
    loop
      ret(ch).sample := to_sample(
        to_unsigned((idx * 4 + ch * 1000) mod 65536, cfg.sample_bits),
        cfg.coding);

      if cfg.sideband_bits /= 0 then
        ret(ch).sideband(sideband_v_c) := pat_v(ch, idx);
        ret(ch).sideband(sideband_u_c) := pat_u(ch, idx);
        ret(ch).sideband(sideband_c_c) := pat_c(ch, idx);
      end if;
    end loop;
    return ret;
  end function;

  signal ex_done_s, mg_done_s: boolean := false;

begin

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration(0) => 30 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

  extract: nsl_audio.metadata.pcm_metadata_extract
    generic map(
      in_config_c => framed_c,
      out_config_c => plain_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => ex_in_m_s,
      in_o => ex_in_s_s,

      out_o => ex_out_m_s,
      out_i => ex_out_s_s,

      block_valid_o => ex_block_s,
      v_o => ex_v_s,
      u_o => ex_u_s,
      c_o => ex_c_s
      );

  ex_out_s_s <= accept(plain_c, true);

  merge: nsl_audio.metadata.pcm_metadata_merge
    generic map(
      in_config_c => plain_c,
      out_config_c => framed_c
      )
    port map(
      reset_n_i => reset_n_s,
      clock_i => clock_s,

      in_i => mg_in_m_s,
      in_o => mg_in_s_s,

      out_o => mg_out_m_s,
      out_i => mg_out_s_s,

      block_valid_i => mg_block_valid_s,
      block_ready_o => mg_block_ready_s,
      v_i => mg_v_s,
      u_i => mg_u_s,
      c_i => mg_c_s
      );

  mg_out_s_s <= accept(framed_c, true);

  -- A whole block of frames into the extractor
  ex_source: process is
  begin
    ex_in_m_s <= transfer_defaults(framed_c);

    wait until reset_n_s = '1';

    for blk in 0 to 3
    loop
      for i in 0 to block_frame_count_c-1
      loop
        ex_in_m_s <= transfer(framed_c, pat_frame(framed_c, i),
                              last => i = block_frame_count_c-1,
                              block_start => i = 0);

        loop
          wait until rising_edge(clock_s);
          exit when is_taken(framed_c, ex_in_m_s, ex_in_s_s);
        end loop;
      end loop;
    end loop;

    ex_in_m_s <= transfer_defaults(framed_c);
    wait;
  end process;

  -- Samples out unchanged, bits out whole
  ex_check: process is
    variable f: frame_t;
    variable i: natural;
    variable blocks: natural := 0;
  begin
    -- Where the stream had got to when reading started, rather than
    -- where it was assumed to be
    wait until rising_edge(clock_s)
      and is_taken(plain_c, ex_out_m_s, ex_out_s_s);
    f := frame(plain_c, ex_out_m_s);
    i := to_integer(f(0).sample(23 downto 0)) / 4;

    loop
      assert f(0).sample = pat_frame(plain_c, i)(0).sample
        and f(1).sample = pat_frame(plain_c, i)(1).sample
        report "Frame " & to_string(i)
        & " came out of the extractor with its samples changed"
        severity failure;
      assert is_last(plain_c, ex_out_m_s) = (i = block_frame_count_c-1)
        report "Frame " & to_string(i)
        & " came out with the packet boundary moved"
        severity failure;

      if i = block_frame_count_c-1 then
        i := 0;
      else
        i := i + 1;
      end if;

      wait until rising_edge(clock_s)
        and is_taken(plain_c, ex_out_m_s, ex_out_s_s);
      f := frame(plain_c, ex_out_m_s);
    end loop;
  end process;

  -- And the bits, once a block of them is whole
  ex_block_check: process is
    variable blocks: natural := 0;
  begin
    loop
      wait until rising_edge(clock_s) and ex_block_s = '1';

      for ch in 0 to 1
      loop
        assert ex_v_s(ch) = pat_block(0, ch)
          report "V of channel " & to_string(ch) & " did not come out whole"
          severity failure;
        assert ex_u_s(ch) = pat_block(1, ch)
          report "U of channel " & to_string(ch) & " did not come out whole"
          severity failure;
        assert ex_c_s(ch) = pat_block(2, ch)
          report "C of channel " & to_string(ch) & " did not come out whole"
          severity failure;
      end loop;

      blocks := blocks + 1;
      if blocks = 1 then
        ex_done_s <= true;
      end if;
    end loop;
  end process;

  -- Blocks and samples into the merger
  mg_v_s <= (pat_block(0, 0), pat_block(0, 1));
  mg_u_s <= (pat_block(1, 0), pat_block(1, 1));
  mg_c_s <= (pat_block(2, 0), pat_block(2, 1));
  mg_block_valid_s <= '1';

  mg_source: process is
  begin
    mg_in_m_s <= transfer_defaults(plain_c);

    wait until reset_n_s = '1';

    for i in 0 to 6 * block_frame_count_c - 1
    loop
      mg_in_m_s <= transfer(plain_c, pat_frame(plain_c, i mod block_frame_count_c));

      loop
        wait until rising_edge(clock_s);
        exit when is_taken(plain_c, mg_in_m_s, mg_in_s_s);
      end loop;
    end loop;

    mg_in_m_s <= transfer_defaults(plain_c);
    wait;
  end process;

  -- Which has to come out carrying both: the samples that went in,
  -- unchanged, and the block's bits against the frames of the packet
  -- the merger cut.  Those two are not the same clock: what arrives
  -- has no packets of its own, so where the merger puts its boundaries
  -- is its business and is checked as such.
  mg_check: process is
    variable f: frame_t;
    variable idx: natural;
    variable pos: natural;
    variable packets: natural := 0;
  begin
    -- Start at a packet the merger opened, and after the first one:
    -- before any block has been taken it sends whatever it started
    -- with.
    for skip in 0 to 1
    loop
      loop
        wait until rising_edge(clock_s)
          and is_taken(framed_c, mg_out_m_s, mg_out_s_s);
        exit when is_block(framed_c, mg_out_m_s);
      end loop;
    end loop;

    f := frame(framed_c, mg_out_m_s);
    -- Where the samples had got to, which is not where the packets are
    idx := to_integer(f(0).sample(23 downto 0)) / 4;
    pos := 0;

    loop
      for ch in 0 to 1
      loop
        assert f(ch).sample = pat_frame(framed_c, idx)(ch).sample
          report "Frame at " & to_string(pos) & " of a packet came through "
          & "the merger with channel " & to_string(ch) & " changed"
          severity failure;

        assert f(ch).sideband(sideband_v_c) = pat_v(ch, pos)
          and f(ch).sideband(sideband_u_c) = pat_u(ch, pos)
          and f(ch).sideband(sideband_c_c) = pat_c(ch, pos)
          report "Frame " & to_string(pos) & " of a packet carries channel "
          & to_string(ch) & "'s bits from somewhere else in the block"
          severity failure;
      end loop;

      assert is_block(framed_c, mg_out_m_s) = (pos = 0)
        report "Frame " & to_string(pos) & " states a block where there is none"
        severity failure;
      assert is_last(framed_c, mg_out_m_s) = (pos = block_frame_count_c-1)
        report "Frame " & to_string(pos) & " closes a packet where it should not"
        severity failure;

      if pos = block_frame_count_c-1 then
        pos := 0;
        packets := packets + 1;
        if packets = 1 then
          mg_done_s <= true;
        end if;
      else
        pos := pos + 1;
      end if;

      idx := (idx + 1) mod block_frame_count_c;

      wait until rising_edge(clock_s)
        and is_taken(framed_c, mg_out_m_s, mg_out_s_s);
      f := frame(framed_c, mg_out_m_s);
    end loop;
  end process;

  main: process is
  begin
    done_s <= "0";

    wait until reset_n_s = '1';
    wait until ex_done_s and mg_done_s;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
