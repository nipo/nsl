library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking, nsl_io, nsl_amba, nsl_data, nsl_ext_ram,
  gatecap_generated;
use nsl_clocking.pll.all;
use nsl_amba.axi4_mm.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.part.all;
use nsl_ext_ram.sdram.all;

entity boundary is
  port(
    clk: in std_ulogic;

    led: out std_ulogic_vector(4 downto 0);

    sdram_clk: out std_ulogic;
    sdram_cke: out std_ulogic;
    sdram_csn: out std_ulogic;
    sdram_rasn: out std_ulogic;
    sdram_casn: out std_ulogic;
    sdram_wen: out std_ulogic;
    sdram_ba: out std_ulogic_vector(1 downto 0);
    sdram_a: out std_ulogic_vector(12 downto 0);
    sdram_dqm: out std_ulogic_vector(1 downto 0);
    sdram_dq: inout std_logic_vector(15 downto 0)
    );
end entity;

architecture beh of boundary is

  constant board_hz_c: natural := 50000000;
  constant ram_hz_c: natural := 80000000;
  constant tck_ps_c: natural := 1000000000 / (ram_hz_c / 1000);

  -- The oscillator is already above what the PLL wants to compare at,
  -- so unlike the Spartan-6 boards there is nothing to carry it up
  -- first: one block does the whole job.
  constant ram_config_c: pll_config_t := pll_config(
    input_hz => board_hz_c,
    o0 => pll_output(ram_hz_c),
    implementation => nsl_clocking.pll_backend.pll_implementation_id("DEFAULT"));

  constant part_c: dram_part_t := w9825g6kh_c;
  constant burst_length_l2_c: natural := 3;

  -- Controller cycles between a read command leaving and its answer
  -- being taken, on top of the part's CAS latency.  Which falling
  -- edge the part's answer lands on moves with the period, so this is
  -- swept at every rung of the rate ladder rather than carried down
  -- it.  One build a value; this is the line that says which.
  constant capture_ck_c: natural := 2;
  constant axi_config_c: config_t := axi_config(part_c, burst_length_l2_c);

  -- The whole part: 4 banks of 8K rows of 512 columns, two bytes each.
  constant region_byte_l2_c: natural := 25;

  constant lane_c: natural := part_c.dq_width / 8;

  signal board_s, ram_raw_s, ram_s: std_ulogic;
  signal startup_reset_n_s, locked_s, ram_reset_n_s, walk_reset_n_s: std_ulogic;

  signal axi_s: bus_t;
  signal ready_s, busy_s, done_s, run_s: std_ulogic;
  signal error_count_s: unsigned(31 downto 0);
  signal first_error_s: unsigned(axi_config_c.address_width - 1 downto 0);

  signal ram_ba_s: unsigned(part_c.bank_count_l2 - 1 downto 0);
  signal ram_a_s: unsigned(address_width(part_c) - 1 downto 0);
  signal ram_cs_n_s, ram_ras_n_s, ram_cas_n_s, ram_we_n_s: std_ulogic;
  signal ram_dqm_s: std_ulogic_vector(lane_c - 1 downto 0);
  signal dq_out_s: nsl_io.io.tristated_vector(part_c.dq_width - 1 downto 0);
  signal dq_in_s: std_ulogic_vector(part_c.dq_width - 1 downto 0);

  signal heartbeat_s: unsigned(25 downto 0);

  -- The first word the part hands back after a walk starts, and the
  -- address it was asked for.  A part that is not driving the bus at
  -- all reads as all ones or all zeroes; one that is driving but
  -- mistimed reads as something else entirely.  The two need telling
  -- apart before any capture point is worth sweeping.
  signal first_read_s: std_ulogic_vector(15 downto 0);
  signal got_read_s: std_ulogic;

  -- Every channel of the bus the walker drives, both sides of each
  -- handshake, and the last address taken each way.  A walker that
  -- raises busy and returns nothing says no more than that through an
  -- error count; which of these stopped moving says which transfer it
  -- is waiting on, and how far into the region it got there.
  signal aw_count_s, w_count_s, b_count_s, ar_count_s: unsigned(31 downto 0);
  signal read_count_s: unsigned(31 downto 0);
  signal last_aw_s, last_ar_s:
    unsigned(axi_config_c.address_width - 1 downto 0);

  -- What left on the command pins, by kind.  A bus that stops
  -- advancing with these still moving is a part that is not
  -- answering; one that stops with these frozen is a controller that
  -- has stopped asking.
  signal act_count_s, pre_count_s, wr_count_s: unsigned(31 downto 0);
  signal rd_count_s, ref_count_s, mrs_count_s: unsigned(31 downto 0);

  -- Both sides of every handshake as they stand, rather than counted.
  -- A bus where nothing moves at all has one side of one channel
  -- waiting on the other, and no count of transfers that did not
  -- happen says which side it is.
  signal handshake_s: unsigned(9 downto 0);

