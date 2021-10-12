library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_math, nsl_line_coding, nsl_data, work;
use work.encoder.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;

entity dvi_10_encoder is
  port(
    reset_n_i : in std_ulogic;
    pixel_clock_i : in std_ulogic;

    v_fp_m1_i : in unsigned;
    v_sync_m1_i : in unsigned;
    v_bp_m1_i : in unsigned;
    v_act_m1_i : in unsigned;

    h_fp_m1_i : in unsigned;
    h_sync_m1_i : in unsigned;
    h_bp_m1_i : in unsigned;
    h_act_m1_i : in unsigned;

    vsync_i : in std_ulogic := '1';
    hsync_i : in std_ulogic := '1';
    
    sof_o : out std_ulogic;
    sol_o : out std_ulogic;
    pixel_ready_o : out std_ulogic;
    pixel_i : in nsl_color.rgb.rgb24;
    
    tmds_o : out work.dvi.symbol_vector_t
    );
end entity;

architecture beh of dvi_10_encoder is

  constant h_width_c : integer := nsl_math.arith.max(
    h_fp_m1_i'length, nsl_math.arith.max(
    h_sync_m1_i'length, nsl_math.arith.max(
    h_bp_m1_i'length, h_act_m1_i'length)));
  constant v_width_c : integer := nsl_math.arith.max(
    v_fp_m1_i'length, nsl_math.arith.max(
    v_sync_m1_i'length, nsl_math.arith.max(
    v_bp_m1_i'length, v_act_m1_i'length)));

  subtype h_count_t is unsigned(h_width_c-1 downto 0);
  subtype v_count_t is unsigned(v_width_c-1 downto 0);
  
  type state_t is (
    ST_FP,
    ST_SYNC,
    ST_BP,
    ST_ACT
    );

  type regs_t is
  record
    v_left : v_count_t;
    v_state: state_t;

    h_left : h_count_t;
    h_state: state_t;
  end record;
  
  signal r, rin : regs_t;

  signal period_s : period_t;

  signal hsync_s, vsync_s: std_ulogic;
  
begin

  regs: process(pixel_clock_i, reset_n_i) is
  begin
    if rising_edge(pixel_clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.h_state <= ST_ACT;
      r.h_left <= (others => '0');
      r.v_state <= ST_ACT;
      r.v_left <= (others => '0');
    end if;
  end process;
  
  transition: process(r,
                      h_fp_m1_i,
                      h_sync_m1_i,
                      h_bp_m1_i,
                      h_act_m1_i,
                      v_fp_m1_i,
                      v_sync_m1_i,
                      v_bp_m1_i,
                      v_act_m1_i) is
    variable v_next: boolean;
  begin
    rin <= r;

    v_next := false;

    case r.h_state is
      when ST_FP =>
        if r.h_left /= 0 then
          rin.h_left <= r.h_left - 1;
        else
          rin.h_left <= resize(h_sync_m1_i, h_width_c);
          rin.h_state <= ST_SYNC;
          v_next := true;
        end if;

      when ST_SYNC =>
        if r.h_left /= 0 then
          rin.h_left <= r.h_left - 1;
        else
          rin.h_left <= resize(h_bp_m1_i, h_width_c);
          rin.h_state <= ST_BP;
        end if;

      when ST_BP =>
        if r.h_left /= 0 then
          rin.h_left <= r.h_left - 1;
        else
          rin.h_left <= resize(h_act_m1_i, h_width_c);
          rin.h_state <= ST_ACT;
        end if;

      when ST_ACT =>
        if r.h_left /= 0 then
          rin.h_left <= r.h_left - 1;
        else
          rin.h_state <= ST_FP;
          rin.h_left <= resize(h_fp_m1_i, h_width_c);
        end if;
    end case;

    if v_next then
      case r.v_state is
        when ST_FP =>
          if r.v_left /= 0 then
            rin.v_left <= r.v_left - 1;
          else
            rin.v_left <= resize(v_sync_m1_i, v_width_c);
            rin.v_state <= ST_SYNC;
          end if;

        when ST_SYNC =>
          if r.v_left /= 0 then
            rin.v_left <= r.v_left - 1;
          else
            rin.v_left <= resize(v_bp_m1_i, v_width_c);
            rin.v_state <= ST_BP;
          end if;

        when ST_BP =>
          if r.v_left /= 0 then
            rin.v_left <= r.v_left - 1;
          else
            rin.v_left <= resize(v_act_m1_i, v_width_c);
            rin.v_state <= ST_ACT;
          end if;

        when ST_ACT =>
          if r.v_left /= 0 then
            rin.v_left <= r.v_left - 1;
          else
            rin.v_state <= ST_FP;
            rin.v_left <= resize(v_fp_m1_i, v_width_c);
          end if;
      end case;
    end if;
  end process;

  mealy: process(r, pixel_i, vsync_i, hsync_i) is
  begin
    period_s <= PERIOD_CONTROL;
    pixel_ready_o <= '0';
    hsync_s <= not hsync_i;
    vsync_s <= not vsync_i;

    case r.h_state is
      when ST_SYNC =>
        hsync_s <= hsync_i;
      when others =>
        null;
    end case;

    case r.v_state is
      when ST_SYNC =>
        vsync_s <= vsync_i;
        
      when ST_ACT =>
        case r.h_state is
          when ST_ACT =>
            period_s <= PERIOD_VIDEO_DATA;
            pixel_ready_o <= '1';

          when others =>
            null;
        end case;

      when others =>
        null;
    end case;
  end process;

  sof_o <= '1' when r.h_state = ST_SYNC and r.v_state = ST_SYNC and r.h_left = 0 and r.v_left = 0 else '0';
  sol_o <= '1' when r.h_state = ST_SYNC and r.v_state = ST_ACT and r.h_left = 0 else '0';
  
  encoder: work.encoder.source_stream_encoder
    port map(
      reset_n_i => reset_n_i,
      pixel_clock_i => pixel_clock_i,
      period_i => period_s,
      pixel_i(0) => byte(pixel_i.b),
      pixel_i(1) => byte(pixel_i.g),
      pixel_i(2) => byte(pixel_i.r),
      hsync_i => hsync_s,
      vsync_i => vsync_s,
      tmds_o => tmds_o
      );

end architecture;
