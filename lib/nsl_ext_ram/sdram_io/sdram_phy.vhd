library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_io, nsl_ext_ram;
use nsl_data.bytestream.all;
use nsl_ext_ram.timing.all;
use nsl_ext_ram.dfi.all;

-- Pin logic of a single data rate SDRAM controller.
--
-- Portable, and for the same reason the SRAM one is: at the rates a
-- single data rate part runs at, a fabric needs nothing from its
-- vendor but the block that forwards a clock to a pin.  One phase and
-- one edge per controller cycle means a DFI slot maps straight onto a
-- pin, so there is no serialising to do and no strobe to place.
--
-- The forwarded clock goes out half a period behind the controller's,
-- so the part samples the pins in the middle of the window they are
-- held for.  That is half a period of setup and half of hold, and it
-- is why nothing here has a delay of its own to declare.
--
-- Write data travels with its command: a single data rate part has no
-- write latency to speak of, which is what the timing package says by
-- giving the generation a CAS write latency of zero.
--
-- Read data is caught on the falling edge, and that is not a detail.
-- A part answers its access time after the edge it was asked on and
-- holds until its output hold past the next one, so with the clock
-- forwarded half a period behind, the eye sits astride the launching
-- clock's own edges and none of them lands in it: at ten nanoseconds
-- a period, a part with 5.4 ns of access time and 2.5 ns of hold is
-- valid from 10.4 ns to 17.5 ns after the edge that launched the
-- command, while the rising edges are at 10 and at 20.  The falling
-- edge, at 15, is near enough the middle of it.
--
-- This is the same thing the DDR3 PHY needs a strobe for, in its
-- weaker form: read timing is not related to the launch clock, and
-- something else has to sample it.
--
-- Every pin this drives is the Q of a register and nothing else, and
-- a pad only takes a register in when three things hold at once:
--
--  * the register drives that pad alone, which is why the tri-state
--    control is carried one copy per pin rather than shared,
--
--  * nothing stands between the register and the pad, which is why
--    the tri-state control is held in the sense the pad's own control
--    takes rather than as an enable -- an inversion on the way out is
--    a lookup table, and a pin behind a lookup table is a pin left in
--    the fabric,
--
--  * the value register and the tri-state register beside it answer
--    to the same reset, because a pad's pair of output registers
--    share one reset input between them.  That is why the write
--    payload is reset at all: it has no state that needs clearing,
--    only a neighbour whose reset it has to match.
--
-- Miss any of the three and a pin leaves by whatever route placement
-- found, nanoseconds away from the pin beside it and somewhere else
-- again on the next build; on a source synchronous bus that spread is
-- the margin.
entity sdram_phy is
  generic(
    part_c: dram_part_t;
    timing_c: dram_timing_t;
    dfi_config_c: config_t;
    -- Controller cycles a read takes on top of the part's CAS latency:
    -- the register that puts the command on the pins, the one that
    -- captures the answer, and the flight time on the board.
    --
    -- Three suits a part whose access time runs past half a period,
    -- which is the usual case: CAS latency is chosen so that the data
    -- arrives near the end of its cycle, and the clock this PHY
    -- forwards is already half a period behind.  A part quick enough
    -- to answer inside that half period wants two, and a board slow
    -- enough to lose a cycle in flight wants four.  It is settled by
    -- sweeping it, not by arithmetic.
    capture_ck_c: natural := 2;
    -- Which edge catches the bus.  The falling one samples half a
    -- period later than the rising one, so the two together step the
    -- capture point in half periods: whole cycles from capture_ck_c,
    -- halves from here.  That is the same coarse and fine pair the
    -- DDR3 read gate needs, in its smallest form.
    capture_on_fall_c: boolean := true
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    dfi_i: in master_t;
    dfi_o: out slave_t;

    clock_o: out std_ulogic;
    cke_o: out std_ulogic;
    cs_n_o: out std_ulogic;
    ras_n_o: out std_ulogic;
    cas_n_o: out std_ulogic;
    we_n_o: out std_ulogic;
    ba_o: out unsigned;
    a_o: out unsigned;
    dqm_o: out std_ulogic_vector;
    dq_o: out nsl_io.io.tristated_vector;
    dq_i: in std_ulogic_vector
    );
end entity;