begin

  board_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => clk,
      clock_o => board_s
      );

  startup_reset: nsl_clocking.reset.reset_at_startup
    port map(
      clock_i => board_s,
      reset_n_o => startup_reset_n_s
      );

  ram_pll: nsl_clocking.pll.pll_multi
    generic map(
      config_c => ram_config_c
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,
      clock_o(0) => ram_raw_s,
      locked_o => locked_s
      );

  ram_buffer: nsl_clocking.distribution.clock_buffer
    port map(
      clock_i => ram_raw_s,
      clock_o => ram_s
      );

  memory_reset: nsl_clocking.async.async_edge
    port map(
      clock_i => ram_s,
      data_i => locked_s,
      data_o => ram_reset_n_s
      );

  -- The walker stops for good once it is done, so a new walk needs it
  -- taken back to reset.  That is what the panel's control does.
  --
  -- The controller is taken back with it, and that is not a
  -- convenience.  An AXI master that is reset in the middle of a
  -- transaction leaves its slave waiting for a beat that will never
  -- come: the controller holds the commands and the payload of a
  -- transaction whose master has gone, and nothing in the protocol
  -- gets it out again.  Sharing the reset means every walk starts
  -- from the state the benches cover -- both sides out of reset
  -- together -- and costs the part's power-up sequence, about a
  -- hundred microseconds, at the front of each walk.
  walk_reset_n_s <= ram_reset_n_s and run_s;

  tester: nsl_amba.mm_traffic.axi4_mm_memory_tester
    generic map(
      config_c => axi_config_c,
      region_byte_l2_c => region_byte_l2_c,
      burst_length_c => 2 ** burst_length_l2_c,
      seed_c => 20260915,
      scramble_c => false
      )
    port map(
      clock_i => ram_s,
      reset_n_i => walk_reset_n_s,
      start_i => '1',
      axi_o => axi_s.m,
      axi_i => axi_s.s,
      busy_o => busy_s,
      done_o => done_s,
      error_count_o => error_count_s,
      first_error_address_o => first_error_s
      );

  controller: nsl_ext_ram.sdram.axi4_mm_sdram
    generic map(
      part_c => part_c,
      tck_ps_c => tck_ps_c,
      axi_config_c => axi_config_c,
      burst_length_l2_c => burst_length_l2_c,
      capture_ck_c => capture_ck_c
      )
    port map(
      clock_i => ram_s,
      reset_n_i => walk_reset_n_s,

      axi_i => axi_s.m,
      axi_o => axi_s.s,

      ready_o => ready_s,

      ram_clock_o => sdram_clk,
      ram_cke_o => sdram_cke,
      ram_cs_n_o => ram_cs_n_s,
      ram_ras_n_o => ram_ras_n_s,
      ram_cas_n_o => ram_cas_n_s,
      ram_we_n_o => ram_we_n_s,
      ram_ba_o => ram_ba_s,
      ram_a_o => ram_a_s,
      ram_dqm_o => ram_dqm_s,
      ram_dq_o => dq_out_s,
      ram_dq_i => dq_in_s
      );

  -- The command pins are read as well as driven: what the part was
  -- asked for is counted off the pins themselves, on this side of the
  -- registers that carry them.
  sdram_csn <= ram_cs_n_s;
  sdram_rasn <= ram_ras_n_s;
  sdram_casn <= ram_cas_n_s;
  sdram_wen <= ram_we_n_s;

  sdram_ba <= std_ulogic_vector(ram_ba_s);
  sdram_a <= std_ulogic_vector(ram_a_s);
  sdram_dqm <= ram_dqm_s;

  -- The pads are resolved here rather than through
  -- nsl_io.io.tristated_vector_io_driver: GHDL synthesis does not
  -- carry an inout across a hierarchy boundary.  A child's inout port
  -- becomes an internal wire, the pin is emitted as an output, and
  -- what the fabric reads back is its own drive instead of what the
  -- part put on the wire.  Both halves of the bus die silently.
  dq_pads: for i in 0 to part_c.dq_width - 1
  generate
    sdram_dq(i) <= std_logic(dq_out_s(i).v) when dq_out_s(i).en = '1' else 'Z';
    dq_in_s(i) <= to_x01(sdram_dq(i));
  end generate;

  observer: gatecap_generated.sdram_walk.sdram_walk_core
    generic map(
      burst_length_l2_c => 6
      )
    port map(
      clock_i => board_s,
      reset_n_i => startup_reset_n_s,

      rates_board_i => board_s,
      rates_ram_i => ram_s,

      panel_clock_i => ram_s,
      panel_reset_n_i => ram_reset_n_s,
      panel_run_o => run_s,
      panel_ready_i => ready_s,
      panel_busy_i => busy_s,
      panel_done_i => done_s,
      panel_error_count_i => error_count_s,
      panel_first_error_address_i => first_error_s,
      panel_first_read_i => unsigned(first_read_s),
      panel_read_count_i => read_count_s,
      panel_aw_count_i => aw_count_s,
      panel_w_count_i => w_count_s,
      panel_b_count_i => b_count_s,
      panel_ar_count_i => ar_count_s,
      panel_last_aw_i => last_aw_s,
      panel_last_ar_i => last_ar_s,
      panel_act_count_i => act_count_s,
      panel_pre_count_i => pre_count_s,
      panel_wr_count_i => wr_count_s,
      panel_rd_count_i => rd_count_s,
      panel_ref_count_i => ref_count_s,
      panel_mrs_count_i => mrs_count_s,
      panel_handshake_i => handshake_s
      );

  snoop: process(ram_s, ram_reset_n_s) is
    variable word: nsl_data.bytestream.byte_string(0 to lane_c - 1);
  begin
    if ram_reset_n_s = '0' then
      first_read_s <= (others => '0');
      got_read_s <= '0';
      read_count_s <= (others => '0');
    elsif rising_edge(ram_s) then
      if run_s = '0' then
        got_read_s <= '0';
        read_count_s <= (others => '0');
      elsif is_valid(axi_config_c, axi_s.s.r)
        and is_ready(axi_config_c, axi_s.m.r) then
        read_count_s <= read_count_s + 1;
        if got_read_s = '0' then
          word := bytes(axi_config_c, axi_s.s.r)(0 to lane_c - 1);
          first_read_s <= word(1) & word(0);
          got_read_s <= '1';
        end if;
      end if;
    end if;
  end process;

  -- Both sides of every channel, so that a transfer counted here is
  -- one that happened rather than one that was offered.
  traffic: process(ram_s, ram_reset_n_s) is
  begin
    if ram_reset_n_s = '0' then
      aw_count_s <= (others => '0');
      w_count_s <= (others => '0');
      b_count_s <= (others => '0');
      ar_count_s <= (others => '0');
      last_aw_s <= (others => '0');
      last_ar_s <= (others => '0');
    elsif rising_edge(ram_s) then
      if run_s = '0' then
        aw_count_s <= (others => '0');
        w_count_s <= (others => '0');
        b_count_s <= (others => '0');
        ar_count_s <= (others => '0');
        last_aw_s <= (others => '0');
        last_ar_s <= (others => '0');
      else
        if is_valid(axi_config_c, axi_s.m.aw)
          and is_ready(axi_config_c, axi_s.s.aw) then
          aw_count_s <= aw_count_s + 1;
          last_aw_s <= address(axi_config_c, axi_s.m.aw);
        end if;

        if is_valid(axi_config_c, axi_s.m.w)
          and is_ready(axi_config_c, axi_s.s.w) then
          w_count_s <= w_count_s + 1;
        end if;

        if is_valid(axi_config_c, axi_s.s.b)
          and is_ready(axi_config_c, axi_s.m.b) then
          b_count_s <= b_count_s + 1;
        end if;

        if is_valid(axi_config_c, axi_s.m.ar)
          and is_ready(axi_config_c, axi_s.s.ar) then
          ar_count_s <= ar_count_s + 1;
          last_ar_s <= address(axi_config_c, axi_s.m.ar);
        end if;
      end if;
    end if;
  end process;

  handshake: process(axi_s) is
  begin
    handshake_s <= (others => '0');

    if is_valid(axi_config_c, axi_s.m.aw) then
      handshake_s(0) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.s.aw) then
      handshake_s(1) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.m.w) then
      handshake_s(2) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.s.w) then
      handshake_s(3) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.s.b) then
      handshake_s(4) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.m.b) then
      handshake_s(5) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.m.ar) then
      handshake_s(6) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.s.ar) then
      handshake_s(7) <= '1';
    end if;
    if is_valid(axi_config_c, axi_s.s.r) then
      handshake_s(8) <= '1';
    end if;
    if is_ready(axi_config_c, axi_s.m.r) then
      handshake_s(9) <= '1';
    end if;
  end process;

  -- The command the pins carried, decoded as the part decodes it.
  --
  -- Counted from reset rather than from the run, which the channel
  -- counters above are not: the power-up script's own commands and
  -- whatever the part was asked for before a host arrived are in
  -- these, and that is the point of them.  A walk that asks for
  -- nothing is read against what the controller did before it.
  command_watch: process(ram_s, ram_reset_n_s) is
    variable code: std_ulogic_vector(2 downto 0);
  begin
    if ram_reset_n_s = '0' then
      act_count_s <= (others => '0');
      pre_count_s <= (others => '0');
      wr_count_s <= (others => '0');
      rd_count_s <= (others => '0');
      ref_count_s <= (others => '0');
      mrs_count_s <= (others => '0');
    elsif rising_edge(ram_s) then
      code := ram_ras_n_s & ram_cas_n_s & ram_we_n_s;
      if ram_cs_n_s = '0' then
        case code is
          when "011" =>
            act_count_s <= act_count_s + 1;

          when "010" =>
            pre_count_s <= pre_count_s + 1;

          when "100" =>
            wr_count_s <= wr_count_s + 1;

          when "101" =>
            rd_count_s <= rd_count_s + 1;

          when "001" =>
            ref_count_s <= ref_count_s + 1;

          when "000" =>
            mrs_count_s <= mrs_count_s + 1;

          when others =>
            null;
        end case;
      end if;
    end if;
  end process;

  -- Enough to tell a running board from a dead one without a host.
  heartbeat: process(ram_s, ram_reset_n_s)
  begin
    if ram_reset_n_s = '0' then
      heartbeat_s <= (others => '0');
    elsif rising_edge(ram_s) then
      heartbeat_s <= heartbeat_s + 1;
    end if;
  end process;

  led(0) <= heartbeat_s(heartbeat_s'left);
  led(1) <= ready_s;
  led(2) <= busy_s;
  led(3) <= done_s;
  led(4) <= '1' when error_count_s /= 0 else '0';

end architecture;
