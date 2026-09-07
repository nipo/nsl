library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_math;

-- Scope-style color-index pixel source. Draws a graticule and a
-- continuous sine trace from scope_sine_rom. Phase is swept
-- horizontally: the leftmost column is at phase_origin_i, each pixel
-- advances by phase_increment_i, both expressed as a fraction of a
-- full period scaled to 2**16. zoom_i halves the trace amplitude.
--
-- Trace samples are prefetched two columns ahead of the output so the
-- one-cycle ROM latency stays hidden; each column fills the rows
-- between its own sample and the next column's, keeping the trace
-- continuous on steep slopes.
entity scope_renderer is
  generic(
    h_act_c : natural;
    v_act_c : natural;
    color_count_l2_c : natural;
    background_color_c : natural;
    grid_color_c : natural;
    trace_color_c : natural;
    trace_amplitude_c : natural;
    grid_pitch_l2_c : natural := 6
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    sof_i : in std_ulogic;
    sol_i : in std_ulogic;
    color_ready_i : in std_ulogic;
    color_valid_o : out std_ulogic;
    color_o : out unsigned(color_count_l2_c-1 downto 0);

    phase_increment_i : in unsigned(15 downto 0);
    phase_origin_i : in unsigned(15 downto 0);
    zoom_i : in std_ulogic := '0';
    grid_enable_i : in std_ulogic := '1'
    );
end entity;

architecture beh of scope_renderer is

  constant x_width_c : natural := nsl_math.arith.log2(h_act_c);
  constant y_width_c : natural := nsl_math.arith.log2(v_act_c);
  constant rom_address_width_c : natural := 9;
  constant sample_width_c : natural := nsl_math.arith.log2(trace_amplitude_c) + 2;

  subtype row_t is unsigned(y_width_c-1 downto 0);
  subtype sample_t is signed(sample_width_c-1 downto 0);

  function sample_row(sample : sample_t; zoom : std_ulogic) return row_t is
    variable v, c : signed(sample_width_c downto 0);
  begin
    if zoom = '1' then
      v := resize(shift_right(sample, 1), v'length);
    else
      v := resize(sample, v'length);
    end if;
    c := to_signed(v_act_c / 2, c'length) - v;
    return resize(unsigned(c), y_width_c);
  end function;

  type state_t is (
    ST_IDLE,
    ST_FETCH_CUR,
    ST_FETCH_NEXT,
    ST_RUN
    );

  type regs_t is
  record
    state : state_t;
    x : unsigned(x_width_c-1 downto 0);
    y : row_t;
    first_line : boolean;
    phase : unsigned(15 downto 0);
    s_cur : row_t;
    s_next : row_t;
    pending : boolean;
  end record;

  signal r, rin : regs_t;

  signal rom_sample_s : sample_t;

begin

  rom: work.top.scope_sine_rom
    generic map(
      address_width_c => rom_address_width_c,
      value_width_c => sample_width_c,
      amplitude_c => trace_amplitude_c
      )
    port map(
      clock_i => clock_i,
      address_i => r.phase(15 downto 16-rom_address_width_c),
      value_o => rom_sample_s
      );

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_IDLE;
      r.first_line <= true;
    end if;
  end process;

  transition: process(r, sof_i, sol_i, color_ready_i,
                      phase_increment_i, phase_origin_i, zoom_i,
                      rom_sample_s) is
  begin
    rin <= r;

    case r.state is
      when ST_IDLE =>
        null;

      when ST_FETCH_CUR =>
        rin.phase <= r.phase + phase_increment_i;
        rin.state <= ST_FETCH_NEXT;

      when ST_FETCH_NEXT =>
        rin.s_cur <= sample_row(rom_sample_s, zoom_i);
        rin.phase <= r.phase + phase_increment_i;
        rin.pending <= true;
        rin.state <= ST_RUN;

      when ST_RUN =>
        if color_ready_i = '1' then
          if r.pending then
            rin.s_cur <= sample_row(rom_sample_s, zoom_i);
          else
            rin.s_cur <= r.s_next;
          end if;
          rin.pending <= true;
          rin.phase <= r.phase + phase_increment_i;
          rin.x <= r.x + 1;
          if r.x = h_act_c - 1 then
            rin.state <= ST_IDLE;
          end if;
        else
          if r.pending then
            rin.s_next <= sample_row(rom_sample_s, zoom_i);
          end if;
          rin.pending <= false;
        end if;
    end case;

    if sol_i = '1' then
      rin.state <= ST_FETCH_CUR;
      rin.x <= (others => '0');
      rin.phase <= phase_origin_i;
      rin.pending <= false;
      if r.first_line then
        rin.y <= (others => '0');
        rin.first_line <= false;
      else
        rin.y <= r.y + 1;
      end if;
    end if;

    if sof_i = '1' then
      rin.state <= ST_IDLE;
      rin.first_line <= true;
    end if;
  end process;

  mealy: process(r, rom_sample_s, zoom_i, grid_enable_i) is
    variable s_next : row_t;
    variable trace, grid : boolean;
  begin
    if r.pending then
      s_next := sample_row(rom_sample_s, zoom_i);
    else
      s_next := r.s_next;
    end if;

    trace := (r.s_cur <= r.y and r.y <= s_next)
             or (s_next <= r.y and r.y <= r.s_cur);
    grid := r.x(grid_pitch_l2_c-1 downto 0) = 0
            or r.y(grid_pitch_l2_c-1 downto 0) = 0;

    if r.state = ST_RUN then
      color_valid_o <= '1';
    else
      color_valid_o <= '0';
    end if;

    if r.state = ST_RUN and trace then
      color_o <= to_unsigned(trace_color_c, color_count_l2_c);
    elsif r.state = ST_RUN and grid and grid_enable_i = '1' then
      color_o <= to_unsigned(grid_color_c, color_count_l2_c);
    else
      color_o <= to_unsigned(background_color_c, color_count_l2_c);
    end if;
  end process;

end architecture;
