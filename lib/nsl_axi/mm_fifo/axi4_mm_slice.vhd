library ieee;
use ieee.std_logic_1164.all;

library work;
use work.axi4_mm.all;

entity axi4_mm_slice is
  generic(
    config_c : work.axi4_mm.config_t
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    slave_i : in work.axi4_mm.master_t;
    slave_o : out work.axi4_mm.slave_t;

    master_o : out work.axi4_mm.master_t;
    master_i : in work.axi4_mm.slave_t
    );
end entity;

architecture beh of axi4_mm_slice is
  
begin

  aw: work.mm_fifo.axi4_mm_a_slice
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

  w: work.mm_fifo.axi4_mm_w_slice
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

  b: work.mm_fifo.axi4_mm_b_slice
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => master_i.b,
      in_o => master_o.b,

      out_o => slave_o.b,
      out_i => slave_i.b
      );

  ar: work.mm_fifo.axi4_mm_a_slice
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

  r: work.mm_fifo.axi4_mm_r_slice
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      in_i => master_i.r,
      in_o => master_o.r,

      out_o => slave_o.r,
      out_i => slave_i.r
      );
  
end architecture;