architecture beh of sdram_phy is

  constant dq_byte_c: natural := dfi_config_c.dq_byte_count;
  constant dq_bit_c: natural := dq_byte_c * 8;
  constant read_delay_c: natural := timing_c.cl + capture_ck_c;

  type regs_t is
  record
    -- Command registers, driving the pins
    cke: std_ulogic;
    cs_n: std_ulogic;
    ras_n: std_ulogic;
    cas_n: std_ulogic;
    we_n: std_ulogic;
    -- Sized to what the configuration says is meaningful, not to the
    -- worst case the record carries between blocks.
    bank: unsigned(dfi_config_c.bank_width - 1 downto 0);
    address: unsigned(dfi_config_c.address_width - 1 downto 0);

    -- Write payload, which goes out with its command
    data: std_ulogic_vector(dq_bit_c - 1 downto 0);
    mask: std_ulogic_vector(dq_byte_c - 1 downto 0);
    -- Whether the bus is left to the part this cycle, one copy per
    -- pin and asserted high, which is the sense a pad's tri-state
    -- control takes.  Held that way round so that the register's Q is
    -- the pad's control with nothing in between; an enable would have
    -- to be inverted on its way there and the inverter is what keeps
    -- the pin out of its pad.
    dq_hiz: std_ulogic_vector(dq_bit_c - 1 downto 0);

    -- Cycles a read is away from its answer reaching the controller
    expected: std_ulogic_vector(0 to read_delay_c - 1);
    capture: std_ulogic_vector(dq_i'length - 1 downto 0);
  end record;

  signal r, rin: regs_t;

  -- The bus as the falling edge found it, handed to the rising edge
  -- half a period later.
  signal caught_s: std_ulogic_vector(dq_i'length - 1 downto 0);

  signal forward_s: nsl_io.diff.diff_pair;

  -- The three rules above are what makes packing possible; on Lattice
  -- they are not what makes it happen.  LSE packs "based on timing
  -- requirements" and, asked to hold this bus to the part's own setup
  -- and hold, still leaves every one of these registers in the
  -- fabric.  Saying it outright is the documented override and costs
  -- nothing on a backend that does not know the attribute.
  attribute syn_useioff: boolean;
  attribute syn_useioff of beh: architecture is true;

  -- And the first of the three rules needs saying too: sixteen
  -- registers fed by one expression are one register as far as LSE is
  -- concerned, and one register has sixteen pads to reach.  A fanout
  -- of one is what keeps the copies apart.
  attribute syn_maxfan: integer;
  attribute syn_maxfan of r: signal is 1;

begin

  assert dfi_config_c.phase_count = 1 and dfi_config_c.edge_count = 1
    report "sdram_phy: a single data rate part has one phase and one edge"
    severity failure;

  assert dq_i'length = dq_bit_c
    report "sdram_phy: data bus is not the configured width"
    severity failure;

  assert timing_c.cwl = 0
    report "sdram_phy: this PHY sends write data with its command"
    severity failure;

  forward_s.p <= clock_i;
  forward_s.n <= not clock_i;

  forward: nsl_io.ddr.ddr_output
    port map(
      clock_i => forward_s,
      d_i => "10",
      dd_o => clock_o
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.cke <= '0';
      r.cs_n <= '1';
      r.dq_hiz <= (others => '1');
      -- The write payload has nothing to clear, and is cleared anyway:
      -- a pad's value register and its tri-state register answer to
      -- one reset input between them, so a payload left without one
      -- keeps the pins it drives out of their pads.
      r.data <= (others => '0');
      r.expected <= (others => '0');
    end if;
  end process;

  transition: process(r, dfi_i, dq_i) is
    variable slot: data_t;
  begin
    rin <= r;

    rin.cke <= dfi_i.command(0).cke;
    rin.cs_n <= dfi_i.command(0).cs_n;
    rin.ras_n <= dfi_i.command(0).ras_n;
    rin.cas_n <= dfi_i.command(0).cas_n;
    rin.we_n <= dfi_i.command(0).we_n;
    rin.bank <= bank(dfi_config_c, dfi_i.command(0));
    rin.address <= address(dfi_config_c, dfi_i.command(0));

    slot := dfi_i.wrdata(0);
    for i in 0 to dq_byte_c - 1
    loop
      if dfi_i.wrdata_en(0) = '1' then
        rin.mask(i) <= slot.mask(i);
      else
        rin.mask(i) <= '0';
      end if;

      for b in 0 to 7
      loop
        rin.data(i * 8 + b) <= slot.value(i)(b);
      end loop;
    end loop;
    rin.dq_hiz <= (others => not dfi_i.wrdata_en(0));

    rin.expected(0) <= dfi_i.rddata_en(0);
    for i in 1 to read_delay_c - 1
    loop
      rin.expected(i) <= r.expected(i - 1);
    end loop;

    rin.capture <= caught_s;
  end process;

  catch_on_fall: if capture_on_fall_c
  generate
    catch: process(clock_i) is
    begin
      if falling_edge(clock_i) then
        caught_s <= dq_i;
      end if;
    end process;
  end generate;

  catch_on_rise: if not capture_on_fall_c
  generate
    caught_s <= dq_i;
  end generate;

  moore: process(r) is
    variable word: byte_string(0 to dq_byte_c - 1);
  begin
    cke_o <= r.cke;
    cs_n_o <= r.cs_n;
    ras_n_o <= r.ras_n;
    cas_n_o <= r.cas_n;
    we_n_o <= r.we_n;
    ba_o <= resize(r.bank, ba_o'length);
    a_o <= resize(r.address, a_o'length);

    for i in 0 to dq_byte_c - 1
    loop
      dqm_o(dqm_o'low + i) <= r.mask(i);
      for b in 0 to 7
      loop
        -- The tri-state control is inverted back into an enable here
        -- because that is what the pad driver takes, and a pad driver
        -- inverts it again on its way to the silicon.  The two cancel,
        -- so what reaches the pad is the register.
        dq_o(dq_o'low + i * 8 + b)
          <= nsl_io.io.to_tristated(r.data(i * 8 + b),
                                    not r.dq_hiz(i * 8 + b));
      end loop;
      word(i) := r.capture(r.capture'low + i * 8 + 7
                           downto r.capture'low + i * 8);
    end loop;

    dfi_o <= slave_defaults(dfi_config_c);
    dfi_o.rddata <= to_data_vector(dfi_config_c, word);
    dfi_o.rddata_valid <= r.expected(read_delay_c - 1);
    dfi_o.init_complete <= '1';
  end process;

end architecture;
