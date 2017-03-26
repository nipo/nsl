library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
    p_write   : out std_ulogic
    );
end event_monitor;

architecture rtl of event_monitor is
  
  subtype word_t is std_ulogic_vector(data_width-1 downto 0);
  type pipeline_t is array(sync_depth downto 0) of word_t;
  signal r_resync : pipeline_t;

  signal r_count : std_ulogic_vector(delta_width-1 downto 0);
  signal s_count : std_ulogic_vector(delta_width downto 0);
  signal s_diff : word_t;
  signal s_changed : std_ulogic;

begin

  reg: process (p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r_resync <= (others => (others => '0'));
      r_count <= (others => '0');
    elsif rising_edge(p_clk) then
      r_resync(sync_depth - 1 downto 0) <= r_resync(sync_depth downto 1);
      r_resync(sync_depth) <= p_in;
      r_count <= s_count(delta_width - 1 downto 0);
    end if;
  end process reg;

  s_count <= std_ulogic_vector((to_unsigned(0,1) & unsigned(r_count)) + 1) when s_changed = '0' else (others => '0');
  s_diff <= r_resync(0) xor r_resync(1);
  s_changed <= '0' when unsigned(s_diff) = 0 else '1';
  p_write <= s_count(delta_width) or s_changed;
  p_delta <= r_count;
  p_data <= r_resync(1);
  
end rtl;
