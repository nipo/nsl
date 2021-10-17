library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, nsl_spdif, nsl_logic, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use nsl_spdif.framer.all;
use work.hdmi.all;
use work.audio.all;
use nsl_logic.logic.all;

entity hdmi_spdif_di_encoder is
  generic(
    audio_clock_divisor_c: natural := 4096
    );
  port(
    reset_n_i : in std_ulogic;
    clock_i : in std_ulogic;

    enable_i : in std_ulogic := '1';

    cts_send_i : in std_ulogic;
    cts_i : in unsigned(19 downto 0);

    -- SPDIF block input
    block_ready_o : out std_ulogic;
    block_valid_i : in std_ulogic := '1';
    block_user_i : in std_ulogic_vector(0 to 191);
    block_channel_status_i : in std_ulogic_vector(0 to 191);
    block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

    -- PCM data input
    ready_o : out std_ulogic;
    valid_i : in std_ulogic := '1';
    a_i, b_i: in nsl_spdif.blocker.channel_data_t;

    -- HDMI SOF marker from encoder
    sof_i : in std_ulogic := '0';

    -- DI stream
    di_valid_o : out std_ulogic;
    di_ready_i : in std_ulogic;
    di_o : out work.hdmi.data_island_t
    );
end entity;

architecture beh of hdmi_spdif_di_encoder is

  type state_t is (
    ST_RESET,
    ST_GET_SAMPLE,
    ST_PUT_DI,
    ST_FILL_ACR,
    ST_FILL_AIF
    );

  type regs_t is
  record
    state: state_t;
    acr_send: boolean;
    aif_send: boolean;
    di: data_island_t;
  end record;

  function di_acr_init return data_island_t
  is
    variable ret : data_island_t;
  begin
    ret.packet_type := di_type_audio_sample;
    ret.hb := (others => x"00");
    ret.pb := (others => "--------");
    return ret;
  end function;

  function di_acr_shift(di: data_island_t) return data_island_t
  is
    variable ret : data_island_t := di;
  begin
    ret.hb(1) := di.hb(1)(7 downto 4) & "0" & di.hb(1)(3 downto 1);
    ret.hb(2) := "0" & di.hb(2)(7 downto 5) & "0" & di.hb(2)(3 downto 1);
    ret.pb := di.pb(7 to 27) & from_hex("00000000000000");
    return ret;
  end function;

  function di_acr_set(di: data_island_t;
                      block_start: in std_ulogic;
                      channel: in std_ulogic;
                      frame: in frame_t) return data_island_t
  is
    variable ret: data_island_t := di;
    variable parity : std_ulogic := xor_reduce(
      std_ulogic_vector(frame.audio & frame.aux)
      & frame.channel_status
      & frame.user
      & frame.invalid);
  begin
    ret.hb(1)(3) := '1';
    ret.hb(2)(3) := '0';
    if channel = '0' then
      ret.hb(2)(7) := block_start;
      ret.pb(21 to 23) := to_le(frame.audio & frame.aux);
      ret.pb(27)(3) := parity;
      ret.pb(27)(2) := frame.channel_status;
      ret.pb(27)(1) := frame.user;
      ret.pb(27)(0) := frame.invalid;
    else
      ret.pb(24 to 26) := to_le(frame.audio & frame.aux);
      ret.pb(27)(7) := parity;
      ret.pb(27)(6) := frame.channel_status;
      ret.pb(27)(5) := frame.user;
      ret.pb(27)(4) := frame.invalid;
    end if;
    return ret;
  end function;
  
  signal r, rin: regs_t;

  signal block_start_s, channel_s, valid_s, ready_s : std_ulogic;
  signal frame_s : frame_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.acr_send <= false;
      r.aif_send <= false;
    end if;
  end process;

  transition: process(r,
                      block_start_s, channel_s, frame_s, valid_s,
                      di_ready_i, sof_i, cts_i, cts_send_i, enable_i) is
  begin
    rin <= r;
    
    if sof_i = '1' then
      rin.aif_send <= true;
    end if;

    if cts_send_i = '1' then
      rin.acr_send <= true;
    end if;
      
    case r.state is
      when ST_RESET =>
        if enable_i = '1' then
          rin.state <= ST_GET_SAMPLE;
          rin.di <= di_acr_init;
        end if;

      when ST_GET_SAMPLE =>
        if valid_s = '1' then
          rin.di <= di_acr_set(r.di, block_start_s, channel_s, frame_s);
          if channel_s = '0' then
            rin.di <= di_acr_set(di_acr_shift(r.di), block_start_s, channel_s, frame_s);
          elsif r.di.hb(1)(0) = '1' then
            rin.state <= ST_PUT_DI;
          end if;
        end if;

      when ST_PUT_DI =>
        if di_ready_i = '1' then
          rin.di <= di_acr_init;
          if enable_i = '0' then
            rin.state <= ST_RESET;
          elsif r.acr_send then
            rin.state <= ST_FILL_ACR;
          elsif r.aif_send then
            rin.state <= ST_FILL_AIF;
          else
            rin.state <= ST_GET_SAMPLE;
          end if;
        end if;

      when ST_FILL_ACR =>
        rin.acr_send <= false;
        rin.di <= di_audio_clock_regen(cts_i, to_unsigned(audio_clock_divisor_c, 20));
        rin.state <= ST_PUT_DI;

      when ST_FILL_AIF =>
        rin.aif_send <= false;
        rin.di <= di_audio_infoframe(
          ct => 0,
          cc => 0,
          ss => 0,
          sf => 0,
          cxt => 0,
          ca => 0,
          lsv => 0,
          lfepbl0 => 0,
          dm => 0
          );
        rin.state <= ST_PUT_DI;
    end case;
  end process;

  moore: process(r) is
  begin
    di_valid_o <= '0';
    ready_s <= '0';
    di_o <= r.di;

    case r.state is
      when ST_PUT_DI =>
        di_valid_o <= '1';

      when ST_GET_SAMPLE =>
        ready_s <= '1';

      when others =>
        null;
    end case;
  end process;

  blocker: nsl_spdif.blocker.block_tx
    port map(
    clock_i => clock_i,
    reset_n_i => reset_n_i,

    block_ready_o => block_ready_o,
    block_valid_i => block_valid_i,
    block_user_i => block_user_i,
    block_channel_status_i => block_channel_status_i,
    block_channel_status_aesebu_auto_crc_i => block_channel_status_aesebu_auto_crc_i,

    ready_o => ready_o,
    valid_i => valid_i,
    a_i => a_i,
    b_i => b_i,

    block_start_o => block_start_s,
    channel_o => channel_s,
    frame_o => frame_s,
    valid_o => valid_s,
    ready_i => ready_s
    );
end architecture;
