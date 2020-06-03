library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_ws, nsl_color;

entity ws_2812_framed is
  generic(
    color_order : string := "GRB";
    clk_freq_hz : natural;
    error_ns : natural := 150;
    t0h_ns : natural := 350;
    t0l_ns : natural := 1360;
    t1h_ns : natural := 1360;
    t1l_ns : natural := 350
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    led_o : out std_ulogic;

    cmd_i   : in nsl_bnoc.framed.framed_req;
    cmd_o   : out nsl_bnoc.framed.framed_ack;

    rsp_o   : out nsl_bnoc.framed.framed_req;
    rsp_i   : in nsl_bnoc.framed.framed_ack
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
    color   : nsl_color.rgb.rgb24;
  end record;

  signal r, rin : regs_t;

  signal s_valid        :  std_ulogic;
  signal s_ready       :  std_ulogic;

begin

  ck : process (clock_i, reset_n_i)
  begin
    if reset_n_i = '0' then
      r.state <= ST_RESET;
    elsif rising_edge(clock_i) then
      r <= rin;
    end if;
  end process;

  transition : process (r, cmd_i, rsp_i, s_ready)
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_GET_R;

      when ST_GET_R =>
        if cmd_i.valid = '1' then
          rin.color.r <= unsigned(cmd_i.data);
          rin.last <= cmd_i.last;
          if cmd_i.last = '1' then
            rin.state <= ST_RUN;
          else
            rin.state <= ST_GET_G;
          end if;
        end if;

      when ST_GET_G =>
        if cmd_i.valid = '1' then
          rin.color.g <= unsigned(cmd_i.data);
          if cmd_i.last = '1' then
            rin.state <= ST_RUN;
          else
            rin.state <= ST_GET_B;
          end if;
        end if;

      when ST_GET_B =>
        if cmd_i.valid = '1' then
          rin.color.b <= unsigned(cmd_i.data);
          rin.last <= cmd_i.last;
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
        if rsp_i.ready = '1' then
          rin.state <= ST_GET_R;
        end if;
    end case;
  end process;

  moore : process (r)
  begin
    cmd_o.ready <= '0';
    rsp_o.valid <= '0';
    rsp_o.data <= (others => '-');
    rsp_o.last <= '-';
    s_valid <= '0';

    case r.state is
      when ST_GET_R | ST_GET_G | ST_GET_B =>
        cmd_o.ready <= '1';

      when ST_RUN =>
        s_valid <= '1';

      when ST_RSP_PUT =>
        rsp_o.valid <= '1';
        rsp_o.last <= '1';
        rsp_o.data <= (others => '0');

      when others =>
        null;
    end case;
  end process;

  master: nsl_ws.driver.ws_2812_driver
    generic map(
      color_order => color_order,
      clk_freq_hz => clk_freq_hz,
      error_ns => error_ns,
      t0h_ns => t0h_ns,
      t0l_ns => t0l_ns,
      t1h_ns => t1h_ns,
      t1l_ns => t1l_ns
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      led_o => led_o,
      
      color_i => r.color,
      last_i => r.last,
      valid_i => s_valid,
      ready_o => s_ready
      );
  
end architecture;
