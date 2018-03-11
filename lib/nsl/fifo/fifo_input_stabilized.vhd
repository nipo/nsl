library ieee;
use ieee.std_logic_1164.all;

entity fifo_input_stabilized is
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
end fifo_input_stabilized;

architecture rtl of fifo_input_stabilized is

  type regs_t is
  record
    stable : natural range 0 to latency;
  end record;

  signal r, rin: regs_t;
  
begin

  p_in_ready <= p_out_ready when r.stable = latency else '0';
  p_out_data <= p_in_data;
  p_out_valid <= p_in_valid and p_out_ready when r.stable = latency else '0';

  regs: process(p_clk, p_resetn)
  begin
    if p_resetn = '0' then
      r.stable <= 0;
    elsif rising_edge(p_clk) then
      r <= rin;
    end if;
  end process;

  transition: process(r, p_out_ready)
  begin
    rin <= r;

    if p_out_ready = '0' then
      rin.stable <= 0;
    elsif r.stable /= latency then
      rin.stable <= r.stable + 1;
    end if;
  end process;

end rtl;
