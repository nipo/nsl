library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_data, work;
use nsl_data.bytestream.all;
use nsl_data.endian.all;
use work.ubx.all;

entity ubx_nav_timegps is
  generic(
    epoch_offset_c : natural := 0
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    byte_i : in byte;
    valid_i : in std_ulogic;

    second_o : out unsigned(31 downto 0);
    leap_s_o : out signed(7 downto 0);
    tow_valid_o : out std_ulogic;
    week_valid_o : out std_ulogic;
    leap_valid_o : out std_ulogic;
    tacc_o : out unsigned(31 downto 0);
    strobe_o : out std_ulogic
    );
end entity;

architecture beh of ubx_nav_timegps is

  -- Longest frame the framer agrees to follow.  Beyond this, the
  -- length field is taken as noise rather than as a frame to skip
  -- over, and the hunt restarts immediately.
  constant max_payload_c : natural := 1024;

  constant ms_per_second_c : natural := 1000;
  constant divide_step_c : natural := 32;
  -- 604800 needs 20 bits.
  constant week_seconds_width_c : natural := 20;

  subtype pos_t is integer range 0 to ubx_nav_timegps_length_c-1;

  -- The states from ST_DIVIDE on ignore valid_i, so bytes arriving
  -- while the seconds count is being computed are dropped, and with
  -- them the frame they belong to.  The computation is over in less
  -- than a hundred cycles; at the navigation rates the receiver
  -- offers, the next frame is millions of cycles away.
  type state_t is (
    ST_SYNC1,
    ST_SYNC2,
    ST_CLASS,
    ST_ID,
    ST_LEN_L,
    ST_LEN_H,
    ST_PAYLOAD,
    ST_CK_A,
    ST_CK_B,
    ST_DIVIDE,
    ST_MULTIPLY,
    ST_ADD_TOW,
    ST_ADD_EPOCH,
    ST_EMIT
    );

  type regs_t is
  record
    state: state_t;

    ck_a, ck_b: unsigned(7 downto 0);
    msg_class, msg_id: byte;
    length_l: unsigned(7 downto 0);
    left: integer range 0 to max_payload_c-1;
    pos: pos_t;
    timegps: boolean;

    itow_b: byte_string(0 to 3);
    week_b: byte_string(0 to 1);
    leap_b: byte;
    valid_b: byte;
    tacc_b: byte_string(0 to 3);

    div_num: unsigned(31 downto 0);
    div_rem: unsigned(9 downto 0);
    div_quot: unsigned(31 downto 0);
    mul_a: unsigned(31 downto 0);
    mul_b: unsigned(week_seconds_width_c-1 downto 0);
    acc: unsigned(31 downto 0);
    step: integer range 0 to divide_step_c-1;

    second: unsigned(31 downto 0);
    leap_s: signed(7 downto 0);
    tow_valid, week_valid, leap_valid: std_ulogic;
    tacc: unsigned(31 downto 0);
    strobe: std_ulogic;
  end record;

  signal r, rin: regs_t;

