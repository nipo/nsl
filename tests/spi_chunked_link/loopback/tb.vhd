library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_spi, nsl_bnoc, nsl_data, nsl_simulation;
use nsl_spi.spi.all;
use nsl_bnoc.testing.all;
use nsl_bnoc.framed.all;
use nsl_data.bytestream.all;
use nsl_simulation.logging.all;
use nsl_simulation.assertions.all;

-- Loopback test for the SPI chunked_link slave. A behavioral mode-3 SPI
-- master runs CS windows carrying the chunked_link protocol on MOSI (budget
-- grant, data frames, idle filler) while parsing the MISO stream (control
-- frames skipped, data frames collected). Payloads are checked in both
-- directions, including packets larger than one chunk, and each window must
-- end with the MISO parser on a frame boundary (the budget discipline keeps
-- slave frames inside the window).
entity tb is
end entity;

architecture arch of tb is

  constant half_bit_c : time := 20 ns;

  function seq(base : integer; len : integer) return byte_string is
    variable ret : byte_string(0 to len-1);
  begin
    for i in ret'range
    loop
      ret(i) := to_byte((base + i * 5) mod 256);
    end loop;
    return ret;
  end function;

  -- Budget grant frame.
  function ctl_grant(v : integer) return byte_string is
  begin
    return (0 => x"f1",
            1 => to_byte(v mod 256),
            2 => to_byte(v / 256));
  end function;

  -- Payload as chunked_link data frames, 64 bytes per frame at most.
  function data_frames(payload : byte_string) return byte_string is
    alias xp : byte_string(0 to payload'length-1) is payload;
    variable ret : byte_string(0 to payload'length + (payload'length + 63) / 64 - 1);
    variable src, dst, chunk : integer;
    variable hdr : byte;
  begin
    src := 0;
    dst := 0;
    while src < xp'length
    loop
      chunk := xp'length - src;
      if chunk > 64 then
        chunk := 64;
      end if;
      hdr := "00" & std_ulogic_vector(to_unsigned(chunk - 1, 6));
      if src + chunk = xp'length then
        hdr(6) := '1';
      end if;
      ret(dst) := hdr;
      ret(dst+1 to dst+chunk) := xp(src to src+chunk-1);
      src := src + chunk;
      dst := dst + chunk + 1;
    end loop;
    return ret;
  end function;

  signal done_s : std_ulogic_vector(0 to 0);

  shared variable stx_q, srx_q : framed_queue_root;

  signal clock_s : std_ulogic := '0';
  signal reset_n_s : std_ulogic;

  signal slave_i : spi_slave_i;
  signal slave_o : spi_slave_o;

  signal stx_bus, srx_bus : nsl_bnoc.framed.framed_bus;

begin

  master: process
    variable pstate : integer := 0; -- 0: header, >0: data bytes left, <0: operand bytes left
    variable plast : boolean := false;
    variable rx_accum : byte_stream := new byte_string(1 to 0);
    variable rx_packets : integer := 0;

    procedure parse(b : byte) is
    begin
      if pstate > 0 then
        write(rx_accum, b);
        pstate := pstate - 1;
        if pstate = 0 and plast then
          rx_packets := rx_packets + 1;
        end if;
      elsif pstate < 0 then
        pstate := pstate + 1;
      else
        if b(7) = '0' then
          pstate := to_integer(unsigned(b(5 downto 0))) + 1;
          plast := b(6) = '1';
        elsif b = x"f1" or b = x"f2" then
          pstate := -2;
        else
          -- idle, reserved: no operand.
          null;
        end if;
      end if;
    end procedure;

    procedure xfer(tx : byte) is
      variable rx : byte;
    begin
      for i in 7 downto 0
      loop
        slave_i.sck <= '0';
        slave_i.mosi <= tx(i);
        wait for half_bit_c;
        rx(i) := slave_o.miso.v;
        slave_i.sck <= '1';
        wait for half_bit_c;
      end loop;
      parse(rx);
    end procedure;

    -- One CS window: send the given MOSI stream padded with idle up to
    -- len bytes, parse every MISO byte.
    procedure window(mosi : byte_string; len : integer) is
      alias xm : byte_string(0 to mosi'length-1) is mosi;
    begin
      assert xm'length <= len
        report "window too short for its MOSI content" severity failure;
      slave_i.cs_n <= '0';
      wait for 2 * half_bit_c;
      for i in 0 to len - 1
      loop
        if i < xm'length then
          xfer(xm(i));
        else
          xfer(x"f0");
        end if;
      end loop;
      slave_i.cs_n <= '1';
      assert pstate = 0
        report "window ended with a truncated MISO frame" severity failure;
      wait for 300 ns;
    end procedure;

    variable got : byte_stream;
  begin
    done_s(0) <= '0';
    framed_queue_init(stx_q);
    framed_queue_init(srx_q);
    slave_i.cs_n <= '1';
    slave_i.sck <= '1';
    slave_i.mosi <= '0';

    wait for 1 us;

    -- Round 1: short payloads both ways.
    framed_queue_put(stx_q, seq(16#80#, 4));
    wait for 500 ns;
    window(ctl_grant(32) & data_frames(seq(16#10#, 5)), 48);

    framed_queue_get(srx_q, got);
    assert_equal("master->slave short", got.all, seq(16#10#, 5), failure);
    assert_equal("slave->master short count", rx_packets, 1, failure);
    assert_equal("slave->master short", rx_accum.all, seq(16#80#, 4), failure);

    -- Round 2: multi-chunk payloads both ways in one window.
    framed_queue_put(stx_q, seq(16#90#, 70));
    wait for 500 ns;
    window(ctl_grant(96) & data_frames(seq(16#20#, 70)), 116);

    framed_queue_get(srx_q, got);
    assert_equal("master->slave long", got.all, seq(16#20#, 70), failure);
    assert_equal("slave->master packet count", rx_packets, 2, failure);
    assert_equal("slave->master all", rx_accum.all,
                 seq(16#80#, 4) & seq(16#90#, 70), failure);

    log_info("spi chunked_link loopback OK");
    done_s(0) <= '1';
    wait;
  end process;

  stx_worker: process is
  begin
    stx_bus.req <= framed_req_idle_c;
    wait for 40 ns;
    framed_queue_master_worker(stx_bus.req, stx_bus.ack, clock_s, stx_q);
  end process;

  srx_worker: process is
  begin
    srx_bus.ack <= framed_ack_idle_c;
    wait for 40 ns;
    framed_queue_slave_worker(srx_bus.req, srx_bus.ack, clock_s, srx_q);
  end process;

  dut: nsl_spi.chunked_link.spi_chunked_link_slave
    generic map(
      rx_fifo_depth_c => 256,
      tx_fifo_depth_c => 256
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,
      spi_i => slave_i,
      spi_o => slave_o,
      tx_i => stx_bus.req,
      tx_o => stx_bus.ack,
      rx_o => srx_bus.req,
      rx_i => srx_bus.ack
      );

  driver: nsl_simulation.driver.simulation_driver
    generic map(
      clock_count => 1,
      reset_count => 1,
      done_count => done_s'length
      )
    port map(
      clock_period(0) => 5 ns,
      reset_duration(0) => 50 ns,
      reset_n_o(0) => reset_n_s,
      clock_o(0) => clock_s,
      done_i => done_s
      );

end architecture;
