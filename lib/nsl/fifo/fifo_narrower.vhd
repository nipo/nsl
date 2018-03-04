library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo_narrower is
  generic(
    parts : integer;
    width_out : integer
    );
  port(
    p_resetn  : in  std_ulogic;
    p_clk     : in  std_ulogic;

    p_out_data    : out std_ulogic_vector(width_out-1 downto 0);
    p_out_ready    : in  std_ulogic;
    p_out_valid : out std_ulogic;

    p_in_data   : in  std_ulogic_vector(parts*width_out-1 downto 0);
    p_in_valid  : in  std_ulogic;
    p_in_ready : out std_ulogic
    );
end fifo_narrower;

architecture rtl of fifo_narrower is

  constant width_in : integer := width_out * parts;

  signal r_buffer, s_buffer : std_ulogic_vector(width_in-1 downto 0);
  signal r_filled, s_filled : std_ulogic_vector(parts-1 downto 0);
  signal s_can_take, s_has_data, s_can_shift : std_ulogic;

begin

  reg: process (p_clk, p_resetn)
  begin  -- process reg
    if p_resetn = '0' then
      r_filled <= (others => '0');
      r_buffer <= (others => '0');
    elsif p_clk'event and p_clk = '1' then  -- rising clock edge
      r_filled <= s_filled;
      r_buffer <= s_buffer;
    end if;
  end process reg;

  s_can_shift <= r_filled(0);
  s_can_take <= (not r_filled(0)) or (not r_filled(1) and p_out_ready);
  s_has_data <= r_filled(0);

  process (s_can_shift, s_can_take, s_has_data, r_filled, p_in_valid, p_out_ready, r_buffer)
  begin
    s_filled <= r_filled;
    s_buffer <= r_buffer;

    if s_can_take = '1' and p_in_valid = '1' then
      s_filled <= (others => '1');
      s_buffer <= p_in_data;
    elsif s_can_shift = '1' and p_out_ready = '1' then
      s_filled(parts-1) <= '0';
      s_filled(parts-2 downto 0) <= r_filled(parts-1 downto 1);
      s_buffer(width_in - width_out - 1 downto 0) <= r_buffer(width_in - 1 downto width_out);
    end if;
  end process;
  
  p_out_valid <= r_filled(0);
  p_in_ready <= s_can_take;
  p_out_data <= r_buffer(width_out - 1 downto 0);
   
end rtl;