begin

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_SYNC1;
      r.second <= (others => '0');
      r.leap_s <= (others => '0');
      r.tow_valid <= '0';
      r.week_valid <= '0';
      r.leap_valid <= '0';
      r.tacc <= (others => '0');
      r.strobe <= '0';
    end if;
  end process;

  transition: process(r, byte_i, valid_i) is
    variable data : unsigned(7 downto 0);
    variable ck_a_next : unsigned(7 downto 0);
    variable msg_len : unsigned(15 downto 0);
    variable shifted : unsigned(10 downto 0);
    variable diff : unsigned(11 downto 0);
  begin
    rin <= r;
    rin.strobe <= '0';

    data := unsigned(byte_i);
    ck_a_next := r.ck_a + data;
    msg_len := data & r.length_l;
    shifted := r.div_rem & r.div_num(r.div_num'left);
    diff := ('0' & shifted) - ms_per_second_c;

    case r.state is
      when ST_SYNC1 =>
        if valid_i = '1' and byte_i = ubx_sync1_c then
          rin.state <= ST_SYNC2;
        end if;

      when ST_SYNC2 =>
        if valid_i = '1' then
          if byte_i = ubx_sync2_c then
            rin.state <= ST_CLASS;
          elsif byte_i /= ubx_sync1_c then
            rin.state <= ST_SYNC1;
          end if;
        end if;

      when ST_CLASS =>
        if valid_i = '1' then
          rin.msg_class <= byte_i;
          rin.ck_a <= data;
          rin.ck_b <= data;
          rin.state <= ST_ID;
        end if;

      when ST_ID =>
        if valid_i = '1' then
          rin.msg_id <= byte_i;
          rin.ck_a <= ck_a_next;
          rin.ck_b <= r.ck_b + ck_a_next;
          rin.state <= ST_LEN_L;
        end if;

      when ST_LEN_L =>
        if valid_i = '1' then
          rin.length_l <= data;
          rin.ck_a <= ck_a_next;
          rin.ck_b <= r.ck_b + ck_a_next;
          rin.state <= ST_LEN_H;
        end if;

      when ST_LEN_H =>
        if valid_i = '1' then
          rin.ck_a <= ck_a_next;
          rin.ck_b <= r.ck_b + ck_a_next;
          rin.pos <= 0;
          rin.timegps <= r.msg_class = ubx_class_nav_c
                         and r.msg_id = ubx_id_nav_timegps_c
                         and msg_len = ubx_nav_timegps_length_c;

          if msg_len > max_payload_c then
            rin.state <= ST_SYNC1;
          elsif msg_len = 0 then
            rin.state <= ST_CK_A;
          else
            rin.left <= to_integer(msg_len) - 1;
            rin.state <= ST_PAYLOAD;
          end if;
        end if;

      when ST_PAYLOAD =>
        if valid_i = '1' then
          rin.ck_a <= ck_a_next;
          rin.ck_b <= r.ck_b + ck_a_next;

          if r.timegps then
            if r.pos >= ubx_timegps_off_itow_c
              and r.pos < ubx_timegps_off_itow_c + 4 then
              rin.itow_b(r.pos - ubx_timegps_off_itow_c) <= byte_i;
            end if;

            if r.pos >= ubx_timegps_off_week_c
              and r.pos < ubx_timegps_off_week_c + 2 then
              rin.week_b(r.pos - ubx_timegps_off_week_c) <= byte_i;
            end if;

            if r.pos = ubx_timegps_off_leap_c then
              rin.leap_b <= byte_i;
            end if;

            if r.pos = ubx_timegps_off_valid_c then
              rin.valid_b <= byte_i;
            end if;

            if r.pos >= ubx_timegps_off_tacc_c
              and r.pos < ubx_timegps_off_tacc_c + 4 then
              rin.tacc_b(r.pos - ubx_timegps_off_tacc_c) <= byte_i;
            end if;
          end if;

          if r.left = 0 then
            rin.state <= ST_CK_A;
          else
            rin.left <= r.left - 1;
            if r.pos /= pos_t'high then
              rin.pos <= r.pos + 1;
            end if;
          end if;
        end if;

      when ST_CK_A =>
        if valid_i = '1' then
          if data = r.ck_a then
            rin.state <= ST_CK_B;
          else
            rin.state <= ST_SYNC1;
          end if;
        end if;

      when ST_CK_B =>
        if valid_i = '1' then
          rin.state <= ST_SYNC1;

          if data = r.ck_b and r.timegps then
            rin.div_num <= from_le(r.itow_b);
            rin.div_rem <= (others => '0');
            rin.div_quot <= (others => '0');
            rin.step <= divide_step_c - 1;
            rin.state <= ST_DIVIDE;
          end if;
        end if;

      when ST_DIVIDE =>
        rin.div_num <= r.div_num(r.div_num'left-1 downto 0) & '0';

        if diff(diff'left) = '0' then
          rin.div_rem <= diff(r.div_rem'range);
          rin.div_quot <= r.div_quot(r.div_quot'left-1 downto 0) & '1';
        else
          rin.div_rem <= shifted(r.div_rem'range);
          rin.div_quot <= r.div_quot(r.div_quot'left-1 downto 0) & '0';
        end if;

        if r.step = 0 then
          rin.mul_a <= resize(from_le(r.week_b), rin.mul_a'length);
          rin.mul_b <= to_unsigned(gps_week_seconds_c, rin.mul_b'length);
          rin.acc <= (others => '0');
          rin.step <= week_seconds_width_c - 1;
          rin.state <= ST_MULTIPLY;
        else
          rin.step <= r.step - 1;
        end if;

      when ST_MULTIPLY =>
        rin.mul_a <= r.mul_a(r.mul_a'left-1 downto 0) & '0';
        rin.mul_b <= '0' & r.mul_b(r.mul_b'left downto 1);

        if r.mul_b(0) = '1' then
          rin.acc <= r.acc + r.mul_a;
        end if;

        if r.step = 0 then
          rin.state <= ST_ADD_TOW;
        else
          rin.step <= r.step - 1;
        end if;

      when ST_ADD_TOW =>
        rin.acc <= r.acc + r.div_quot;
        rin.state <= ST_ADD_EPOCH;

      when ST_ADD_EPOCH =>
        rin.acc <= r.acc + to_unsigned(epoch_offset_c, r.acc'length);
        rin.state <= ST_EMIT;

      when ST_EMIT =>
        rin.second <= r.acc;
        rin.leap_s <= signed(r.leap_b);
        rin.tow_valid <= r.valid_b(0);
        rin.week_valid <= r.valid_b(1);
        rin.leap_valid <= r.valid_b(2);
        rin.tacc <= from_le(r.tacc_b);
        rin.strobe <= '1';
        rin.state <= ST_SYNC1;
    end case;
  end process;

  moore: process(r) is
  begin
    second_o <= r.second;
    leap_s_o <= r.leap_s;
    tow_valid_o <= r.tow_valid;
    week_valid_o <= r.week_valid;
    leap_valid_o <= r.leap_valid;
    tacc_o <= r.tacc;
    strobe_o <= r.strobe;
  end process;

end architecture;
