library ieee;
use ieee.std_logic_1164.all;

library nsl_ext_ram;
use nsl_ext_ram.timing.all;

-- Datasheet timings and geometry of the memory devices NSL has been
-- used with.  Nothing here is logic: each constant is a transcription
-- of one datasheet, to be handed to nsl_ext_ram.timing.timings().
package part is

  -- Hynix H5TQ4G63EFR, 4Gbit DDR3 SDRAM, 256M x 16.
  --
  -- Timings are those of the DDR3-800E speed bin.  The part carries a
  -- faster grade, so honouring the slowest bin is conservative on
  -- every parameter; revisit when running above 800 MT/s.
  --
  -- A16 exists on the package but is a no-connect at this density.
  constant h5tq4g63efr_c: dram_part_t := (
    generation => DRAM_DDR3,

    bank_count_l2 => 3,
    row_count_l2 => 15,
    column_count_l2 => 10,
    dq_width => 16,
    prefetch_l2 => 3,

    tck_min_ps => 2500,
    tck_max_ps => 3300,

    aa_ps => 15000,
    rcd_ps => 15000,
    rp_ps => 15000,
    ras_ps => 37500,
    rc_ps => 52500,
    -- 2KB page
    rrd_ps => 10000,
    rrd_min_ck => 4,
    faw_ps => 50000,
    ccd_min_ck => 4,

    wr_ps => 15000,
    wr_min_ck => 0,
    wtr_ps => 7500,
    wtr_min_ck => 4,
    rtp_ps => 7500,
    rtp_min_ck => 4,

    rfc_ps => 300000,
    refi_ps => 7800000,

    mrd_min_ck => 4,
    mod_ps => 15000,
    mod_min_ck => 12,

    init_reset_ps => 200000000,
    init_cke_ps => 500000000,
    zqinit_min_ck => 512
    );

  -- Alliance Memory AS4C128M8D3LB, 1Gbit DDR3L SDRAM, 128M x 8.
  --
  -- Transcribed from the -12 column of the AS4C128M8D3LB-12BIN /
  -- -12BCN datasheet, Rev. 1.0, January 2018.  That column is the only
  -- one the sheet carries: the part is a DDR3L-1600 grade, and its
  -- delays are the ones honoured at any slower clock the range allows.
  --
  -- A10 and A12 carry auto-precharge and burst chop, leaving A0-A13 as
  -- fourteen row address bits and A0-A9 as ten column bits.
  constant as4c128m8d3lb_c: dram_part_t := (
    generation => DRAM_DDR3,

    bank_count_l2 => 3,
    row_count_l2 => 14,
    column_count_l2 => 10,
    dq_width => 8,
    prefetch_l2 => 3,

    tck_min_ps => 1250,
    -- The slowest period any CAS latency the sheet tabulates allows
    tck_max_ps => 3300,

    aa_ps => 13750,
    rcd_ps => 13750,
    rp_ps => 13750,
    ras_ps => 35000,
    rc_ps => 48750,
    -- 1KB page
    rrd_ps => 6000,
    rrd_min_ck => 4,
    faw_ps => 30000,
    ccd_min_ck => 4,

    wr_ps => 15000,
    wr_min_ck => 0,
    wtr_ps => 7500,
    wtr_min_ck => 4,
    rtp_ps => 7500,
    rtp_min_ck => 4,

    rfc_ps => 110000,
    refi_ps => 7800000,

    mrd_min_ck => 4,
    mod_ps => 15000,
    mod_min_ck => 12,

    init_reset_ps => 200000000,
    init_cke_ps => 500000000,
    zqinit_min_ck => 512
    );

  -- Winbond W9825G6KH, 256Mbit SDR SDRAM, 4M x 4 banks x 16.
  --
  -- Timings are those of the -6 speed grade, CAS latency 3.
  constant w9825g6kh_c: dram_part_t := (
    generation => DRAM_SDR,

    bank_count_l2 => 2,
    row_count_l2 => 13,
    column_count_l2 => 9,
    dq_width => 16,
    prefetch_l2 => 0,

    tck_min_ps => 6000,
    -- No lower bound in the datasheet, the part is static apart from
    -- refresh.  This is a sanity limit, not a device property.
    tck_max_ps => 20000,

    aa_ps => 18000,
    rcd_ps => 18000,
    rp_ps => 18000,
    ras_ps => 42000,
    rc_ps => 60000,
    rrd_ps => 12000,
    rrd_min_ck => 2,
    -- No activate window on SDR
    faw_ps => 0,
    ccd_min_ck => 1,

    wr_ps => 12000,
    wr_min_ck => 2,
    -- Read follows write with no bus turnaround penalty
    wtr_ps => 0,
    wtr_min_ck => 0,
    rtp_ps => 0,
    rtp_min_ck => 0,

    rfc_ps => 60000,
    -- 8192 rows in 64 ms
    refi_ps => 7812500,

    mrd_min_ck => 2,
    mod_ps => 0,
    mod_min_ck => 0,

    -- No reset pin
    init_reset_ps => 0,
    init_cke_ps => 100000000,
    -- No ZQ pin
    zqinit_min_ck => 0
    );

  -- Cypress CY7C1462AV25, 36Mbit pipelined NoBL SRAM, 2M x 18.
  --
  -- Transcribed from the -200 speed grade column of document
  -- 38-05354 Rev. *D.  Two of the eighteen bits are parity, one per
  -- byte lane, written and read with the lane they belong to.
  --
  -- Both latencies are two: a read command puts its data on the bus
  -- two clock rises later, and a write command has its data taken from
  -- the bus two clock rises later.  That symmetry is what "no bus
  -- latency" names, and it means a read may follow a write with
  -- nothing between them.
  constant cy7c1462av25_c: sram_part_t := (
    address_width => 21,
    dq_byte_count => 2,
    has_parity => true,

    read_latency_ck => 2,
    write_latency_ck => 2,

    tck_min_ps => 5000,
    ch_ps => 2000,
    cl_ps => 2000,

    co_ps => 3200,
    doh_ps => 1500,
    chz_ps => 3000,
    clz_ps => 1300,
    eov_ps => 3000,
    eohz_ps => 3000,
    eolz_ps => 0,

    as_ps => 1400,
    ds_ps => 1400,
    cens_ps => 1400,
    wes_ps => 1400,
    ces_ps => 1400,

    ah_ps => 400,
    dh_ps => 400,
    cenh_ps => 400,
    weh_ps => 400,
    ceh_ps => 400,

    power_ps => 1000000000
    );

end package part;
