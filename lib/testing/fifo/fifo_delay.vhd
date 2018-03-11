library ieee;
use ieee.std_logic_1164.all;

entity fifo_delay is
  generic (
    width   : integer;
    latency : natural range 1 to 8
    );
  port (
    p_resetn : in std_ulogic;
    p_clk    : in std_ulogic;

    p_in_data  : in  std_ulogic_vector(width-1 downto 0);
    p_in_valid : in  std_ulogic;
    p_in_ready : out std_ulogic;

    p_out_data  : out std_ulogic_vector(width-1 downto 0);
    p_out_ready : in  std_ulogic;
    p_out_valid : out std_ulogic
    );
end fifo_delay;

architecture rtl of fifo_delay is

  type regs_t is
  record
    delay : std_ulogic_vector(latency-1 downto 0);
  end record;

  signal r, rin: regs_t;
  signal s_in_ready : std_ulogic;
  
begin

  p_in_ready <= r.delay(0);
  p_out_data <= p_in_data;
  p_out_valid <= p_in_valid;

  regs: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.delay <= (others => '0');
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_out_ready)
  begin
    rin <= r;

    rin.delay(latency - 2 downto 0) <= r.delay(latency - 1 downto 1);
    rin.delay(latency - 1) <= p_out_ready;
  end process;
  
end rtl;
