library ieee;
use ieee.std_logic_1164.all;

library work, nsl_math;
use work.axi4_mm.all;
use nsl_math.arith.all;

entity axi4_mm_fifo is
  generic(
    config_c : work.axi4_mm.config_t;
    aw_depth_c : positive range 4 to positive'high;
    w_depth_c : positive range 4 to positive'high;
    b_depth_c : positive range 4 to positive'high;
    ar_depth_c : positive range 4 to positive'high;
    r_depth_c : positive range 4 to positive'high;
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

  aw: work.mm_fifo.axi4_mm_a_fifo
    generic map(
      config_c => config_c,
      depth_c => max(4, aw_depth_c),
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

  w: work.mm_fifo.axi4_mm_w_fifo
    generic map(
      config_c => config_c,
      depth_c => max(4, w_depth_c),
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

  b: work.mm_fifo.axi4_mm_b_fifo
    generic map(
      config_c => config_c,
      depth_c => max(4, b_depth_c),
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

  ar: work.mm_fifo.axi4_mm_a_fifo
    generic map(
      config_c => config_c,
      depth_c => max(4, ar_depth_c),
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

  r: work.mm_fifo.axi4_mm_r_fifo
    generic map(
      config_c => config_c,
      depth_c => max(4, r_depth_c),
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
  
end architecture;
