library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_video;

entity raster_counter is
  generic(
    geometry_c: nsl_video.mode.geometry_t;
    pixel_count_c: positive := 1
    );
  port(
    clock_i: in std_ulogic;
    reset_n_i: in std_ulogic;

    enable_i: in std_ulogic := '1';

    x_o: out unsigned(nsl_video.mode.x_width(geometry_c)-1 downto 0);
    y_o: out unsigned(nsl_video.mode.y_width(geometry_c)-1 downto 0);

    sof_o: out std_ulogic;
    eol_o: out std_ulogic;
    eof_o: out std_ulogic;
    keep_o: out std_ulogic_vector(0 to pixel_count_c-1);

    valid_o: out std_ulogic;
    ready_i: in std_ulogic
    );
end entity;

architecture beh of raster_counter is

  constant x_width_c: natural := nsl_video.mode.x_width(geometry_c);
  constant y_width_c: natural := nsl_video.mode.y_width(geometry_c);

  -- Coordinate the last beat of a line starts at.
  constant x_last_c: natural
    := ((geometry_c.width - 1) / pixel_count_c) * pixel_count_c;
  constant y_last_c: natural := geometry_c.height - 1;

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_SCAN
    );

  type regs_t is
  record
    state: state_t;
    x: unsigned(x_width_c-1 downto 0);
    y: unsigned(y_width_c-1 downto 0);
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

  transition: process(r, enable_i, ready_i) is
    variable eol, eof: boolean;
  begin
    rin <= r;

    eol := r.x = x_last_c;
    eof := eol and r.y = y_last_c;

    case r.state is
      when ST_RESET =>
        rin.x <= (others => '0');
        rin.y <= (others => '0');
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        if enable_i = '1' then
          rin.state <= ST_SCAN;
        end if;

      when ST_SCAN =>
        if ready_i = '1' then
          if eof then
            rin.x <= (others => '0');
            rin.y <= (others => '0');
            if enable_i = '0' then
              rin.state <= ST_IDLE;
            end if;
          elsif eol then
            rin.x <= (others => '0');
            rin.y <= r.y + 1;
          else
            rin.x <= r.x + pixel_count_c;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
    variable last_kept: natural range 0 to pixel_count_c-1;
  begin
    x_o <= r.x;
    y_o <= r.y;

    if r.state = ST_SCAN then
      valid_o <= '1';
    else
      valid_o <= '0';
    end if;

    if r.x = 0 and r.y = 0 then
      sof_o <= '1';
    else
      sof_o <= '0';
    end if;

    if r.x = x_last_c then
      eol_o <= '1';
    else
      eol_o <= '0';
    end if;

    if r.x = x_last_c and r.y = y_last_c then
      eof_o <= '1';
    else
      eof_o <= '0';
    end if;

    -- Only the beat closing a line can hold pixels past its end, and
    -- only when a line does not hold a whole number of beats.
    last_kept := pixel_count_c - 1;
    if r.x = x_last_c then
      last_kept := (geometry_c.width - 1) mod pixel_count_c;
    end if;

    for i in keep_o'range
    loop
      if i <= last_kept then
        keep_o(i) <= '1';
      else
        keep_o(i) <= '0';
      end if;
    end loop;
  end process;

end architecture;
