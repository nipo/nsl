library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_color, nsl_math, nsl_line_coding, nsl_data, nsl_video, work, nsl_dvi;
use work.hdmi.all;
use work.encoder.all;
use nsl_dvi.encoder.all;
use nsl_dvi.dvi.all;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_data.crc.all;

entity hdmi_13_encoder is
  generic(
    config_c : nsl_video.pixel_stream.config_t;
    channel_map_c : nsl_dvi.encoder.channel_map_t := nsl_dvi.encoder.channel_map_rgb_c;
    vendor_name_c: string := "NSL";
    product_description_c: string := "HDMI Encoder";
    source_type_c: integer := 0
    );
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
    

    -- Asserted every cycle pixel data is taken by encoder
    pixel_i : in nsl_video.pixel_stream.master_t;
    pixel_o : out nsl_video.pixel_stream.slave_t;

    synced_o : out std_ulogic;

    -- Data island insertion option. 
    di_valid_i : in std_ulogic := '0';
    di_ready_o : out std_ulogic;
    di_i : in data_island_t := di_null;
    
    tmds_o : out nsl_dvi.dvi.symbol_vector_t
    );
end entity;

architecture beh of hdmi_13_encoder is

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

  constant min_vb_left_for_island_c : natural :=
    2 -- Video leading guard
    + 8 -- Video Preamble
    + 4 -- Gap (>= 4)
    + 2 -- DI Trailing guard
    + 32 -- DI
    + 2 -- DI Leading guard
    + 8 -- Preamble
    ;
  
  type state_t is (
    ST_FP,
    ST_SYNC,
    ST_BP,
    ST_ACT
    );

  type di_state_t is (
    DI_IDLE,
    DI_PRE,
    DI_PRE_GB,
    DI_DATA_FIRST,
    DI_DATA,
    DI_TRAIL_GB
    );

  type subpacket_t is
  record
    data: std_ulogic_vector(0 to 55);
    bch: di_bch_t;
  end record;

  type subpacket_vector_t is array(natural range <>) of subpacket_t;
  
  type packet_header_t is
  record
    data: std_ulogic_vector(0 to 23);
    bch: di_bch_t;
  end record;

  constant video_info_di_c : data_island_t := di_avi_rgb;
  
  function di_subpacket_ingress(di: data_island_t;
                                index: natural range 0 to 3) return subpacket_t
  is
    variable ret: subpacket_t;
    variable code: unsigned(55 downto 0) := from_le(di.pb(index*7 to index*7+6));
  begin
    ret.data := bitswap(std_ulogic_vector(code));
    ret.bch := (others => '0');
    return ret;
  end function;

  function di_header_ingress(di: data_island_t) return packet_header_t
  is
    variable ret: packet_header_t;
  begin
    ret.data(0 to 7) := bitswap(di.packet_type);
    ret.data(8 to 15) := bitswap(di.hb(1));
    ret.data(16 to 23) := bitswap(di.hb(2));
    ret.bch := (others => '0');
    return ret;
  end function;

  type regs_t is
  record
    v_left : v_count_t;
    v_state: state_t;

    h_left : h_count_t;
    h_state: state_t;

    di_state : di_state_t;
    di_can_take: natural range 0 to 17;
    di_left: natural range 0 to 31;
    di_subpacket: subpacket_vector_t(0 to 3);
    di_header: packet_header_t;

    may_take_di: boolean;
    send_video_info: boolean;
  end record;
  
  signal r, rin : regs_t;

  signal period_s : nsl_dvi.dvi.period_t;
  signal di_hdr_s: std_ulogic_vector(1 downto 0);
  signal di_data_s: std_ulogic_vector(7 downto 0);

  signal hsync_s, vsync_s: std_ulogic;

  signal sof_s, sol_s, ready_s, valid_s: std_ulogic;
  signal stream_pixel_s: nsl_video.pixel_stream.pixel_t;
  signal pixel_s: nsl_data.bytestream.byte_string(0 to 2);

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
      r.di_state <= DI_IDLE;
      r.di_left <= 0;
      r.send_video_info <= false;
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
                      v_act_m1_i,
                      di_valid_i,
                      di_i) is
    variable take_di, v_next: boolean;
  begin
    rin <= r;
    
    rin.may_take_di <= false;

    take_di := false;
    v_next := false;
    
    case r.di_state is
      when DI_IDLE =>
        if di_valid_i = '1' and r.may_take_di then
          take_di := true;
        end if;
        if r.di_left /= 0 then
          rin.di_left <= r.di_left - 1;
        else
          rin.may_take_di <= r.h_left >= min_vb_left_for_island_c
                             and not (r.v_state = ST_ACT and r.h_state = ST_ACT);
        end if;

      when DI_PRE =>
        if r.di_left = 0 then
          rin.di_state <= DI_PRE_GB;
          rin.di_left <= 1;
        else
          rin.di_left <= r.di_left - 1;
        end if;

      when DI_PRE_GB =>
        if r.di_left = 0 then
          rin.di_state <= DI_DATA_FIRST;
          rin.di_left <= 31;
        else
          rin.di_left <= r.di_left - 1;
        end if;

      when DI_DATA_FIRST | DI_DATA =>
        rin.di_state <= DI_DATA;

        rin.di_header.data <= r.di_header.data(1 to 23) & "-";
        rin.di_header.bch <= di_bch(r.di_header.bch, r.di_header.data(0 to 0));
        if r.di_left = 8 then
          rin.di_header.data <= (others => '-');
          rin.di_header.data(0 to 7) <= std_ulogic_vector(di_bch(r.di_header.bch, r.di_header.data(0 to 0)));
        end if;

        for i in 0 to 3
        loop
          rin.di_subpacket(i).data <= r.di_subpacket(i).data(2 to 55) & "--";
          rin.di_subpacket(i).bch <= di_bch(r.di_subpacket(i).bch, r.di_subpacket(i).data(0 to 1));
          if r.di_left = 4 then
            rin.di_subpacket(i).data <= (others => '-');
            rin.di_subpacket(i).data(0 to 7) <= std_ulogic_vector(di_bch(r.di_subpacket(i).bch, r.di_subpacket(i).data(0 to 1)));
          end if;
        end loop;

        if r.di_left = 1 then
          rin.may_take_di <= r.h_left >= min_vb_left_for_island_c
                             and r.di_can_take /= 0;
        end if;
        
        if r.di_left = 0 then
          if di_valid_i = '1' and r.may_take_di then
            take_di := true;
          else
            rin.di_state <= DI_TRAIL_GB;
            rin.di_left <= 1;
          end if;
        else
          rin.di_left <= r.di_left - 1;
        end if;

      when DI_TRAIL_GB =>
        if r.di_left = 0 then
          rin.di_state <= DI_IDLE;
          rin.di_left <= 3;
        else
          rin.di_left <= r.di_left - 1;
        end if;
    end case;

    if take_di then
      for i in 0 to 3
      loop
        rin.di_subpacket(i) <= di_subpacket_ingress(di_i, i);
      end loop;
      rin.di_header <= di_header_ingress(di_i);
    elsif r.send_video_info and r.may_take_di then
      take_di := true;
      rin.send_video_info <= false;

      for i in 0 to 3
      loop
        rin.di_subpacket(i) <= di_subpacket_ingress(video_info_di_c, i);
      end loop;
      rin.di_header <= di_header_ingress(video_info_di_c);
    end if;

    if take_di then
      rin.may_take_di <= false;
      if r.di_state = DI_IDLE then
        rin.di_state <= DI_PRE;
        rin.di_left <= 7;
        rin.di_can_take <= 17;
      else
        rin.di_state <= DI_DATA;
        rin.di_can_take <= r.di_can_take - 1;
        rin.di_left <= 31;
      end if;
    end if;

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
          rin.di_left <= 31;
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
            rin.send_video_info <= true;
          end if;
      end case;
    end if;
  end process;

  di_ready_o <= '1' when r.may_take_di else '0';

  mealy: process(r, vsync_i, hsync_i) is
  begin
    period_s <= PERIOD_CONTROL;
    ready_s <= '0';
    hsync_s <= not hsync_i;
    vsync_s <= not vsync_i;
    di_hdr_s <= "--";
    di_data_s <= "--------";

    case r.di_state is
      when DI_PRE =>
        period_s <= PERIOD_DI_PRE;

      when DI_DATA_FIRST | DI_DATA =>
        period_s <= PERIOD_DI_DATA;
        di_hdr_s(0) <= r.di_header.data(0);
        if r.di_state = DI_DATA_FIRST then
          di_hdr_s(1) <= '0';
        else
          di_hdr_s(1) <= '1';
        end if;
        for i in 0 to 3
        loop
          di_data_s(i) <= r.di_subpacket(i).data(0);
          di_data_s(4+i) <= r.di_subpacket(i).data(1);
        end loop;

      when DI_TRAIL_GB | DI_PRE_GB =>
        period_s <= PERIOD_DI_GUARD;

      when DI_IDLE =>
        null;
    end case;

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
          when ST_BP =>
            if r.h_left <= 1 then
              period_s <= PERIOD_VIDEO_GUARD;
            elsif r.h_left <= 9 then
              period_s <= PERIOD_VIDEO_PRE;
            end if;

          when ST_ACT =>
            period_s <= PERIOD_VIDEO_DATA;
            ready_s <= '1';

          when others =>
            null;
        end case;

      when others =>
        null;
    end case;
  end process;

  sof_s <= '1' when r.h_state = ST_SYNC and r.v_state = ST_SYNC and r.h_left = 0 and r.v_left = 0 else '0';
  sol_s <= '1' when r.h_state = ST_SYNC and r.v_state = ST_ACT and r.h_left = 0 else '0';

  unframer: nsl_video.raster.pixel_stream_unframer
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => pixel_clock_i,
      reset_n_i => reset_n_i,
      in_i => pixel_i,
      in_o => pixel_o,
      sof_i => sof_s,
      sol_i => sol_s,
      ready_i => ready_s,
      valid_o => valid_s,
      pixel_o => stream_pixel_s,
      synced_o => synced_o
      );

  -- The wire cannot wait, so a pixel the stream did not hold has to
  -- have something go out in its place.
  pixel_s <= nsl_dvi.encoder.channel_bytes(config_c, channel_map_c, stream_pixel_s)
             when valid_s = '1' else nsl_dvi.encoder.channel_bytes_starved_c;

  encoder: nsl_dvi.encoder.source_stream_encoder
    port map(
      reset_n_i => reset_n_i,
      pixel_clock_i => pixel_clock_i,
      period_i => period_s,
      pixel_i => pixel_s,
      hsync_i => hsync_s,
      vsync_i => vsync_s,
      di_hdr_i => di_hdr_s,
      di_data_i => di_data_s,
      tmds_o => tmds_o
      );

end architecture;
