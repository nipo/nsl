library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use work.spdif.all;
use work.framer.all;
use work.blocker.all;
use nsl_data.crc.all;
  
entity block_rx is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    synced_i : in std_ulogic;
    block_start_i : in std_ulogic;
    channel_i : in std_ulogic;
    frame_i : in frame_t;
    parity_ok_i : in std_ulogic;
    valid_i : in std_ulogic;

    synced_o : out std_ulogic;

    block_valid_o : out std_ulogic;
    block_user_o : out std_ulogic_vector(0 to 191);
    block_channel_status_o : out std_ulogic_vector(0 to 191);
    block_channel_status_aesebu_crc_ok_o : out std_ulogic;

    valid_o : out std_ulogic;
    a_o, b_o: out channel_data_t
    );
end entity;

architecture beh of block_rx is

  type state_t is (
    ST_RESET,
    ST_WAIT_SOB,
    ST_WAIT_NEXT_SOB,
    ST_WAIT_A,
    ST_WAIT_B,
    ST_PUT_FRAME,
    ST_PUT_BLOCK
    );
  
  type regs_t is
  record
    state: state_t;
    user: std_ulogic_vector(0 to 191);
    channel_status: std_ulogic_vector(0 to 191);
    channel_status_crc: aesebu_crc;
    frame_to_go: integer range 0 to 191;

    a, b: channel_data_t;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, synced_i, block_start_i, channel_i, frame_i, parity_ok_i, valid_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_WAIT_SOB;

      when ST_WAIT_SOB | ST_WAIT_NEXT_SOB =>
        if valid_i = '1' then
          rin.a.aux <= frame_i.aux;
          rin.a.audio <= frame_i.audio;
          rin.a.valid <= not frame_i.invalid and parity_ok_i;

          if r.state = ST_WAIT_NEXT_SOB then
            rin.state <= ST_WAIT_SOB;
          end if;
        end if;

      when ST_WAIT_A =>
        if valid_i = '1' then
          rin.a.aux <= frame_i.aux;
          rin.a.audio <= frame_i.audio;
          rin.a.valid <= not frame_i.invalid and parity_ok_i;
          if channel_i = '0' then
            rin.state <= ST_WAIT_B;
          end if;
        end if;

      when ST_WAIT_B =>
        if valid_i = '1' then
          rin.b.aux <= frame_i.aux;
          rin.b.audio <= frame_i.audio;
          rin.b.valid <= not frame_i.invalid and parity_ok_i;

          rin.user <= r.user(1 to 191) & frame_i.user;
          rin.channel_status <= r.channel_status(1 to 191) & frame_i.channel_status;
          rin.channel_status_crc <= aesebu_crc_update(r.channel_status_crc,
                                                      frame_i.channel_status);

          if channel_i = '1' then
            rin.state <= ST_PUT_FRAME;
          end if;
        end if;

      when ST_PUT_FRAME =>
        if r.frame_to_go = 0 then
          rin.state <= ST_PUT_BLOCK;
        else
          rin.frame_to_go <= r.frame_to_go - 1;
          rin.state <= ST_WAIT_A;
        end if;

      when ST_PUT_BLOCK =>
        rin.state <= ST_WAIT_NEXT_SOB;
    end case;

    if valid_i = '1' and block_start_i = '1' and channel_i = '0' then
      rin.state <= ST_WAIT_B;
      rin.frame_to_go <= 191;
      rin.channel_status_crc <= aesebu_crc_init;
    end if;

    if synced_i = '0' then
      rin.state <= ST_WAIT_SOB;
    end if;
  end process;

  moore: process(r) is
  begin
    block_channel_status_aesebu_crc_ok_o <= '0';
    block_valid_o <= '0';
    valid_o <= '0';
    synced_o <= '0';

    case r.state is
      when ST_RESET | ST_WAIT_SOB =>
        null;

      when ST_PUT_FRAME =>
        valid_o <= '1';
        synced_o <= '1';

      when ST_PUT_BLOCK =>
        block_valid_o <= '1';
        synced_o <= '1';

      when ST_WAIT_A | ST_WAIT_B | ST_WAIT_NEXT_SOB =>
        synced_o <= '1';
    end case;

    block_channel_status_o <= r.channel_status;
    if r.channel_status_crc = x"00" then
      block_channel_status_aesebu_crc_ok_o <= '1';
    end if;
    block_user_o <= r.user;

    a_o.valid <= r.a.valid;
    a_o.audio <= r.a.audio;
    a_o.aux <= r.a.aux;

    b_o.valid <= r.b.valid;
    b_o.audio <= r.b.audio;
    b_o.aux <= r.b.aux;
  end process;
  
end architecture;
