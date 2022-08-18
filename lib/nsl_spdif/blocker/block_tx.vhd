library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_data;
use nsl_data.crc.all;
use work.spdif.all;
use work.framer.all;
use work.blocker.all;
  
entity block_tx is
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    block_ready_o : out std_ulogic;
    block_valid_i : in std_ulogic := '1';
    block_user_i : in std_ulogic_vector(0 to 191);
    block_channel_status_i : in std_ulogic_vector(0 to 191);
    block_channel_status_aesebu_auto_crc_i : in std_ulogic := '0';

    ready_o : out std_ulogic;
    valid_i : in std_ulogic := '1';
    a_i, b_i: in channel_data_t;

    block_start_o : out std_ulogic;
    channel_o : out std_ulogic;
    frame_o : out frame_t;
    valid_o : out std_ulogic;
    ready_i : in std_ulogic
    );
end entity;

architecture beh of block_tx is

  type state_t is (
    ST_RESET,
    ST_GET_BLOCK,
    ST_GET_FRAME,
    ST_PUT_A,
    ST_PUT_B
    );
  
  type regs_t is
  record
    state: state_t;
    user: std_ulogic_vector(0 to 191);
    channel_status: std_ulogic_vector(0 to 191);
    do_crc: boolean;
    channel_status_crc: aesebu_crc_t;
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

  transition: process(r, block_user_i, block_channel_status_i,
                      block_channel_status_aesebu_auto_crc_i,
                      valid_i, block_valid_i,
                      a_i, b_i,
                      ready_i) is
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_GET_BLOCK;

      when ST_GET_BLOCK =>
        if block_valid_i = '1' then
          rin.state <= ST_GET_FRAME;
          rin.frame_to_go <= 191;
          rin.channel_status <= block_channel_status_i;
          rin.do_crc <= block_channel_status_aesebu_auto_crc_i = '1';
          rin.channel_status_crc <= crc_init(aesebu_crc_params_c);
          rin.user <= block_user_i;
        end if;

      when ST_GET_FRAME =>
        if valid_i = '1' then
          rin.a <= a_i;
          rin.b <= b_i;
          rin.state <= ST_PUT_A;
          rin.channel_status_crc <= crc_update(aesebu_crc_params_c,
                                               r.channel_status_crc,
                                               r.channel_status(0));
          if r.frame_to_go = 7 and r.do_crc then
            rin.channel_status(0 to 7) <= nsl_data.endian.bitswap(std_ulogic_vector(r.channel_status_crc));
          end if;
        end if;

      when ST_PUT_A =>
        if ready_i = '1' then
          rin.state <= ST_PUT_B;
        end if;

      when ST_PUT_B =>
        if ready_i = '1' then
          rin.channel_status <= r.channel_status(1 to 191) & '-';
          rin.user <= r.user(1 to 191) & '-';

          if r.frame_to_go = 0 then
            rin.state <= ST_GET_BLOCK;
          else
            rin.frame_to_go <= r.frame_to_go - 1;
            rin.state <= ST_GET_FRAME;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    block_start_o <= '0';
    ready_o <= '0';
    block_ready_o <= '0';
    valid_o <= '0';
    frame_o.audio <= (others => '-');
    frame_o.aux <= (others => '-');
    frame_o.invalid <= '1';
    frame_o.user <= '-';
    frame_o.channel_status <= '-';
    channel_o <= '-';

    case r.state is
      when ST_RESET =>
        null;

      when ST_GET_BLOCK =>
        block_ready_o <= '1';

      when ST_GET_FRAME =>
        ready_o <= '1';

      when ST_PUT_A =>
        if r.frame_to_go = 191 then
          block_start_o <= '1';
        end if;
        channel_o <= '0';
        frame_o.audio <= r.a.audio;
        frame_o.aux <= r.a.aux;
        frame_o.invalid <= not r.a.valid;
        valid_o <= '1';

      when ST_PUT_B =>
        channel_o <= '1';
        frame_o.audio <= r.b.audio;
        frame_o.aux <= r.b.aux;
        frame_o.invalid <= not r.b.valid;
        valid_o <= '1';
    end case;

    frame_o.user <= r.user(0);
    frame_o.channel_status <= r.channel_status(0);
  end process;

end architecture;
