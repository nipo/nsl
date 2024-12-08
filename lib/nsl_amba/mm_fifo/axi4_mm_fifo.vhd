library ieee;
use ieee.std_logic_1164.all;

library work, nsl_math;
use work.axi4_mm.all;
use nsl_math.arith.all;

entity axi4_mm_fifo is
  generic(
    config_c : work.axi4_mm.config_t;
    aw_depth_c : positive;
    w_depth_c : positive;
    b_depth_c : positive;
    ar_depth_c : positive;
    r_depth_c : positive;
    clock_count_c : integer range 1 to 2 := 1
    );
  port(
    clock_i : in std_ulogic_vector(0 to clock_count_c-1);
    reset_n_i : in std_ulogic;

    slave_i : in work.axi4_mm.master_t;
    slave_o : out work.axi4_mm.slave_t;

    master_o : out work.axi4_mm.master_t;
    master_i : in work.axi4_mm.slave_t
    );
end entity;

architecture beh of axi4_mm_fifo is

  signal rclk_s: std_ulogic_vector(0 to clock_count_c-1);
  
begin

  two_clock: if clock_count_c = 2
  generate
    rclk_s(0) <= clock_i(1);
    rclk_s(1) <= clock_i(0);
  end generate;

  one_clock: if clock_count_c = 1
  generate
    rclk_s <= clock_i;
  end generate;

  aw_fifo: if aw_depth_c >= 4
  generate
    aw: work.mm_fifo.axi4_mm_a_fifo
      generic map(
        config_c => config_c,
        depth_c => aw_depth_c,
        clock_count_c => clock_count_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => slave_i.aw,
        in_o => slave_o.aw,

        out_o => master_o.aw,
        out_i => master_i.aw
        );
  end generate;

  aw_cdc: if aw_depth_c < 4 and clock_count_c = 2
  generate
    aw: work.mm_fifo.axi4_mm_a_cdc
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => slave_i.aw,
        in_o => slave_o.aw,

        out_o => master_o.aw,
        out_i => master_i.aw
        );
  end generate;

  aw_slice: if aw_depth_c < 4 and clock_count_c = 1
  generate
    aw: work.mm_fifo.axi4_mm_a_slice
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i(0),
        reset_n_i => reset_n_i,

        in_i => slave_i.aw,
        in_o => slave_o.aw,

        out_o => master_o.aw,
        out_i => master_i.aw
        );
  end generate;

  w_fifo: if w_depth_c >= 4
  generate
    w: work.mm_fifo.axi4_mm_w_fifo
      generic map(
        config_c => config_c,
        depth_c => w_depth_c,
        clock_count_c => clock_count_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => slave_i.w,
        in_o => slave_o.w,

        out_o => master_o.w,
        out_i => master_i.w
        );
  end generate;

  w_cdc: if w_depth_c < 4 and clock_count_c = 2
  generate
    w: work.mm_fifo.axi4_mm_w_cdc
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => slave_i.w,
        in_o => slave_o.w,

        out_o => master_o.w,
        out_i => master_i.w
        );
  end generate;

  w_slice: if w_depth_c < 4 and clock_count_c = 1
  generate
    w: work.mm_fifo.axi4_mm_w_slice
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i(0),
        reset_n_i => reset_n_i,

        in_i => slave_i.w,
        in_o => slave_o.w,

        out_o => master_o.w,
        out_i => master_i.w
        );
  end generate;

  b_fifo: if b_depth_c >= 4
  generate
    b: work.mm_fifo.axi4_mm_b_fifo
      generic map(
        config_c => config_c,
        depth_c => b_depth_c,
        clock_count_c => clock_count_c
        )
      port map(
        clock_i => rclk_s,
        reset_n_i => reset_n_i,

        in_i => master_i.b,
        in_o => master_o.b,

        out_o => slave_o.b,
        out_i => slave_i.b
        );
  end generate;

  b_cdc: if b_depth_c < 4 and clock_count_c = 2
  generate
    b: work.mm_fifo.axi4_mm_b_cdc
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => rclk_s,
        reset_n_i => reset_n_i,

        in_i => master_i.b,
        in_o => master_o.b,

        out_o => slave_o.b,
        out_i => slave_i.b
        );
  end generate;

  b_slice: if b_depth_c < 4 and clock_count_c = 1
  generate
    b: work.mm_fifo.axi4_mm_b_slice
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => rclk_s(0),
        reset_n_i => reset_n_i,

        in_i => master_i.b,
        in_o => master_o.b,

        out_o => slave_o.b,
        out_i => slave_i.b
        );
  end generate;

  ar_fifo: if ar_depth_c >= 4
  generate
    ar: work.mm_fifo.axi4_mm_a_fifo
      generic map(
        config_c => config_c,
        depth_c => ar_depth_c,
        clock_count_c => clock_count_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => slave_i.ar,
        in_o => slave_o.ar,

        out_o => master_o.ar,
        out_i => master_i.ar
        );
  end generate;

  ar_cdc: if ar_depth_c < 4 and clock_count_c = 2
  generate
    ar: work.mm_fifo.axi4_mm_a_cdc
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,

        in_i => slave_i.ar,
        in_o => slave_o.ar,

        out_o => master_o.ar,
        out_i => master_i.ar
        );
  end generate;

  ar_slice: if ar_depth_c < 4 and clock_count_c = 1
  generate
    ar: work.mm_fifo.axi4_mm_a_slice
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i(0),
        reset_n_i => reset_n_i,

        in_i => slave_i.ar,
        in_o => slave_o.ar,

        out_o => master_o.ar,
        out_i => master_i.ar
        );
  end generate;

  r_fifo: if r_depth_c >= 4
  generate
    r: work.mm_fifo.axi4_mm_r_fifo
      generic map(
        config_c => config_c,
        depth_c => r_depth_c,
        clock_count_c => clock_count_c
        )
      port map(
        clock_i => rclk_s,
        reset_n_i => reset_n_i,

        in_i => master_i.r,
        in_o => master_o.r,

        out_o => slave_o.r,
        out_i => slave_i.r
        );
  end generate;

  r_cdc: if r_depth_c < 4 and clock_count_c = 2
  generate
    r: work.mm_fifo.axi4_mm_r_cdc
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => rclk_s,
        reset_n_i => reset_n_i,

        in_i => master_i.r,
        in_o => master_o.r,

        out_o => slave_o.r,
        out_i => slave_i.r
        );
  end generate;

  r_slice: if r_depth_c < 4 and clock_count_c = 1
  generate
    r: work.mm_fifo.axi4_mm_r_slice
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => rclk_s(0),
        reset_n_i => reset_n_i,

        in_i => master_i.r,
        in_o => master_o.r,

        out_o => slave_o.r,
        out_i => slave_i.r
        );
  end generate;
  
end architecture;
