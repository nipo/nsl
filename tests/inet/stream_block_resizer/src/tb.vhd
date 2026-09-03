library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_simulation, nsl_amba, nsl_math, nsl_inet;
use nsl_data.bytestream.all;
use nsl_data.text.all;
use nsl_simulation.assertions.all;
use nsl_simulation.logging.all;
use nsl_amba.axi4_stream.all;
use nsl_math.int_ext.all;
use nsl_inet.stream.all;

-- Block resizing between every pair of supported widths, for three
-- block layouts.  Each instance is fed a series of packets built with
-- the input-side padding and checked against a golden image built with
-- the output-side padding.
entity tb is
end tb;

architecture arch of tb is

  signal clock_s, reset_n_s : std_ulogic;
  signal done_s : std_ulogic_vector(0 to 26);

  function hdr_of(sel: integer) return integer_vector
  is
  begin
    case sel is
      when 0 => return null_integer_vector;
      when 1 => return integer_vector'(0 => 7);
      when others => return integer_vector'(0 => 5, 1 => 7, 2 => 7, 3 => 2);
    end case;
  end function;

  function content_of(idx, len: integer) return byte_string
  is
    variable ret: byte_string(0 to len-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((idx * 37 + k * 5 + 1) mod 256);
    end loop;
    return ret;
  end function;

  function payload_of(len: integer) return byte_string
  is
    variable ret: byte_string(0 to len-1);
  begin
    for k in ret'range
    loop
      ret(k) := to_byte((k * 11 + 3) mod 256);
    end loop;
    return ret;
  end function;

  -- Input length at which the packets checking the truncation path are
  -- cut: inside the first block for the single-block layout, inside the
  -- second one at width 1 and inside the first one's padding above.
  constant trunc_len_c : integer := 6;

begin

  h_gen: for hsel in 0 to 2 generate
    constant hdr_c : integer_vector := hdr_of(hsel);
  begin

    iw_gen: for iw2 in 0 to 2 generate
      ow_gen: for ow2 in 0 to 2 generate
        constant in_cfg_c : config_t := stream_config(2 ** iw2);
        constant out_cfg_c : config_t := stream_config(2 ** ow2);
        constant tag_c : string := "h" & to_string(hsel)
                                   & " i" & to_string(2 ** iw2)
                                   & " o" & to_string(2 ** ow2);

        signal in_s, out_s : bus_t;

        -- The block region, tail-padded to whole beats of cfg.
        function blocks_padded(cfg: config_t) return byte_string
        is
          variable ret: byte_string(0 to context_byte_count(cfg, hdr_c)-1);
          variable point: integer := 0;
          variable len, span: integer;
        begin
          for i in 0 to hdr_c'length-1
          loop
            len := hdr_c(hdr_c'left + i);
            span := context_byte_count(cfg, (0 => len));
            ret(point to point+span-1) := context_pad(cfg, content_of(i, len));
            point := point + span;
          end loop;
          return ret;
        end function;

        constant in_blocks_c : byte_string := blocks_padded(in_cfg_c);

        function in_pkt(payload_len: integer) return byte_string
        is
        begin
          return in_blocks_c & payload_of(payload_len);
        end function;

        function in_len(payload_len: integer) return integer
        is
        begin
          return in_blocks_c'length + payload_len;
        end function;

        function out_pkt(payload_len: integer) return byte_string
        is
        begin
          return blocks_padded(out_cfg_c) & payload_of(payload_len);
        end function;

        -- Golden model: what the output packet holds when the input
        -- packet is in_len bytes long.  Blocks whose contents complete
        -- get the output-side padding; a packet ending before its
        -- listed blocks complete keeps whatever was produced.
        function expected(in_len: integer) return byte_string
        is
          variable ret: byte_string(0 to 255);
          variable content: byte_string(0 to 255);
          variable point: integer := 0;
          variable left: integer := in_len;
          variable len, out_pad, in_pad: integer;
        begin
          for i in 0 to hdr_c'length-1
          loop
            len := hdr_c(hdr_c'left + i);
            out_pad := context_byte_count(out_cfg_c, (0 => len)) - len;
            in_pad := context_byte_count(in_cfg_c, (0 => len)) - len;
            content(0 to len-1) := content_of(i, len);

            if left < len then
              for k in 0 to left-1
              loop
                ret(point + k) := content(k);
              end loop;
              return ret(0 to point + left - 1);
            end if;

            for k in 0 to len-1
            loop
              ret(point + k) := content(k);
            end loop;
            point := point + len;
            left := left - len;

            for k in 0 to out_pad-1
            loop
              ret(point + k) := x"00";
            end loop;
            point := point + out_pad;

            if left < in_pad then
              return ret(0 to point-1);
            end if;
            left := left - in_pad;
          end loop;

          content(0 to left-1) := payload_of(left);
          for k in 0 to left-1
          loop
            ret(point + k) := content(k);
          end loop;
          return ret(0 to point + left - 1);
        end function;
      begin

        stim: process is
        begin
          in_s.m <= transfer_defaults(in_cfg_c);
          wait for 100 ns;

          -- A layout with no block has no zero-length packet to send.
          if hsel /= 0 then
            packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                        packet => in_pkt(0), user => "0");
          end if;
          packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                      packet => in_pkt(1), user => "0");
          packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                      packet => in_pkt(5), user => "0");
          packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                      packet => in_pkt(33), user => "0");

          -- Same packet, rejected then not
          packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                      packet => in_pkt(5), user => "1");
          packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                      packet => in_pkt(5), user => "0");

          -- Back to back
          packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                      packet => in_pkt(7), user => "0");
          packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                      packet => in_pkt(2), user => "0");

          if hsel /= 0 then
            packet_send(in_cfg_c, clock_s, in_s.s, in_s.m,
                        packet => in_blocks_c(0 to trunc_len_c-1),
                        user => "0");
          end if;

          wait;
        end process;

        check: process is
          variable beat_v: master_t;
          variable rx_v: byte_stream;
          variable rejected_v: boolean;

          procedure rx_pkt is
          begin
            clear(rx_v);
            loop
              receive(out_cfg_c, clock_s, out_s.m, out_s.s, beat_v);
              assert is_packed(out_cfg_c, beat_v)
                report tag_c & ": unpacked output beat"
                severity failure;
              for k in 0 to byte_count(out_cfg_c, beat_v)-1
              loop
                write(rx_v, beat_v.data(k));
              end loop;
              if is_last(out_cfg_c, beat_v) then
                rejected_v := is_rejected(out_cfg_c, beat_v);
                exit;
              end if;
            end loop;
          end procedure;

          procedure expect_pkt(constant what: string;
                               constant ref: byte_string;
                               constant rejected: boolean) is
          begin
            rx_pkt;
            assert_equal(tag_c & " " & what, rx_v.all, ref, failure);
            assert rejected_v = rejected
              report tag_c & " " & what & ": unexpected reject flag"
              severity failure;
            deallocate(rx_v);
          end procedure;
        begin
          out_s.s <= accept(out_cfg_c, false);

          -- The two ways of building the reference image must agree on
          -- every packet that is not truncated.
          assert_equal(tag_c & " model", expected(in_len(1)),
                       out_pkt(1), failure);
          assert_equal(tag_c & " model", expected(in_len(33)),
                       out_pkt(33), failure);

          wait for 100 ns;

          if hsel /= 0 then
            expect_pkt("payload 0", out_pkt(0), false);
          end if;
          expect_pkt("payload 1", out_pkt(1), false);
          expect_pkt("payload 5", out_pkt(5), false);
          expect_pkt("payload 33", out_pkt(33), false);
          expect_pkt("rejected", out_pkt(5), true);
          expect_pkt("accepted", out_pkt(5), false);
          expect_pkt("back to back 1", out_pkt(7), false);
          expect_pkt("back to back 2", out_pkt(2), false);

          if hsel /= 0 then
            expect_pkt("truncated", expected(trunc_len_c), true);
          end if;

          log_info(tag_c & " OK");
          done_s(hsel * 9 + iw2 * 3 + ow2) <= '1';
          wait;
        end process;

        dut: nsl_inet.stream.stream_block_resizer
          generic map(
            in_config_c => in_cfg_c,
            out_config_c => out_cfg_c,
            header_length_c => hdr_c
            )
          port map(
            clock_i => clock_s,
            reset_n_i => reset_n_s,

            in_i => in_s.m,
            in_o => in_s.s,

            out_o => out_s.m,
            out_i => out_s.s
            );

      end generate;
    end generate;
  end generate;

  simdrv: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 10 ns,
      reset_duration => (others => 32 ns),
      clock_o(0) => clock_s,
      reset_n_o(0) => reset_n_s,
      done_i => done_s
      );

end;
