library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl, signalling;

entity ws_2812_framed is
  generic(
    clk_freq_hz : natural;
    cycle_time_ns : natural := 208
    );
  port(
    p_clk : in std_ulogic;
    p_resetn : in std_ulogic;

    p_data : out std_ulogic;

    p_cmd_val   : in nsl.framed.framed_req;
    p_cmd_ack   : out nsl.framed.framed_ack;

    p_rsp_val   : out nsl.framed.framed_req;
    p_rsp_ack   : in nsl.framed.framed_ack
    );
end entity;

architecture rtl of ws_2812_framed is

  type state_t is (
    ST_RESET,
    ST_GET_R,
    ST_GET_G,
    ST_GET_B,
    ST_RUN,
    ST_RSP_PUT
    );
  
  type regs_t is record
    state   : state_t;
    last    : std_ulogic;
    color   : signalling.color.rgb24;
  end record;

  signal r, rin : regs_t;

  signal s_valid        :  std_ulogic;
  signal s_ready       :  std_ulogic;

begin

  ck : process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition : process (r, p_cmd_val, p_rsp_ack, s_ready)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_GET_R;

      when ST_GET_R =>
        if p_cmd_val.valid = '1' then
          rin.color.r <= to_integer(unsigned(p_cmd_val.data));
          rin.last <= p_cmd_val.last;
          if p_cmd_val.last = '1' then
            rin.state <= ST_RUN;
          else
            rin.state <= ST_GET_G;
          end if;
        end if;

      when ST_GET_G =>
        if p_cmd_val.valid = '1' then
          rin.color.g <= to_integer(unsigned(p_cmd_val.data));
          if p_cmd_val.last = '1' then
            rin.state <= ST_RUN;
          else
            rin.state <= ST_GET_B;
          end if;
        end if;

      when ST_GET_B =>
        if p_cmd_val.valid = '1' then
          rin.color.b <= to_integer(unsigned(p_cmd_val.data));
          rin.last <= p_cmd_val.last;
          rin.state <= ST_RUN;
        end if;

      when ST_RUN =>
        if s_ready = '1' then
          if r.last = '1' then
            rin.state <= ST_RSP_PUT;
          else
            rin.state <= ST_GET_R;
          end if;
        end if;

      when ST_RSP_PUT =>
        if p_rsp_ack.ready = '1' then
          rin.state <= ST_GET_R;
        end if;
    end case;
  end process;

  moore : process (r)
  begin
    p_cmd_ack.ready <= '0';
    p_rsp_val.valid <= '0';
    p_rsp_val.data <= (others => '-');
    p_rsp_val.last <= '-';
    s_valid <= '0';

    case r.state is
      when ST_GET_R | ST_GET_G | ST_GET_B =>
        p_cmd_ack.ready <= '1';

      when ST_RUN =>
        s_valid <= '1';

      when ST_RSP_PUT =>
        p_rsp_val.valid <= '1';
        p_rsp_val.last <= '1';
        p_rsp_val.data <= (others => '0');

      when others =>
        null;
    end case;
  end process;

  master: nsl.ws.ws_2812_driver
    generic map(
      clk_freq_hz => clk_freq_hz,
      cycle_time_ns => cycle_time_ns
      )
    port map(
      p_clk => p_clk,
      p_resetn => p_resetn,

      p_data => p_data,
      
      p_led => r.color,
      p_last => r.last,
      p_valid => s_valid,
      p_ready => s_ready
      );
  
end architecture;
