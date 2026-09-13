library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_dvi, nsl_video, nsl_i2c, nsl_io, nsl_data, nsl_simulation;
use nsl_video.mode.all;
use nsl_video.edid.all;
use nsl_data.bytestream.all;
use nsl_data.text.all;

-- Reads a sink's EDID the way a source does: over I2C, one address
-- byte written and then bytes read back.
--
-- The bus is driven from here rather than by a master component, so
-- what is exercised is the wire protocol a source actually speaks --
-- including the two things it does that a plain memory read does not:
-- a repeated start between the address write and the read, and
-- reading the whole block in one go.
entity tb is
end entity;

architecture arch of tb is

  constant clock_hz_c: natural := 50_000_000;
  constant clock_period_c: time := 20 ns;
  -- Slow enough that the slave is never the reason a bit is missed
  constant bit_period_c: time := 2500 ns;

  constant modes_c: mode_vector(0 to 2) := (
    mode_std_640x480p60_c,
    mode_std_800x600p60_c,
    mode_std_1024x768p60_c);

  constant expected_c: edid_block_t := edid_block(
    modes => modes_c,
    manufacturer => "NSL",
    product_code => 2,
    name => "NSL Capture",
    h_size_mm => 160,
    v_size_mm => 120);

  signal clock_s, reset_n_s: std_ulogic;

  signal slave_o_s: nsl_i2c.i2c.i2c_o;
  signal bus_s: nsl_i2c.i2c.i2c_i;
  signal selected_s: std_ulogic;

  -- What the master pulls down, as an open drain does
  signal master_scl_s, master_sda_s: std_ulogic := '1';

begin

  clock_gen: process is
  begin
    clock_s <= '0';
    wait for clock_period_c / 2;
    clock_s <= '1';
    wait for clock_period_c / 2;
  end process;

  reset_gen: process is
  begin
    reset_n_s <= '0';
    wait for 10 * clock_period_c;
    reset_n_s <= '1';
    wait;
  end process;

  -- Both ends pull down, and pull-ups make the rest
  bus_s.scl <= '0' when master_scl_s = '0' or slave_o_s.scl.drain_n = '0' else 'H';
  bus_s.sda <= '0' when master_sda_s = '0' or slave_o_s.sda.drain_n = '0' else 'H';

  dut: nsl_dvi.ddc.ddc_edid_slave
    generic map(
      modes_c => modes_c,
      manufacturer_c => "NSL",
      product_code_c => 2,
      name_c => "NSL Capture",
      h_size_mm_c => 160,
      v_size_mm_c => 120
      )
    port map(
      clock_i => clock_s,
      reset_n_i => reset_n_s,

      i2c_i => bus_s,
      i2c_o => slave_o_s,

      selected_o => selected_s
      );

  main: process is
    variable got: edid_block_t;
    variable acked: boolean;

    procedure quarter is
    begin
      wait for bit_period_c / 4;
    end procedure;

    procedure bus_start is
    begin
      master_sda_s <= '1';
      master_scl_s <= '1';
      quarter;
      master_sda_s <= '0';
      quarter;
      master_scl_s <= '0';
      quarter;
    end procedure;

    procedure bus_stop is
    begin
      master_sda_s <= '0';
      quarter;
      master_scl_s <= '1';
      quarter;
      master_sda_s <= '1';
      quarter;
    end procedure;

    -- One byte out, and whether the slave acknowledged it
    procedure bus_write(constant data: byte; variable ack: out boolean) is
    begin
      for i in 7 downto 0
      loop
        master_sda_s <= data(i);
        quarter;
        master_scl_s <= '1';
        quarter;
        quarter;
        master_scl_s <= '0';
        quarter;
      end loop;

      -- Acknowledge slot, the wire left to the slave
      master_sda_s <= '1';
      quarter;
      master_scl_s <= '1';
      quarter;
      ack := bus_s.sda = '0';
      quarter;
      master_scl_s <= '0';
      quarter;
    end procedure;

    -- One byte in, acknowledged unless it is the last one wanted
    procedure bus_read(variable data: out byte; constant last: boolean) is
      variable v: byte;
    begin
      master_sda_s <= '1';
      for i in 7 downto 0
      loop
        quarter;
        master_scl_s <= '1';
        quarter;
        v(i) := to_x01(bus_s.sda);
        quarter;
        master_scl_s <= '0';
        quarter;
      end loop;

      if last then
        master_sda_s <= '1';
      else
        master_sda_s <= '0';
      end if;
      quarter;
      master_scl_s <= '1';
      quarter;
      quarter;
      master_scl_s <= '0';
      master_sda_s <= '1';
      quarter;

      data := v;
    end procedure;
  begin
    wait until reset_n_s = '1';
    wait for bit_period_c;

    assert selected_s = '0'
      report "The slave claims to be selected before anything was said"
      severity failure;

    -- A source sets the byte it wants to read from, then restarts and
    -- reads.  Address 0x50, write.
    bus_start;
    bus_write(to_byte(16#a0#), acked);
    assert acked
      report "The slave did not answer its address"
      severity failure;

    bus_write(to_byte(0), acked);
    assert acked
      report "The slave did not take the byte offset"
      severity failure;

    -- Repeated start, then address 0x50, read
    bus_start;
    bus_write(to_byte(16#a1#), acked);
    assert acked
      report "The slave did not answer a read"
      severity failure;

    for i in 0 to block_byte_count_c-1
    loop
      bus_read(got(i), i = block_byte_count_c-1);
    end loop;

    bus_stop;

    assert got = expected_c
      report "What came back over the bus is not the block that was built"
      severity failure;

    -- What a source checks first
    assert got(0) = x"00" and got(7) = x"00"
      report "Header did not come back"
      severity failure;
    assert checksum_of(got) = x"00"
      report "What came back does not sum to zero"
      severity failure;

    -- Reading from part way in gives that part, which is what a
    -- source does when it re-reads a descriptor
    bus_start;
    bus_write(to_byte(16#a0#), acked);
    bus_write(to_byte(54), acked);
    bus_start;
    bus_write(to_byte(16#a1#), acked);
    for i in 0 to 17
    loop
      bus_read(got(i), i = 17);
    end loop;
    bus_stop;

    assert got(0 to 17) = expected_c(54 to 71)
      report "Reading from an offset did not give the preferred timing"
      severity failure;

    -- An address that is not ours is left alone
    bus_start;
    bus_write(to_byte(16#a4#), acked);
    assert not acked
      report "The slave answered an address that is not its own"
      severity failure;
    bus_stop;

    nsl_simulation.control.terminate(0);
    wait;
  end process;

end architecture;
