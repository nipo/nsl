library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_clocking;

entity event_monitor is
  generic(
    data_width : integer;
    delta_width : integer;
    sync_depth : integer
    );
  port(
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_in      : in std_ulogic_vector(data_width-1 downto 0);

    p_delta   : out std_ulogic_vector(delta_width-1 downto 0);
    p_data    : out std_ulogic_vector(data_width-1 downto 0);
    p_valid   : out std_ulogic
    );
end event_monitor;

architecture rtl of event_monitor is

  type regs_t is
  record
    cur, old : std_ulogic_vector(data_width-1 downto 0);
    count : unsigned(delta_width-1 downto 0);

    out_valid : std_ulogic;
    out_delta : unsigned(delta_width-1 downto 0);
    out_value : std_ulogic_vector(data_width-1 downto 0);
  end record;

  signal s_changed : std_ulogic;
  signal s_resync : std_ulogic_vector(data_width-1 downto 0);
  
  signal r, rin: regs_t;
  
begin

  reg: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.cur <= (others => '0');
      r.old <= (others => '0');
      r.count <= (others => '0');
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process reg;

  resync_in: nsl_clocking.async.async_sampler
    generic map(
      cycle_count_c => 2,
      data_width_c => data_width
      )
    port map(
      clock_i => p_clk,
      data_i => p_in,
      data_o => s_resync
      );
  
  s_changed <= '1' when r.cur /= r.old or r.count = (r.count'range => '1') else '0';

  transition: process(r, s_resync, s_changed)
  begin
    rin <= r;

    rin.out_valid <= '0';
    rin.out_value <= (others => '-');
    rin.out_delta <= (others => '-');

    rin.count <= r.count + 1;
    rin.old <= r.cur;
    rin.cur <= s_resync;

    if s_changed = '1' then
      rin.count <= (others => '0');
      rin.out_valid <= '1';
      rin.out_value <= r.cur;
      rin.out_delta <= r.count;
    end if;
  end process;

  p_valid <= r.out_valid;
  p_delta <= std_ulogic_vector(r.out_delta);
  p_data <= r.out_value;
  
end rtl;
